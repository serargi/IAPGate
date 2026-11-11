import Foundation
import Observation
import Discovery
import CloudGateCore

/// Drives the resource browser:
/// organization (combobox) → folders/subfolders (lazy tree) → projects
/// → instances. Each hierarchy node loads its children on first expand.
@MainActor
@Observable
public final class BrowseController {

    public enum LoadState<T>: Sendable where T: Sendable {
        case idle
        case loading
        case loaded(T)
        case failed(CloudGateError)
    }

    // Organizations for the combobox.
    public private(set) var organizations: LoadState<[Organization]> = .idle

    /// The selected organization resource name ("organizations/123"),
    /// or the synthetic no-parent bucket id.
    public var selectedParentRootID: String?

    /// Children (subfolders + projects) keyed by parent resource name.
    public private(set) var childrenByParent: [String: LoadState<NodeChildren>] = [:]

    /// Projects without a visible parent (the "Sin organización" root).
    public private(set) var orphanProjects: LoadState<[Project]> = .idle

    /// Instances keyed by project id.
    public private(set) var instancesByProject: [String: LoadState<[Instance]>] = [:]

    public var selectedProjectID: String?

    /// Incremented on every explicit project tap, including re-taps on
    /// the already-selected project. The UI observes this to return
    /// focus to the machine list (a plain selection binding wouldn't
    /// change, so nothing would fire).
    public private(set) var projectFocusTick: Int = 0

    /// Called when the user taps a project row.
    public func focusProject(_ projectID: String) {
        selectedProjectID = projectID
        projectFocusTick += 1
    }

    /// Whether the sidebar is showing the favorites list instead of the
    /// full hierarchy.
    public var showingFavorites: Bool = false

    /// Current favorites for this account (observed by the UI).
    public private(set) var favorites: [Favorite] = []

    /// Current search text. Setting it (via `search(_:)`) kicks off a
    /// background traversal; the UI shows a flat result list, not the
    /// tree expanding step by step.
    public private(set) var searchText: String = ""

    /// A flat search hit: a folder or project whose name matches.
    public struct SearchHit: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case folder, project }
        public let kind: Kind
        public let id: String          // folders/<id> or project id
        public let displayName: String
        public let pathLabel: String   // breadcrumb, e.g. "A / B"
    }

    public enum SearchState: Sendable {
        case inactive
        /// Searching, with whatever hits have been found so far (shown
        /// incrementally so the user sees progress).
        case searching([SearchHit])
        case results([SearchHit])
    }

    public private(set) var searchState: SearchState = .inactive

    /// Synthetic id for the "no visible parent" root in the combobox.
    public static let noParentRootID = "__no_parent__"

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Caches the children of each parent across searches, so a second
    /// search (or re-search after narrowing the query) is near-instant
    /// and only the first walk hits the API.
    @ObservationIgnored private var childrenCache: [String: NodeChildren] = [:]

    /// Updates the query and (re)runs the search. Empty query clears it.
    public func search(_ text: String) {
        searchText = text
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            searchState = .inactive
            return
        }
        guard let root = selectedParentRootID, root != Self.noParentRootID else {
            searchState = .results([])
            return
        }
        searchState = .searching([])
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.runSearch(query: q, root: root)
        }
    }

    /// Walks the hierarchy under `root` with bounded parallelism,
    /// publishing matches to the UI as they are found (not only at the
    /// end), and using the children cache so repeat searches are fast.
    private func runSearch(query: String, root: String) async {
        func matches(_ name: String) -> Bool {
            name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        var found: [SearchHit] = []
        // Process the tree level by level; within a level, fetch all
        // nodes' children concurrently (capped) so hundreds of folders
        // don't serialize into hundreds of round-trips.
        var frontier: [(parent: String, path: String)] = [(root, "")]
        let maxConcurrent = 8

        while !frontier.isEmpty {
            if Task.isCancelled { return }
            var nextFrontier: [(parent: String, path: String)] = []

            // Chunk the frontier to cap concurrency.
            for chunk in frontier.chunked(into: maxConcurrent) {
                if Task.isCancelled { return }
                let results = await withTaskGroup(of: (String, String, NodeChildren?).self) { group in
                    for node in chunk {
                        group.addTask { [weak self] in
                            guard let self else { return (node.parent, node.path, nil) }
                            if let cached = await self.cachedChildren(node.parent) {
                                return (node.parent, node.path, cached)
                            }
                            switch await self.discovery.children(accountID: self.accountID, parent: node.parent) {
                            case .success(let c):
                                await self.cacheChildren(c, for: node.parent)
                                return (node.parent, node.path, c)
                            case .failure:
                                return (node.parent, node.path, nil)
                            }
                        }
                    }
                    var out: [(String, String, NodeChildren?)] = []
                    for await r in group { out.append(r) }
                    return out
                }

                var newHits: [SearchHit] = []
                for (_, path, childrenOpt) in results {
                    guard let children = childrenOpt else { continue }
                    for folder in children.folders {
                        let childPath = path.isEmpty ? folder.displayName : "\(path) / \(folder.displayName)"
                        if matches(folder.displayName) {
                            newHits.append(SearchHit(kind: .folder, id: folder.id,
                                                     displayName: folder.displayName, pathLabel: path))
                        }
                        nextFrontier.append((folder.id, childPath))
                    }
                    for project in children.projects where matches(project.displayName) {
                        newHits.append(SearchHit(kind: .project, id: project.id,
                                                 displayName: project.displayName, pathLabel: path))
                    }
                }
                if !newHits.isEmpty {
                    found.append(contentsOf: newHits)
                    found.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
                    // Publish progress so results appear as they arrive.
                    if !Task.isCancelled { searchState = .searching(found) }
                }
            }
            frontier = nextFrontier
        }

        if !Task.isCancelled { searchState = .results(found) }
    }

    private func cachedChildren(_ parent: String) -> NodeChildren? {
        childrenCache[parent]
    }
    private func cacheChildren(_ children: NodeChildren, for parent: String) {
        childrenCache[parent] = children
    }

    /// Clears the search tree cache (e.g. when switching organization).
    public func clearSearchCache() {
        childrenCache.removeAll()
    }

    @ObservationIgnored private let accountID: String
    @ObservationIgnored private let discovery: DiscoveryProviding
    @ObservationIgnored private let favoritesStore: FavoritesStore

    public init(accountID: String, discovery: DiscoveryProviding, favoritesStore: FavoritesStore) {
        self.accountID = accountID
        self.discovery = discovery
        self.favoritesStore = favoritesStore
        self.favorites = favoritesStore.all(accountID: accountID)
    }

    // MARK: - Favorites

    public func isFavorite(_ resourceID: String) -> Bool {
        favoritesStore.isFavorite(resourceID: resourceID, accountID: accountID)
    }

    /// Reloads favorites from the store. Called when the favorites view
    /// is shown, in case the list changed or the controller was built
    /// before the account was known.
    public func reloadFavorites() {
        favorites = favoritesStore.all(accountID: accountID)
    }

    public func toggleFavorite(kind: Favorite.Kind, resourceID: String, displayName: String) {
        if isFavorite(resourceID) {
            favoritesStore.remove(resourceID: resourceID, accountID: accountID)
        } else {
            favoritesStore.add(Favorite(
                kind: kind, resourceID: resourceID,
                displayName: displayName, accountID: accountID))
        }
        favorites = favoritesStore.all(accountID: accountID)
    }

    public func loadOrganizations() async {
        organizations = .loading
        switch await discovery.organizations(accountID: accountID) {
        case .success(let orgs):
            organizations = .loaded(orgs)
            // Do not auto-select: start on a placeholder so the user
            // explicitly chooses an organization.
        case .failure(let error):
            organizations = .failed(error)
        }
    }

    /// Loads children of a hierarchy node (org or folder) on first use.
    public func loadChildrenIfNeeded(parent: String) async {
        if case .loaded = childrenByParent[parent] { return }
        if case .loading = childrenByParent[parent] { return }
        childrenByParent[parent] = .loading
        switch await discovery.children(accountID: accountID, parent: parent) {
        case .success(let children): childrenByParent[parent] = .loaded(children)
        case .failure(let error): childrenByParent[parent] = .failed(error)
        }
    }

    /// Loads the projects for the "no visible parent" root.
    public func loadOrphanProjectsIfNeeded() async {
        if case .loaded = orphanProjects { return }
        if case .loading = orphanProjects { return }
        orphanProjects = .loading
        switch await discovery.projectsWithoutVisibleParent(accountID: accountID) {
        case .success(let projects): orphanProjects = .loaded(projects)
        case .failure(let error): orphanProjects = .failed(error)
        }
    }

    /// Selects a project and (re)loads its instances. Re-selecting an
    /// already-loaded project refreshes it in the background, so a VM
    /// created since the last visit shows up. The spinner only appears
    /// on the first load (when there's nothing to show yet).
    public func selectProject(_ projectID: String) async {
        selectedProjectID = projectID
        let hasData: Bool
        if case .loaded = instancesByProject[projectID] { hasData = true } else { hasData = false }
        if !hasData { instancesByProject[projectID] = .loading }

        switch await discovery.instances(accountID: accountID, projectID: projectID) {
        case .success(let vms): instancesByProject[projectID] = .loaded(vms)
        case .failure(let error):
            // On a refresh error, keep showing the data we had.
            if !hasData { instancesByProject[projectID] = .failed(error) }
        }
    }

    /// Forces a reload of the selected project's instances.
    public func refreshSelectedProject() async {
        guard let pid = selectedProjectID else { return }
        instancesByProject[pid] = .loading
        switch await discovery.instances(accountID: accountID, projectID: pid) {
        case .success(let vms): instancesByProject[pid] = .loaded(vms)
        case .failure(let error): instancesByProject[pid] = .failed(error)
        }
    }
}

private extension Array {
    /// Splits the array into consecutive chunks of at most `size`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
