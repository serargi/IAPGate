import Foundation

/// A Google Cloud organization.
public struct Organization: Equatable, Sendable, Identifiable {
    /// Resource name, e.g. "organizations/123456789". Stable id.
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// A Google Cloud folder (a container between org and projects; folders
/// can nest inside other folders).
public struct Folder: Equatable, Sendable, Identifiable, Hashable {
    /// Resource name, e.g. "folders/123456789". Stable id.
    public let id: String
    public let displayName: String
    /// Parent resource name: "organizations/..." or "folders/...".
    public let parent: String

    public init(id: String, displayName: String, parent: String) {
        self.id = id
        self.displayName = displayName
        self.parent = parent
    }
}

/// A Google Cloud project.
public struct Project: Equatable, Sendable, Identifiable, Hashable {
    /// The project ID (e.g. "cmc-sandbox"), stable and user-visible.
    public let id: String
    public let displayName: String
    public let number: String?
    /// Parent resource name: "organizations/123", "folders/456", or nil
    /// (no parent / not visible).
    public let parent: String?
    public let lifecycleState: String?

    public init(
        id: String,
        displayName: String,
        number: String?,
        parent: String?,
        lifecycleState: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.number = number
        self.parent = parent
        self.lifecycleState = lifecycleState
    }
}

/// Operating system family of a VM, used to choose SSH vs RDP.
public enum VMOSType: String, Sendable, Equatable {
    case linux
    case windows
    case unknown
}

/// A Compute Engine instance (VM).
public struct Instance: Equatable, Sendable, Identifiable, Hashable {
    /// Stable composite id: "<project>/<zone>/<name>".
    public var id: String { "\(projectID)/\(zone)/\(name)" }
    public let name: String
    public let projectID: String
    public let zone: String
    public let status: String
    public let internalIP: String?
    public let externalIP: String?
    public let osType: VMOSType

    public init(
        name: String,
        projectID: String,
        zone: String,
        status: String,
        internalIP: String?,
        externalIP: String?,
        osType: VMOSType = .unknown
    ) {
        self.name = name
        self.projectID = projectID
        self.zone = zone
        self.status = status
        self.internalIP = internalIP
        self.externalIP = externalIP
        self.osType = osType
    }

    public static func == (lhs: Instance, rhs: Instance) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Region derived from the zone (e.g. "europe-west2-a" -> "europe-west2").
    public var region: String? {
        guard let idx = zone.lastIndex(of: "-") else { return nil }
        return String(zone[..<idx])
    }
}

/// A node in the sidebar tree: an organization, or the synthetic
/// "No organization" bucket for projects without visible org parentage.
public enum OrganizationNode: Equatable, Sendable, Identifiable {
    case organization(Organization)
    case noOrganization

    public var id: String {
        switch self {
        case .organization(let org): return org.id
        case .noOrganization: return "__no_org__"
        }
    }

    public var displayName: String {
        switch self {
        case .organization(let org): return org.displayName
        case .noOrganization: return "No organization"
        }
    }
}
