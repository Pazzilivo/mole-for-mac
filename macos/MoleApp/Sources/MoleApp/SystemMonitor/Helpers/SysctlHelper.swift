import Foundation

// SysctlHelper - Wrapper for sysctl system calls
struct SysctlHelper {

    /// Get a string value from sysctl
    /// - Parameter name: The sysctl name (e.g., "hw.machine")
    /// - Returns: The string value if successful, nil otherwise
    static func getString(_ name: String) -> String? {
        var size: Int = 0
        // First call to get size
        sysctlbyname(name, nil, &size, nil, 0)
        if size == 0 {
            return nil
        }

        // Allocate buffer and get actual value
        var buffer = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        if size == 0 {
            return nil
        }

        return String(cString: buffer)
    }

    /// Get an Int32 value from sysctl
    /// - Parameter name: The sysctl name (e.g., "hw.physicalcpu")
    /// - Returns: The Int32 value if successful, nil otherwise
    static func getInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        if result != 0 || size != MemoryLayout<Int32>.size {
            return nil
        }
        return value
    }

    /// Get an Int64 value from sysctl
    /// - Parameter name: The sysctl name
    /// - Returns: The Int64 value if successful, nil otherwise
    static func getInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        if result != 0 || size != MemoryLayout<Int64>.size {
            return nil
        }
        return value
    }

    /// Get a UInt64 value from sysctl
    /// - Parameter name: The sysctl name (e.g., "hw.memsize")
    /// - Returns: The UInt64 value if successful, nil otherwise
    static func getUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        if result != 0 || size != MemoryLayout<UInt64>.size {
            return nil
        }
        return value
    }

    /// Get a Double value from sysctl (for load averages, etc.)
    /// - Parameter name: The sysctl name
    /// - Returns: The Double value if successful, nil otherwise
    static func getDouble(_ name: String) -> Double? {
        var value: Double = 0
        var size = MemoryLayout<Double>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        if result != 0 || size != MemoryLayout<Double>.size {
            return nil
        }
        return value
    }

    /// Get an array of Int32 values from sysctl (for CPU counts, etc.)
    /// - Parameter name: The sysctl name
    /// - Returns: Array of Int32 values if successful, nil otherwise
    static func getInt32Array(_ name: String) -> [Int32]? {
        var size: Int = 0
        // First call to get size
        sysctlbyname(name, nil, &size, nil, 0)
        if size == 0 || size % MemoryLayout<Int32>.size != 0 {
            return nil
        }

        let count = size / MemoryLayout<Int32>.size
        var values = [Int32](repeating: 0, count: count)
        let result = sysctlbyname(name, &values, &size, nil, 0)
        if result != 0 {
            return nil
        }

        return values
    }
}