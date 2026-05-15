import Foundation

/// Async semaphore for concurrent operation control
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    func tryAcquire() -> Bool {
        if value > 0 {
            value -= 1
            return true
        }
        return false
    }
}