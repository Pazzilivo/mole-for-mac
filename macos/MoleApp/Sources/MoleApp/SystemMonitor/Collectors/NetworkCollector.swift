import Foundation

final class NetworkCollector: MetricCollector {
    typealias Output = [NetworkStatus]

    private var previousNetworkStats: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousCollectionTime: Date?

    func collect() async throws -> [NetworkStatus] {
        var networks: [NetworkStatus] = []
        let currentTime = Date()

        // Get network interfaces
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            return []
        }

        defer {
            freeifaddrs(ifaddrs)
        }

        var currentStats: [String: (rx: UInt64, tx: UInt64)] = [:]

        var ptr = ifaddrs
        while let addr = ptr?.pointee {
            let interface = String(cString: addr.ifa_name)
            let addrPtr = addr.ifa_addr

            // Only process AF_INET (IPv4) interfaces
            guard addrPtr.pointee.sa_family == UInt8(AF_INET) else {
                ptr = addr.ifa_next
                continue
            }

            // Filter out noise interfaces
            let ignoredInterfaces = ["lo", "awdl", "utun", "tun", "pptp", "ppp", "ipsec", "anpi"]
            if ignoredInterfaces.contains(where: { interface.hasPrefix($0) }) {
                ptr = addr.ifa_next
                continue
            }

            // Get interface statistics
            if let stats = getInterfaceStats(interface) {
                currentStats[interface] = (rx: stats.rx, tx: stats.tx)

                // Get IP address
                var ipAddress = "Unknown"
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addrPtr, socklen_t(addr.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, socklen_t(0),
                           NI_NUMERICHOST)

                if let ip = String(validatingUTF8: &hostname) {
                    ipAddress = ip
                }

                // Calculate rates if we have previous data
                var rxRate: Double = 0.0
                var txRate: Double = 0.0

                if let previous = previousNetworkStats[interface],
                   let previousTime = previousCollectionTime {
                    let timeInterval = currentTime.timeIntervalSince(previousTime)
                    if timeInterval > 0 {
                        let rxDelta = Double(stats.rx - previous.rx) / (1024.0 * 1024.0) // Convert to MB
                        let txDelta = Double(stats.tx - previous.tx) / (1024.0 * 1024.0) // Convert to MB
                        rxRate = rxDelta / timeInterval // MB/s
                        txRate = txDelta / timeInterval // MB/s
                    }
                }

                let network = NetworkStatus(
                    name: interface,
                    rxRateMBs: rxRate,
                    txRateMBs: txRate,
                    ip: ipAddress
                )

                networks.append(network)
            }

            ptr = addr.ifa_next
        }

        // Update previous stats
        previousNetworkStats = currentStats
        previousCollectionTime = currentTime

        return networks
    }

    private func getInterfaceStats(_ interface: String) -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [
            CTL_NET,
            PF_ROUTE,
            0,
            AF_INET,
            NET_RT_IFLIST,
            if_nametoindex(interface)
        ]

        var len: Int = 0
        sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0)

        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &len, nil, 0) == 0 else {
            return nil
        }

        return buffer.withUnsafeBytes { rawBuffer in
            var ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: if_msghdr.self)
            let end = ptr!.advanced(by: len)

            while ptr! < end {
                let ifMsg = ptr!.pointee
                if ifMsg.ifm_type == RTM_IFINFO {
                    // Use if_msghdr, not if_msghdr2
                    let rx = UInt64(ifMsg.ifm_data.ifi_ibytes)
                    let tx = UInt64(ifMsg.ifm_data.ifi_obytes)

                    return (rx: rx, tx: tx)
                }

                ptr = ptr!.advanced(by: Int(ifMsg.ifm_msglen))
            }

            return nil
        }
    }
}