import Foundation

struct AppConfiguration {
    let appGroupID: String
    let fetchServiceBaseURL: URL

    private static let fetchServiceAPIKeyDefaultsKey = "MEMEDROP_API_KEY"

    static let `default` = AppConfiguration(
        appGroupID: "group.dev.jd.memedrop",
        fetchServiceBaseURL: URL(string: ProcessInfo.processInfo.environment["MEMEDROP_FETCH_BASE_URL"] ?? "https://memedrop-fetch.onrender.com")!
    )

    static var fetchServiceAPIKey: String? {
        if let environmentValue = normalizedAPIKey(
            ProcessInfo.processInfo.environment[fetchServiceAPIKeyDefaultsKey]
        ) {
            return environmentValue
        }

        return normalizedAPIKey(
            UserDefaults(suiteName: `default`.appGroupID)?.string(forKey: fetchServiceAPIKeyDefaultsKey)
        )
    }

    static func saveFetchServiceAPIKey(_ value: String?) {
        let defaults = UserDefaults(suiteName: `default`.appGroupID)
        if let value = normalizedAPIKey(value) {
            defaults?.set(value, forKey: fetchServiceAPIKeyDefaultsKey)
        } else {
            defaults?.removeObject(forKey: fetchServiceAPIKeyDefaultsKey)
        }
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
