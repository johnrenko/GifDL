import Foundation

struct AppConfiguration {
    let appGroupID: String
    let fetchServiceBaseURL: URL

    static let `default` = AppConfiguration(
        appGroupID: "group.dev.jd.memedrop",
        fetchServiceBaseURL: URL(string: ProcessInfo.processInfo.environment["MEMEDROP_FETCH_BASE_URL"] ?? "http://192.168.1.97:8080")!
    )
}
