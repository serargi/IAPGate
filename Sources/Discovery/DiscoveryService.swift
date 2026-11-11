import Foundation
import CloudGateCore

/// The direct children of a hierarchy node: subfolders plus projects
/// that sit directly under it. Loaded one level at a time.
public struct NodeChildren: Equatable, Sendable {
    public let folders: [Folder]
    public let projects: [Project]

    public init(folders: [Folder], projects: [Project]) {
        self.folders = folders
        self.projects = projects
    }

    public var isEmpty: Bool { folders.isEmpty && projects.isEmpty }
}

/// High-level resource discovery the UI depends on. The hierarchy is
/// walked lazily: pick an organization, then expand folders/subfolders
/// on demand, then list a project's instances.
public protocol DiscoveryProviding: Sendable {
    /// Organizations the user can view (for the org combobox).
    func organizations(accountID: String) async -> Result<[Organization], CloudGateError>

    /// Direct children (subfolders + projects) of a parent resource
    /// name ("organizations/123" or "folders/456").
    func children(accountID: String, parent: String) async -> Result<NodeChildren, CloudGateError>

    /// Accessible projects that have no visible parent (e.g. the user
    /// lacks org/folder visibility, or they are truly parentless).
    func projectsWithoutVisibleParent(accountID: String) async -> Result<[Project], CloudGateError>

    /// Instances within a project.
    func instances(accountID: String, projectID: String) async -> Result<[Instance], CloudGateError>
}

/// Default implementation combining Resource Manager v3 + Compute.
public struct DiscoveryService: DiscoveryProviding {

    private let resourceManager: ResourceManagerClient
    private let compute: ComputeClient

    public init(resourceManager: ResourceManagerClient, compute: ComputeClient) {
        self.resourceManager = resourceManager
        self.compute = compute
    }

    public func organizations(
        accountID: String
    ) async -> Result<[Organization], CloudGateError> {
        let result = await resourceManager.listOrganizations(accountID: accountID)
        if case .success(let orgs) = result {
            return .success(orgs.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() })
        }
        return result
    }

    public func children(
        accountID: String,
        parent: String
    ) async -> Result<NodeChildren, CloudGateError> {
        // Fetch subfolders and direct projects concurrently.
        async let foldersResult = resourceManager.listFolders(accountID: accountID, parent: parent)
        async let projectsResult = resourceManager.listProjects(accountID: accountID, parent: parent)

        let folders: [Folder]
        switch await foldersResult {
        case .success(let f): folders = f
        case .failure(let e): return .failure(e)
        }
        let projects: [Project]
        switch await projectsResult {
        case .success(let p): projects = p
        case .failure(let e): return .failure(e)
        }
        return .success(NodeChildren(folders: folders, projects: projects))
    }

    public func projectsWithoutVisibleParent(
        accountID: String
    ) async -> Result<[Project], CloudGateError> {
        // Projects the user can reach but whose parent is not an
        // organization (or has no parent). This surfaces projects for
        // users without org/folder viewer, and standalone projects.
        switch await resourceManager.searchAllProjects(accountID: accountID) {
        case .failure(let e):
            return .failure(e)
        case .success(let all):
            let orphans = all.filter { project in
                guard let parent = project.parent else { return true }
                // Keep only those NOT under an organization we would show
                // in the combobox. Projects under folders are reachable by
                // walking the tree, so exclude them here to avoid dupes…
                // unless the user cannot see that folder's org at all.
                return !parent.hasPrefix("organizations/") && !parent.hasPrefix("folders/")
            }
            return .success(orphans.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() })
        }
    }

    public func instances(
        accountID: String,
        projectID: String
    ) async -> Result<[Instance], CloudGateError> {
        await compute.listInstances(accountID: accountID, projectID: projectID)
    }
}
