import Foundation
import CloudGateCore
import Auth

/// Lists Compute Engine instances for a project using aggregatedList,
/// which returns instances across all zones in one paged call.
public struct ComputeClient: Sendable {

    private let http: HTTPClient
    private let tokenProvider: AccessTokenProviding
    private let baseURL: URL

    public init(
        http: HTTPClient,
        tokenProvider: AccessTokenProviding,
        baseURL: URL = URL(string: "https://compute.googleapis.com")!
    ) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
    }

    public func listInstances(
        accountID: String,
        projectID: String
    ) async -> Result<[Instance], CloudGateError> {
        guard case .success(let token) = await tokenProvider.validAccessToken(for: accountID) else {
            return .failure(.make(.authenticationRequired, userMessage: "Please sign in again."))
        }

        var instances: [Instance] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/compute/v1/projects/\(projectID)/aggregated/instances"),
                resolvingAgainstBaseURL: false)!
            var items: [URLQueryItem] = [URLQueryItem(name: "maxResults", value: "500")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data, status: Int
            do { (data, status) = try await http.send(request) }
            catch { return .failure(.make(.networkTimeout, userMessage: "Network error.", technicalDetail: "instances transport")) }

            guard status == 200 else {
                return .failure(Self.mapComputeError(status: status, data: data, projectID: projectID))
            }
            let page = Self.parseInstances(data, projectID: projectID)
            instances.append(contentsOf: page.instances)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return .success(instances.sorted { $0.name < $1.name })
    }

    // MARK: - Parsing (pure, tested)

    public struct InstancePage: Equatable { public let instances: [Instance]; public let nextPageToken: String? }

    public static func parseInstances(_ data: Data, projectID: String) -> InstancePage {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return InstancePage(instances: [], nextPageToken: nil)
        }
        var result: [Instance] = []
        // aggregatedList returns { items: { "zones/europe-west2-a": { instances: [...] }, ... } }
        if let items = obj["items"] as? [String: Any] {
            for (zoneKey, value) in items {
                guard let scope = value as? [String: Any],
                      let list = scope["instances"] as? [[String: Any]] else { continue }
                let zone = zoneKey.replacingOccurrences(of: "zones/", with: "")
                for vm in list {
                    guard let name = vm["name"] as? String else { continue }
                    let status = (vm["status"] as? String) ?? "UNKNOWN"
                    let (internalIP, externalIP) = Self.extractIPs(vm)
                    result.append(Instance(
                        name: name, projectID: projectID, zone: zone,
                        status: status, internalIP: internalIP, externalIP: externalIP,
                        osType: Self.detectOS(vm)))
                }
            }
        }
        return InstancePage(instances: result, nextPageToken: obj["nextPageToken"] as? String)
    }

    /// Detects the OS family from the boot disk's guestOsFeatures /
    /// licenses. A WINDOWS guest-OS feature is the reliable signal; the
    /// license URL containing "windows" is a fallback. Anything else is
    /// treated as Linux (the common default for Compute Engine).
    public static func detectOS(_ vm: [String: Any]) -> VMOSType {
        guard let disks = vm["disks"] as? [[String: Any]] else { return .unknown }
        for disk in disks {
            if let features = disk["guestOsFeatures"] as? [[String: Any]] {
                for f in features where (f["type"] as? String)?.uppercased() == "WINDOWS" {
                    return .windows
                }
            }
            if let licenses = disk["licenses"] as? [String] {
                if licenses.contains(where: { $0.lowercased().contains("windows") }) {
                    return .windows
                }
            }
        }
        // Boot disk present but no Windows signal → assume Linux.
        return disks.isEmpty ? .unknown : .linux
    }

    private static func extractIPs(_ vm: [String: Any]) -> (String?, String?) {
        guard let nics = vm["networkInterfaces"] as? [[String: Any]],
              let nic0 = nics.first else { return (nil, nil) }
        let internalIP = nic0["networkIP"] as? String
        var externalIP: String?
        if let configs = nic0["accessConfigs"] as? [[String: Any]],
           let natIP = configs.first?["natIP"] as? String {
            externalIP = natIP
        }
        return (internalIP, externalIP)
    }

    /// Maps a Compute API error, distinguishing the common 403 causes
    /// that Google reports differently in the error body:
    /// - Compute Engine API not enabled (reason: accessNotConfigured /
    ///   SERVICE_DISABLED) → actionable "enable the API" message.
    /// - IAM permission denied (reason: forbidden / permission) →
    ///   "you lack the compute.instances.list permission".
    public static func mapComputeError(
        status: Int, data: Data, projectID: String
    ) -> CloudGateError {
        let reason = extractErrorReason(data)
        if status == 403 {
            if reason.contains("accessNotConfigured")
                || reason.lowercased().contains("service_disabled")
                || reason.lowercased().contains("has not been used")
                || reason.lowercased().contains("is disabled") {
                return .make(.apiDisabled,
                    userMessage: "The Compute Engine API is not enabled in project \(projectID). Enable it in Google Cloud Console and try again.",
                    technicalDetail: "compute 403 reason=\(reason)")
            }
            let googleMessage = extractErrorMessage(data)
            return .make(.insufficientCloudPermissions,
                userMessage: "Could not list VMs in \(projectID). Google says: \(googleMessage)",
                technicalDetail: "compute 403 reason=\(reason)")
        }
        return ResourceManagerClient.mapError(status: status, context: "instances")
    }

    /// The human-readable message Google returned (safe to show; it
    /// describes the permission/scope problem, not any secret).
    static func extractErrorMessage(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "error desconocido"
        }
        return message
    }

    /// Pulls a useful reason/message string out of a Google API error
    /// body without leaking anything sensitive.
    static func extractErrorReason(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any] else { return "" }
        if let errors = error["errors"] as? [[String: Any]],
           let reason = errors.first?["reason"] as? String {
            return reason
        }
        if let status = error["status"] as? String { return status }
        if let message = error["message"] as? String { return message }
        return ""
    }
}
