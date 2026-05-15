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

            // Get volume info using statfs
            var stat = statfs()
            if statfs(volumePath, &stat) != 0 {
                continue
            }

            let mount = String(cString: &stat.f_mntonname.0)
            let device = String(cString: &stat.f_mntfromname.0)
            let fstype = String(cString: &stat.f_fstypename.0)

            // Get capacity info
            let totalSpace = UInt64(stat.f_bsize) * UInt64(stat.f_blocks)
            let availableSpace = UInt64(stat.f_bsize) * UInt64(stat.f_bavail)
            let usedSpace = totalSpace - availableSpace
            let usedPercent = totalSpace > 0 ? (Double(usedSpace) / Double(totalSpace)) * 100.0 : 0.0

            // Check if external (FIXED C6: corrected logic - use AND instead of OR)
            let external = isExternalDisk(mountPath: mount)

            // Get APFS container free space for more accurate reading
            let apfsFree = getAPFSContainerFree(mountPath: mount)
            let (adjustedUsed, adjustedPercent) = if let apfsFree = apfsFree {
                let adjustedUsed = totalSpace - apfsFree
                let adjustedPercent = totalSpace > 0 ? (Double(adjustedUsed) / Double(totalSpace)) * 100.0 : 0.0
                (adjustedUsed, adjustedPercent)
            } else {
                (usedSpace, usedPercent)
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