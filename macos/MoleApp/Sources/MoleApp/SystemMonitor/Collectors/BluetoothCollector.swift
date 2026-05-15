import Foundation

final class BluetoothCollector: MetricCollector {
    typealias Output = [BluetoothDevice]

    private var cachedDevices: [BluetoothDevice] = []
    private var cacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 30 // 30 seconds

    func collect() async throws -> [BluetoothDevice] {
        // Check cache
        if Date().timeIntervalSince(cacheTime) < cacheTTL, !cachedDevices.isEmpty {
            return cachedDevices
        }

        var devices: [BluetoothDevice] = []

        // Run system_profiler SPBluetoothDataType to get Bluetooth info
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bluetoothData = json["SPBluetoothDataType"] as? [String: Any] {

                // Parse Bluetooth device info
                if let controllerData = bluetoothData.first?.value as? [String: Any] {

                    // Parse connected devices
                    if let connectedDevices = parseBluetoothDevices(controllerData, connected: true) {
                        devices.append(contentsOf: connectedDevices)
                    }

                    // Parse paired but disconnected devices
                    if let disconnectedDevices = parseBluetoothDevices(controllerData, connected: false) {
                        devices.append(contentsOf: disconnectedDevices)
                    }
                }
            }
        } catch {
            // If system_profiler fails, return empty array
            print("BluetoothCollector failed: \(error)")
        }

        // Update cache
        cachedDevices = devices
        cacheTime = Date()

        return devices
    }

    private func parseBluetoothDevices(_ data: [String: Any], connected: Bool) -> [BluetoothDevice]? {
        var devices: [BluetoothDevice] = []

        // Try to find device arrays in common keys
        let deviceKeys = ["device_title", "device_connected", "device_paired", "devices"]

        for key in deviceKeys {
            if let deviceArray = data[key] as? [[String: Any]] {
                for deviceInfo in deviceArray {
                    if let name = deviceInfo["name"] as? String,
                       let deviceConnected = deviceInfo["connected"] as? Bool {

                        // Only include devices matching our connection state filter
                        if deviceConnected == connected {
                            let battery = getBatteryLevel(deviceInfo)

                            let device = BluetoothDevice(
                                name: name,
                                connected: deviceConnected,
                                battery: battery
                            )

                            devices.append(device)
                        }
                    }
                }
            }
        }

        return devices.isEmpty ? nil : devices
    }

    private func getBatteryLevel(_ deviceInfo: [String: Any]) -> String {
        // Try different battery level keys
        let batteryKeys = ["battery_percent", "battery", "batteryLevel", "percent"]

        for key in batteryKeys {
            if let battery = deviceInfo[key] {
                if let percent = battery as? Int {
                    return "\(percent)%"
                } else if let percentString = battery as? String {
                    return percentString
                }
            }
        }

        return "Unknown"
    }
}