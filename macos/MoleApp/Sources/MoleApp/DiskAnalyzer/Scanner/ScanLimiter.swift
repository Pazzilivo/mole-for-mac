import Foundation

/// Controls concurrent scanning operations
final class ScanLimiter {
    let entrySem: AsyncSemaphore
    let dirSem: AsyncSemaphore
    let duSem: AsyncSemaphore
    let duQueueSem: AsyncSemaphore
    let fastSem: AsyncSemaphore

    init(childCount: Int = 0) {
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let numWorkers = max(min(cpuCount, ScanConfig.maxDirWorkers), 1)

        // Initialize semaphores with appropriate limits
        entrySem = AsyncSemaphore(value: numWorkers)
        dirSem = AsyncSemaphore(value: min(cpuCount * 2, ScanConfig.maxDirWorkers))
        duSem = AsyncSemaphore(value: min(4, cpuCount))
        duQueueSem = AsyncSemaphore(value: min(4, cpuCount) * 2)
        fastSem = AsyncSemaphore(value: numWorkers)
    }

    func releaseEntry() {
        Task {
            await entrySem.signal()
        }
    }
}