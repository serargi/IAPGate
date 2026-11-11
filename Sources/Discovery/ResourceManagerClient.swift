import Foundation
import CloudGateCore
import Auth

/// Lists organizations, folders, and projects via Cloud Resource
/// Manager **v3**. The hierarchy is walked one level at a time using
/// the `parent` parameter (direct children only, not descendants),
/// which is what lets the UI load folders/subfolders/projects lazily.
///
/// Network calls go through the injected `HTTPClient`; JSON parsing is
/// pure and unit-tested. Permission errors (403) are handled as
/// "nothing visible here" rather than hard failures where appropriate.
public struct ResourceManagerClient: Sendable {

    private let http: HTTPClient
    private let tokenProvider: AccessTokenProviding
    private let baseURL: URL

    public init(
        http: HTTPClient,
        tokenProvider: AccessTokenProviding,
        baseURL: URL = URL(string: "https://cloudresourcemanager.googleapis.com")!
    ) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
    }

    // MARK: - Organizations

    /// Searches organizations the user can view. A 403 is treated as
    /// "no visible organizations" (the user may still reach projects).
    public func listOrganizations(
        accountID: String
    ) async -> Result<[Organization], CloudGateError> {
        guard case .success(let token) = await tokenProvider.validAccessToken(for: accountID) else {
            return .failure(.make(.authenticationRequired, userMessage: "Please sign in again."))
        }

        var organizations: [Organization] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/v3/organizations:search"),
                resolvingAgainstBaseURL: false)!
            if let pageToken { components.queryItems = [URLQueryItem(name: "pageToken", value: pageToken)] }

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data, status: Int
            do { (data, status) = try await http.send(request) }
            catch { return .failure(.make(.networkTimeout, userMessage: "Network error.", technicalDetail: "orgs transport")) }

            if status == 403 { return .success(organizations) }
            guard status == 200 else { return .failure(Self.mapError(status: status, context: "organizations")) }

            let page = Self.parseOrganizations(data)
            organizations.append(contentsOf: page.organizations)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return .success(organizations)
    }

    // MARK: - Folders (direct children of a parent)

    /// Lists folders whose direct parent is `parent`
    /// ("organizations/123" or "folders/456"). Does NOT recurse.
    public func listFolders(
        accountID: String,
        parent: String
    ) async -> Result<[Folder], CloudGateError> {
        guard case .success(let token) = await tokenProvider.validAccessToken(for: accountID) else {
            return .failure(.make(.authenticationRequired, userMessage: "Please sign in again."))
        }

        var folders: [Folder] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/v3/folders"),
                resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "parent", value: parent)]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data, status: Int
            do { (data, status) = try await http.send(request) }
            catch { return .failure(.make(.networkTimeout, userMessage: "Network error.", technicalDetail: "folders transport")) }

            if status == 403 { return .success(folders) }
            guard status == 200 else { return .failure(Self.mapError(status: status, context: "folders")) }

            let page = Self.parseFolders(data)
            folders.append(contentsOf: page.folders)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return .success(folders.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() })
    }

    // MARK: - Projects (direct children of a parent)

    /// Lists active projects whose direct parent is `parent`
    /// ("organizations/123" or "folders/456"). Does NOT recurse.
    public func listProjects(
        accountID: String,
        parent: String
    ) async -> Result<[Project], CloudGateError> {
        guard case .success(let token) = await tokenProvider.validAccessToken(for: accountID) else {
            return .failure(.make(.authenticationRequired, userMessage: "Please sign in again."))
        }

        var projects: [Project] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/v3/projects"),
                resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "parent", value: parent)]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data, status: Int
            do { (data, status) = try await http.send(request) }
            catch { return .failure(.make(.networkTimeout, userMessage: "Network error.", technicalDetail: "projects transport")) }

            if status == 403 { return .success(projects) }
            guard status == 200 else { return .failure(Self.mapError(status: status, context: "projects")) }

            let page = Self.parseProjects(data)
            projects.append(contentsOf: page.projects)
            pageToken = page.nextPageToken
        } while pageToken != nil

        let active = projects.filter { ($0.lifecycleState ?? "ACTIVE") == "ACTIVE" }
        return .success(active.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() })
    }

    /// Searches ALL projects the user can access, regardless of parent.
    /// Used to compute the "No organization / No visible parent" bucket.
    public func searchAllProjects(
        accountID: String
    ) async -> Result<[Project], CloudGateError> {
        guard case .success(let token) = await tokenProvider.validAccessToken(for: accountID) else {
            return .failure(.make(.authenticationRequired, userMessage: "Please sign in again."))
        }

        var projects: [Project] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/v3/projects:search"),
                resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "query", value: "state:ACTIVE")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data, status: Int
            do { (data, status) = try await http.send(request) }
            catch { return .failure(.make(.networkTimeout, userMessage: "Network error.", technicalDetail: "project search transport")) }

            if status == 403 { return .success(projects) }
            guard status == 200 else { return .failure(Self.mapError(status: status, context: "project search")) }

            let page = Self.parseProjects(data)
            projects.append(contentsOf: page.projects)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return .success(projects)
    }

    // MARK: - Parsing (pure, tested)

    public struct OrgPage: Equatable { public let organizations: [Organization]; public let nextPageToken: String? }
    public struct FolderPage: Equatable { public let folders: [Folder]; public let nextPageToken: String? }
    public struct ProjectPage: Equatable { public let projects: [Project]; public let nextPageToken: String? }

    public static func parseOrganizations(_ data: Data) -> OrgPage {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OrgPage(organizations: [], nextPageToken: nil)
        }
        let raw = (obj["organizations"] as? [[String: Any]]) ?? []
        let orgs = raw.compactMap { item -> Organization? in
            guard let name = item["name"] as? String else { return nil }
            let display = (item["displayName"] as? String) ?? name
            return Organization(id: name, displayName: display)
        }
        return OrgPage(organizations: orgs, nextPageToken: obj["nextPageToken"] as? String)
    }

    public static func parseFolders(_ data: Data) -> FolderPage {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FolderPage(folders: [], nextPageToken: nil)
        }
        let raw = (obj["folders"] as? [[String: Any]]) ?? []
        let folders = raw.compactMap { item -> Folder? in
            guard let name = item["name"] as? String else { return nil }           // "folders/123"
            // v3 only returns ACTIVE-relevant folders; skip DELETE_REQUESTED.
            if let state = item["state"] as? String, state != "ACTIVE" { return nil }
            let display = (item["displayName"] as? String) ?? name
            let parent = (item["parent"] as? String) ?? ""
            return Folder(id: name, displayName: display, parent: parent)
        }
        return FolderPage(folders: folders, nextPageToken: obj["nextPageToken"] as? String)
    }

    public static func parseProjects(_ data: Data) -> ProjectPage {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProjectPage(projects: [], nextPageToken: nil)
        }
        let raw = (obj["projects"] as? [[String: Any]]) ?? []
        let projects = raw.compactMap { item -> Project? in
            // v3 uses "projectId", "displayName", "name"="projects/NUM", "parent", "state".
            guard let projectID = item["projectId"] as? String else { return nil }
            let display = (item["displayName"] as? String) ?? projectID
            let number = (item["name"] as? String)?.replacingOccurrences(of: "projects/", with: "")
            let state = item["state"] as? String
            let parent = item["parent"] as? String   // "organizations/.." or "folders/.."
            return Project(
                id: projectID, displayName: display, number: number,
                parent: parent, lifecycleState: state)
        }
        return ProjectPage(projects: projects, nextPageToken: obj["nextPageToken"] as? String)
    }

    public static func mapError(status: Int, context: String) -> CloudGateError {
        switch status {
        case 401:
            return .make(.authenticationRequired, userMessage: "Please sign in again.",
                         technicalDetail: "\(context) 401")
        case 403:
            return .make(.insufficientCloudPermissions,
                         userMessage: "You don't have permission to view these resources.",
                         technicalDetail: "\(context) 403")
        case 429, 500, 502, 503:
            return .make(.networkTimeout, userMessage: "Temporary error. Try again.",
                         technicalDetail: "\(context) \(status)")
        default:
            return .make(.discoveryIncomplete,
                         userMessage: "Could not load \(context).",
                         technicalDetail: "\(context) status=\(status)")
        }
    }
}
