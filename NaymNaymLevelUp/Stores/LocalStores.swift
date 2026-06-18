import Foundation

final class CodableUserDefaultsStore<Value: Codable> {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

final class UserProfileStore {
    private let store: CodableUserDefaultsStore<UserProfile>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "user-profile", defaults: defaults)
    }

    func load() -> UserProfile? { store.load() }
    func save(_ profile: UserProfile) { store.save(profile) }
    func clear() { store.clear() }
}

final class ProgressStore {
    private let store: CodableUserDefaultsStore<PlayerProgress>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "player-progress", defaults: defaults)
    }

    func load() -> PlayerProgress { store.load() ?? PlayerProgress() }
    func save(_ progress: PlayerProgress) { store.save(progress) }
    func clear() { store.clear() }
}

final class ChallengeStore {
    private let store: CodableUserDefaultsStore<[ChallengeRecord]>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "challenge-records", defaults: defaults)
    }

    func load() -> [ChallengeRecord] { store.load() ?? [] }
    func save(_ records: [ChallengeRecord]) { store.save(records) }
    func clear() { store.clear() }
}

