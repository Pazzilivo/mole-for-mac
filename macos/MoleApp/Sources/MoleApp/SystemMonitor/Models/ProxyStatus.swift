import Foundation

struct ProxyStatus: Codable {
    let enabled: Bool
    let type: ProxyType
    let host: String?
    let port: Int?
    let pacURL: String?        // Proxy Auto-Config URL
    let bypassList: [String]   // Bypass domains

    enum ProxyType: String, Codable {
        case http = "HTTP"
        case https = "HTTPS"
        case socks = "SOCKS"
        case ftp = "FTP"
        case auto = "AUTO"
        case none = "NONE"
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case type
        case host
        case port
        case pacURL = "pac_url"
        case bypassList = "bypass_list"
    }
}