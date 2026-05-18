import Foundation
import DiskArbitration

final class DiskCollector: MetricCollector {
    typealias Output = [DiskStatus]

    func collect() async throws -> [DiskStatus] {
        var disks: [DiskStatus] = []

        // Get mounted volumes
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey],
            options: [.skipHiddenVolumes]
        )

        guard let volumes = mountedVolumes else {
            return []
        }

        for volumeURL in volumes {
            let volumePath = volumeURL.path

            var stat = statfs()
            if statfs(volumePath, &stat) != 0 {
                continue
            }

            let mount = Self.statfsString(from: stat.f_mntonname)
            let device = Self.statfsString(from: stat.f_mntfromname)
            let fstype = Self.statfsString(from: stat.f_fstypename)
            guard !mount.isEmpty else { continue }

            let blockSize = UInt64(max(stat.f_bsize, 0))
            let totalSpace = blockSize * UInt64(stat.f_blocks)
            let availableSpace = blockSize * UInt64(stat.f_bavail)
            let usedSpace = totalSpace > availableSpace ? totalSpace - availableSpace : 0
            let usedPercent = totalSpace > 0 ? (Double(usedSpace) / Double(totalSpace)) * 100.0 : 0.0

            let external = isExternalDisk(mountPath: mount)

            var adjustedUsed = usedSpace
            var adjustedPercent = usedPercent
            if let apfsFree = getAPFSContainerFree(mountPath: mount) {
                adjustedUsed = totalSpace > apfsFree ? totalSpace - apfsFree : usedSpace
                adjustedPercent = totalSpace > 0 ? (Double(adjustedUsed) / Double(totalSpace)) * 100.0 : 0.0
            }

            let disk = DiskStatus(
                mount: mount,
                device: device,
                used: adjustedUsed,
                total: totalSpace,
                usedPercent: adjustedPercent,
                fstype: fstype,
                external: external ?? false
            )
            disks.append(disk)
        }

        return disks
    }

    private static func statfsString<T>(from field: T) -> String {
        var field = field
        return withUnsafePointer(to: &field) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { cString in
                String(cString: cString)
            }
        }
    }

    private func isExternalDisk(mountPath: String) -> Bool? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return nil
        }

        let url = URL(fileURLWithPath: mountPath)

        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return nil
        }

        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else {
            return nil
        }

        // Check if device is internal
        if let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool {
            return !isInternal
        }

        return nil
    }

    private func getAPFSContainerFree(mountPath: String) -> UInt64? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return nil
        }

        let url = URL(fileURLWithPath: mountPath)

        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return nil
        }

        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else {
            return nil
        }

        // Use the raw key string instead of the constant
        return desc["DADiskDescriptionVolumeFreeSize" as String] as? UInt64
    }
}
