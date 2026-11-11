import Foundation
import TestKit
import Discovery

func discoveryParsingSuite() -> TestSuite {
    let s = TestSuite("Discovery parsing (v3)")

    s.test("parses organizations with paging token") { t in
        let json = """
        {"organizations":[
          {"name":"organizations/111","displayName":"gsuitetelefonicaes.com"},
          {"name":"organizations/222","displayName":"Other"}
        ],"nextPageToken":"NEXT"}
        """
        let page = ResourceManagerClient.parseOrganizations(Data(json.utf8))
        t.expectEqual(page.organizations.count, 2)
        t.expectEqual(page.organizations.first?.id, "organizations/111")
        t.expectEqual(page.organizations.first?.displayName, "gsuitetelefonicaes.com")
        t.expectEqual(page.nextPageToken, "NEXT")
    }

    s.test("parses folders and skips non-ACTIVE") { t in
        let json = """
        {"folders":[
          {"name":"folders/501","displayName":"Altostratus","parent":"organizations/111","state":"ACTIVE"},
          {"name":"folders/502","displayName":"Deleted","parent":"organizations/111","state":"DELETE_REQUESTED"}
        ]}
        """
        let page = ResourceManagerClient.parseFolders(Data(json.utf8))
        t.expectEqual(page.folders.count, 1)
        t.expectEqual(page.folders.first?.id, "folders/501")
        t.expectEqual(page.folders.first?.displayName, "Altostratus")
        t.expectEqual(page.folders.first?.parent, "organizations/111")
    }

    s.test("parses v3 projects with parent and number") { t in
        let json = """
        {"projects":[
          {"projectId":"cmc-sandbox","displayName":"CMC Sandbox","name":"projects/253111571185",
           "state":"ACTIVE","parent":"folders/501"},
          {"projectId":"orphan-proj","displayName":"Orphan","name":"projects/999","state":"ACTIVE"}
        ]}
        """
        let page = ResourceManagerClient.parseProjects(Data(json.utf8))
        t.expectEqual(page.projects.count, 2)
        let cmc = page.projects.first { $0.id == "cmc-sandbox" }
        t.expectEqual(cmc?.parent, "folders/501")
        t.expectEqual(cmc?.number, "253111571185")
        let orphan = page.projects.first { $0.id == "orphan-proj" }
        t.expect(orphan?.parent == nil)
    }

    s.test("parses aggregated instances across zones") { t in
        let json = """
        {"items":{
          "zones/europe-west2-a":{"instances":[
            {"name":"web-1","status":"RUNNING",
             "networkInterfaces":[{"networkIP":"10.0.0.2","accessConfigs":[{"natIP":"34.1.2.3"}]}]}
          ]},
          "zones/europe-west2-b":{"instances":[
            {"name":"db-1","status":"TERMINATED",
             "networkInterfaces":[{"networkIP":"10.0.0.5"}]}
          ]},
          "zones/us-east1-a":{"warning":{"code":"NO_RESULTS_ON_PAGE"}}
        }}
        """
        let page = ComputeClient.parseInstances(Data(json.utf8), projectID: "cmc-sandbox")
        t.expectEqual(page.instances.count, 2)
        let web = page.instances.first { $0.name == "web-1" }
        t.expectEqual(web?.zone, "europe-west2-a")
        t.expectEqual(web?.internalIP, "10.0.0.2")
        t.expectEqual(web?.externalIP, "34.1.2.3")
        t.expectEqual(web?.region, "europe-west2")
        let db = page.instances.first { $0.name == "db-1" }
        t.expectEqual(db?.status, "TERMINATED")
        t.expect(db?.externalIP == nil)
    }

    s.test("instance id is stable composite") { t in
        let vm = Instance(name: "web-1", projectID: "p", zone: "z-a",
                          status: "RUNNING", internalIP: nil, externalIP: nil)
        t.expectEqual(vm.id, "p/z-a/web-1")
    }

    s.test("detects Windows via guestOsFeatures") { t in
        let vm: [String: Any] = ["disks": [["guestOsFeatures": [["type": "WINDOWS"]]]]]
        t.expectEqual(ComputeClient.detectOS(vm), .windows)
    }

    s.test("detects Windows via license URL") { t in
        let vm: [String: Any] = ["disks": [["licenses": ["https://.../windows-server-2022"]]]]
        t.expectEqual(ComputeClient.detectOS(vm), .windows)
    }

    s.test("defaults to Linux when a boot disk has no Windows signal") { t in
        let vm: [String: Any] = ["disks": [["guestOsFeatures": [["type": "UEFI_COMPATIBLE"]]]]]
        t.expectEqual(ComputeClient.detectOS(vm), .linux)
    }

    s.test("compute 403 API-disabled maps to apiDisabled") { t in
        let body = Data(#"{"error":{"code":403,"message":"Compute Engine API has not been used in project X before or it is disabled","errors":[{"reason":"accessNotConfigured"}]}}"#.utf8)
        let err = ComputeClient.mapComputeError(status: 403, data: body, projectID: "prj-x")
        t.expectEqual(err.kind, .apiDisabled)
    }

    s.test("compute 403 IAM maps to insufficientCloudPermissions") { t in
        let body = Data(#"{"error":{"code":403,"message":"Required 'compute.instances.list' permission","errors":[{"reason":"forbidden"}]}}"#.utf8)
        let err = ComputeClient.mapComputeError(status: 403, data: body, projectID: "prj-x")
        t.expectEqual(err.kind, .insufficientCloudPermissions)
    }

    return s
}
