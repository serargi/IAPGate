import Foundation

/// Minimal key-value backing store. Abstracted so the preferences
/// store can be tested without touching the real `UserDefaults`
/// database, and so the dependency is injected rather than global.
public protocol KeyValueStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// Persists non-secret `Preferences`.
///
/// Secrets are never accepted here: the API only takes a `Preferences`
/// value, which has no credential fields by construction.
public final class PreferencesStore: @unchecked Sendable {

    private static let key = "com.cloudgate.preferences"

    private let store: KeyValueStore
    private let lock = NSLock()

    public init(store: KeyValueStore) {
        self.store = store
    }

    /// Loads stored preferences, falling back to defaults when nothing
    /// is stored or the stored value is unreadable (e.g. after a schema
    /// change). Never throws into the UI for a corrupt value.
    public func load() -> Preferences {
        lock.lock()
        defer { lock.unlock() }
        guard let data = store.data(forKey: Self.key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            return .default
        }
    }

    public func save(_ preferences: Preferences) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(preferences)
        store.set(data, forKey: Self.key)
    }

    /// Clears stored preferences, returning to defaults on next load.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        store.set(nil, forKey: Self.key)
    }
}

/// `UserDefaults`-backed implementation for production use.
extension UserDefaults: KeyValueStore {
    public func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            set(data as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
