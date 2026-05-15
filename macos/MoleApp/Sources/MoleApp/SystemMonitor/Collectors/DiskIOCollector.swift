import Foundation
import IOKit

final class DiskIOCollector: MetricCollector {
    typealias Output = DiskIOStatus

    private var previousIOStats: (readBytes: UInt64, writeBytes: UInt64)?
    private var previousCollectionTime: Date?

    func collect() async throws -> DiskIOStatus {
        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0

        // Get disk I/O statistics from IOKit
        if let stats = getDiskIOStats() {
            totalReadBytes = stats.readBytes
            totalWriteBytes = stats.writeBytes
        }

        // Calculate rates based on previous stats
        var readRate: Double = 0.0
        var writeRate: Double = 0.0
        let currentTime = Date()

        if let previous = previousIOStats,
           let previousTime = previousCollectionTime {
            let timeInterval = currentTime.timeIntervalSince(previousTime)
            if timeInterval > 0 {
                let readDelta = Double(totalReadBytes - previous.readBytes) / (1024.0 * 1024.0) // Convert to MB
                let writeDelta = Double(totalWriteBytes - previous.writeBytes) / (1024.0 * 1024.0) // Convert to MB
                readRate = readDelta / timeInterval // MB/s
                writeRate = writeDelta / timeInterval // MB/s
            }
        }

        // Update previous stats
        previousIOStats = (readBytes: totalReadBytes, writeBytes: totalWriteBytes)
        previousCollectionTime = currentTime

        return DiskIOStatus(
            readRate: readRate,
            writeRate: writeRate
        )
    }

    private func getDiskIOStats() -> (readBytes: UInt64, writeBytes: UInt64)? {
        // Try to get disk stats from IOKit
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        // Get all block storage drivers
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            // Get statistics property
            if let stats = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            ) {
                if let statsDict = stats.takeRetainedValue() as? [String: Any] {
                    // Extract read and write bytes
                    if let readBytes = statsDict["BytesRead"] as? UInt64 {
                        totalRead += readBytes
                    }
                    if let writeBytes = statsDict["BytesWritten"] as? UInt64 {
                        totalWrite += writeBytes
                    }
                }
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return (readBytes: totalRead, writeBytes: totalWrite)
    }
}