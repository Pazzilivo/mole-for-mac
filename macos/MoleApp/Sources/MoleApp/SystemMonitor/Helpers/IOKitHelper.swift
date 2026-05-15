import Foundation
import IOKit
import IOKit.ps

// IOKitHelper - Wrapper for IOKit framework calls
struct IOKitHelper {

    /// Get an IOKit service by matching name
    /// - Parameter name: The service name to match
    /// - Returns: The service object if found, nil otherwise
    static func getService(name: String) -> io_object_t? {
        let matchingDict = IOServiceMatching(name)
        if matchingDict == nil {
            return nil
        }

        let iterator = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict)
        if iterator == IO_OBJECT_NULL {
            return nil
        }

        return iterator
    }

    /// Get a property from an IOKit service
    /// - Parameters:
    ///   - service: The service object
    ///   - key: The property key
    /// - Returns: The property value if found and castable to type T, nil otherwise
    static func getProperty<T>(_ service: io_object_t, key: String) -> T? {
        let properties = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )

        guard let properties = properties else {
            return nil
        }

        let value = properties.takeRetainedValue() as? T
        return value
    }

    /// Release an IOKit service object
    /// - Parameter service: The service object to release
    static func release(_ service: io_object_t) {
        IOObjectRelease(service)
    }

    /// Get power source information (for battery stats)
    /// - Returns: Dictionary of battery information if available, nil otherwise
    static func getPowerSourceInfo() -> [String: Any]? {
        let snapshot = IOPSCopyPowerSourcesInfo()
        guard let snapshotValue = snapshot else {
            return nil
        }

        let info = snapshotValue.takeRetainedValue()

        var powerSources: [AnyObject]?
        if let sources = IOPSCopyPowerSourcesList(info) {
            powerSources = sources.takeRetainedValue() as? [AnyObject]
        }

        guard let sources = powerSources, !sources.isEmpty else {
            return nil
        }

        // Return first power source info (typically main battery)
        if let firstSource = sources.first as? [String: Any] {
            return firstSource
        }

        return nil
    }

    /// Get IOKit service properties as a dictionary
    /// - Parameter serviceName: The name of service
    /// - Returns: Dictionary of properties if found, nil otherwise
    static func getServiceProperties(serviceName: String) -> [String: Any]? {
        guard let service = getService(name: serviceName) else {
            return nil
        }

        let properties = IORegistryEntryCreateCFProperty(
            service,
            kIOServicePlane as CFString,
            kCFAllocatorDefault,
            0
        )

        defer {
            release(service)
        }

        guard let properties = properties else {
            return nil
        }

        return properties.takeRetainedValue() as? [String: Any]
    }
}

// Extension for getting Data properties
extension IOKitHelper {
    static func propertyGetData(_ service: io_object_t, key: String) -> Data? {
        let cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, CFStringGetSystemEncoding())
        guard let cfProperty = IORegistryEntryCreateCFProperty(service, cfKey, kCFAllocatorDefault, 0) else {
            return nil
        }

        if let data = cfProperty as? Data {
            return data
        }

        // Try to convert to NSData
        if let nsData = cfProperty as? NSData {
            return Data(referencing: nsData)
        }

        return nil
    }
}