import Foundation

/// A saved favorite: a folder or project the user pinned for quick
/// access. Stored as non-secret metadata (safe for UserDefaults).
public struct Favorite: Equatable, Sendable, Codable, Identifiable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case folder
        case project
    }

    /// Stable id of the underlying resource ("folders/123" or a project
    /// id). Used as the Favorite's own id too.
    public var id: String { resourceID }
    public let kind: Kind
    public let resourceID: String
    public let displayName: String
    /// Account the favorite belongs to (favorites are per-account).
    public let accountID: String

    public init(kind: Kind, resourceID: String, displayName: String, accountID: String) {
        self.kind = kind
        self.resourceID = resourceID
        self.displayName = displayName
        self.accountID = accountID
    }
}

/// Persists favorites. Non-secret, so backed by UserDefaults.
public protocol FavoritesStore: Sendable {
    func all(accountID: String) -> [Favorite]
    func isFavorite(resourceID: String, accountID: String) -> Bool
    func add(_ favorite: Favorite)
    func remove(resourceID: String, accountID: String)
}

/// UserDefaults-backed implementation.
public final class UserDefaultsFavoritesStore: FavoritesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.iapgate.favorites"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func load() -> [Favorite] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Favorite].self, from: data) else {
            return []
        }
        return list
    }

    private func save(_ list: [Favorite]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }

    public func all(accountID: String) -> [Favorite] {
        lock.lock(); defer { lock.unlock() }
        return load().filter { $0.accountID == accountID }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    public func isFavorite(resourceID: String, accountID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return load().contains { $0.resourceID == resourceID && $0.accountID == accountID }
    }

    public func add(_ favorite: Favorite) {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        guard !list.contains(where: {
            $0.resourceID == favorite.resourceID && $0.accountID == favorite.accountID
        }) else { return }
        list.append(favorite)
        save(list)
    }

    public func remove(resourceID: String, accountID: String) {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        list.removeAll { $0.resourceID == resourceID && $0.accountID == accountID }
        save(list)
    }
}

/// In-memory double for tests.
public final class InMemoryFavoritesStore: FavoritesStore, @unchecked Sendable {
    private var list: [Favorite] = []
    private let lock = NSLock()
    public init() {}

    public func all(accountID: String) -> [Favorite] {
        lock.lock(); defer { lock.unlock() }
        return list.filter { $0.accountID == accountID }
    }
    public func isFavorite(resourceID: String, accountID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return list.contains { $0.resourceID == resourceID && $0.accountID == accountID }
    }
    public func add(_ favorite: Favorite) {
        lock.lock(); defer { lock.unlock() }
        if !list.contains(where: { $0.resourceID == favorite.resourceID && $0.accountID == favorite.accountID }) {
            list.append(favorite)
        }
    }
    public func remove(resourceID: String, accountID: String) {
        lock.lock(); defer { lock.unlock() }
        list.removeAll { $0.resourceID == resourceID && $0.accountID == accountID }
    }
}
