import Foundation

/// Everything BetterKit restores on launch. Stored as JSON in the app's defaults domain.
/// Every field decodes with a default so new options never reset older settings.
struct AppSettings: Codable, Equatable {
    var onboardingDone = false
    var launchAtLoginInitialized = false
    var scroll = ScrollSettings()
    var display = DisplaySettings()
    var vietnamese = VietnameseSettings()
    var fan = FanSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboardingDone = c.value(.onboardingDone, default: false)
        launchAtLoginInitialized = c.value(.launchAtLoginInitialized, default: false)
        scroll = c.value(.scroll, default: ScrollSettings())
        display = c.value(.display, default: DisplaySettings())
        vietnamese = c.value(.vietnamese, default: VietnameseSettings())
        fan = c.value(.fan, default: FanSettings())
    }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
