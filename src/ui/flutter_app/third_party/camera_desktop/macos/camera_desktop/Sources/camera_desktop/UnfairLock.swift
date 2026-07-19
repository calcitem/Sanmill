import os

/// A Swift wrapper around os_unfair_lock that heap-allocates the lock to prevent
/// Swift from moving the value type, which would invalidate the lock.
final class UnfairLock {
    private let _lock: UnsafeMutablePointer<os_unfair_lock_s>

    init() {
        _lock = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock_s())
    }

    func lock() {
        os_unfair_lock_lock(_lock)
    }

    func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }
}
