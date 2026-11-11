import Foundation
import TestKit
import Discovery

func favoritesSuite() -> TestSuite {
    let s = TestSuite("Favorites")

    s.test("add, query, remove per account") { t in
        let store = InMemoryFavoritesStore()
        let fav = Favorite(kind: .project, resourceID: "cmc-sandbox",
                           displayName: "CMC", accountID: "acct-1")
        store.add(fav)
        t.expect(store.isFavorite(resourceID: "cmc-sandbox", accountID: "acct-1"))
        t.expectEqual(store.all(accountID: "acct-1").count, 1)
        // Different account doesn't see it.
        t.expect(!store.isFavorite(resourceID: "cmc-sandbox", accountID: "acct-2"))

        store.remove(resourceID: "cmc-sandbox", accountID: "acct-1")
        t.expect(!store.isFavorite(resourceID: "cmc-sandbox", accountID: "acct-1"))
    }

    s.test("adding same favorite twice is idempotent") { t in
        let store = InMemoryFavoritesStore()
        let fav = Favorite(kind: .folder, resourceID: "folders/1",
                           displayName: "F", accountID: "a")
        store.add(fav); store.add(fav)
        t.expectEqual(store.all(accountID: "a").count, 1)
    }

    return s
}
