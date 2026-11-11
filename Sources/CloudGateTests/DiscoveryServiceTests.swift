import Foundation
import TestKit
import Discovery
import Auth
import CloudGateCore

/// Token provider double.
struct StubTokenProvider: AccessTokenProviding {
    var token: String = "AT"
    func validAccessToken(for accountID: String) async -> Result<String, CloudGateError> {
        .success(token)
    }
}

/// Routes responses by matching a substring of the request URL/path.
final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    var routes: [(String, Int, String)] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let url = request.url?.absoluteString ?? ""
        for (match, status, body) in routes where url.contains(match) {
            return (Data(body.utf8), status)
        }
        return (Data("{}".utf8), 404)
    }
}

func discoveryServiceSuite() -> TestSuite {
    let s = TestSuite("DiscoveryService (v3 hierarchy)")

    func makeService(_ http: RoutingHTTPClient) -> DiscoveryService {
        let tp = StubTokenProvider()
        return DiscoveryService(
            resourceManager: ResourceManagerClient(http: http, tokenProvider: tp),
            compute: ComputeClient(http: http, tokenProvider: tp))
    }

    s.test("lists organizations for the combobox") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("organizations:search", 200, #"{"organizations":[{"name":"organizations/111","displayName":"gsuitetelefonicaes.com"}]}"#)
        ]
        let service = makeService(http)
        switch await service.organizations(accountID: "acct") {
        case .success(let orgs):
            t.expectEqual(orgs.count, 1)
            t.expectEqual(orgs.first?.id, "organizations/111")
        case .failure(let e): t.expect(false, "unexpected failure: \(e.kind)")
        }
    }

    s.test("children of an org are its folders and direct projects") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("/v3/folders", 200, #"{"folders":[{"name":"folders/501","displayName":"Altostratus","parent":"organizations/111","state":"ACTIVE"}]}"#),
            ("/v3/projects", 200, #"{"projects":[{"projectId":"direct-proj","displayName":"Direct","name":"projects/1","state":"ACTIVE","parent":"organizations/111"}]}"#)
        ]
        let service = makeService(http)
        switch await service.children(accountID: "acct", parent: "organizations/111") {
        case .success(let children):
            t.expectEqual(children.folders.count, 1)
            t.expectEqual(children.folders.first?.displayName, "Altostratus")
            t.expectEqual(children.projects.count, 1)
            t.expectEqual(children.projects.first?.id, "direct-proj")
        case .failure(let e): t.expect(false, "unexpected failure: \(e.kind)")
        }
    }

    s.test("children of a folder support nesting (subfolders)") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("/v3/folders", 200, #"{"folders":[{"name":"folders/777","displayName":"Subfolder","parent":"folders/501","state":"ACTIVE"}]}"#),
            ("/v3/projects", 200, #"{"projects":[]}"#)
        ]
        let service = makeService(http)
        switch await service.children(accountID: "acct", parent: "folders/501") {
        case .success(let children):
            t.expectEqual(children.folders.count, 1)
            t.expectEqual(children.folders.first?.id, "folders/777")
            t.expect(children.projects.isEmpty)
        case .failure(let e): t.expect(false, "unexpected failure: \(e.kind)")
        }
    }

    s.test("403 on folders yields empty children, not failure") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("/v3/folders", 403, #"{"error":{"code":403}}"#),
            ("/v3/projects", 200, #"{"projects":[]}"#)
        ]
        let service = makeService(http)
        switch await service.children(accountID: "acct", parent: "organizations/111") {
        case .success(let children): t.expect(children.isEmpty)
        case .failure(let e): t.expect(false, "403 should be soft, got \(e.kind)")
        }
    }

    s.test("projectsWithoutVisibleParent returns parentless projects") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("/v3/projects:search", 200, #"{"projects":[{"projectId":"standalone","displayName":"Standalone","name":"projects/5","state":"ACTIVE"},{"projectId":"in-folder","displayName":"InFolder","name":"projects/6","state":"ACTIVE","parent":"folders/501"}]}"#)
        ]
        let service = makeService(http)
        switch await service.projectsWithoutVisibleParent(accountID: "acct") {
        case .success(let projects):
            // Only the standalone project (no parent) is an orphan.
            t.expectEqual(projects.map { $0.id }, ["standalone"])
        case .failure(let e): t.expect(false, "unexpected failure: \(e.kind)")
        }
    }

    s.test("instances under a project are listed and sorted") { t in
        let http = RoutingHTTPClient()
        http.routes = [
            ("aggregated/instances", 200, #"{"items":{"zones/z-a":{"instances":[{"name":"zeta","status":"RUNNING","networkInterfaces":[{"networkIP":"10.0.0.9"}]},{"name":"alpha","status":"RUNNING","networkInterfaces":[{"networkIP":"10.0.0.1"}]}]}}}"#)
        ]
        let service = makeService(http)
        switch await service.instances(accountID: "acct", projectID: "cmc-sandbox") {
        case .success(let vms): t.expectEqual(vms.map { $0.name }, ["alpha", "zeta"])
        case .failure(let e): t.expect(false, "unexpected failure: \(e.kind)")
        }
    }

    return s
}
