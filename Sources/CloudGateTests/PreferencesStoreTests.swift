import Foundation
import TestKit
import CloudGateCore

final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func set(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
}

func preferencesStoreSuite() -> TestSuite {
    let s = TestSuite("PreferencesStore")

    s.test("load returns defaults when nothing stored") { t in
        let store = PreferencesStore(store: InMemoryKeyValueStore())
        t.expectEqual(store.load(), Preferences.default)
    }

    s.test("save then load round-trips") { t in
        let store = PreferencesStore(store: InMemoryKeyValueStore())
        var prefs = Preferences.default
        prefs.appearance = .dark
        prefs.language = .spanish
        prefs.defaultSSHUsername = "sgarcia"
        prefs.preferredRDPClient = "com.microsoft.rdc.macos"
        do {
            try store.save(prefs)
            t.expectEqual(store.load(), prefs)
        } catch {
            t.expect(false, "save threw: \(error)")
        }
    }

    s.test("corrupt stored value falls back to defaults") { t in
        let backing = InMemoryKeyValueStore()
        backing.set(Data("not json".utf8), forKey: "com.cloudgate.preferences")
        let store = PreferencesStore(store: backing)
        t.expectEqual(store.load(), Preferences.default)
    }

    s.test("reset returns to defaults") { t in
        let store = PreferencesStore(store: InMemoryKeyValueStore())
        var prefs = Preferences.default
        prefs.appearance = .light
        do {
            try store.save(prefs)
            store.reset()
            t.expectEqual(store.load(), Preferences.default)
        } catch {
            t.expect(false, "save threw: \(error)")
        }
    }

    s.test("recentConnectionsLimit is clamped to a bounded range") { t in
        let tooHigh = Preferences(
            appearance: .system, language: .system,
            defaultConnectionType: .ssh, defaultSSHUsername: nil,
            preferredRDPClient: nil, recentConnectionsLimit: 10_000)
        t.expectEqual(tooHigh.recentConnectionsLimit, 100)

        let negative = Preferences(
            appearance: .system, language: .system,
            defaultConnectionType: .ssh, defaultSSHUsername: nil,
            preferredRDPClient: nil, recentConnectionsLimit: -5)
        t.expectEqual(negative.recentConnectionsLimit, 0)
    }

    return s
}
