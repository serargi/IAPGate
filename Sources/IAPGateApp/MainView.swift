import SwiftUI
import AppKit
import Auth
import Discovery
import Transport
import CloudGateCore

/// Authenticated view. Top: organization combobox. Sidebar: lazy tree
/// of folders/subfolders → projects for the selected org (plus a
/// "No organization" root). Detail: the selected project's instances.
struct MainView: View {
    @Environment(SessionController.self) private var session
    let account: Account
    let connectionManager: ConnectionManager
    @State private var browse: BrowseController
    @State private var terminals: [TerminalController] = []
    @State private var activeTerminal: TerminalController.ID?

    init(account: Account, discovery: DiscoveryProviding,
         favoritesStore: FavoritesStore, connectionManager: ConnectionManager) {
        self.account = account
        self.connectionManager = connectionManager
        _browse = State(initialValue: BrowseController(
            accountID: account.id, discovery: discovery, favoritesStore: favoritesStore))
    }

    var body: some View {
        @Bindable var browse = browse
        return NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    OrgPicker(browse: browse)
                    Button {
                        browse.showingFavorites.toggle()
                        if browse.showingFavorites { browse.reloadFavorites() }
                    } label: {
                        Image(systemName: browse.showingFavorites ? "star.fill" : "star")
                            .foregroundStyle(browse.showingFavorites ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(browse.showingFavorites ? "Show all" : "Show favorites")
                }
                .padding(8)
                SearchField(browse: browse)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                Divider()
                sidebarContent
            }
            .navigationTitle("IAPGate")
            .frame(minWidth: 280)
        } detail: {
            DetailArea(browse: browse, account: account,
                       connectionManager: connectionManager,
                       terminals: $terminals, activeTerminal: $activeTerminal)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Tear down any open sessions before signing out so
                    // no remote SSH/RDP session is left dangling.
                    for term in terminals { term.terminate() }
                    terminals.removeAll()
                    activeTerminal = nil
                    Task { await session.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .help(account.email ?? account.id)
            }
        }
        .task { await browse.loadOrganizations() }
    }

    /// Sidebar body: search results take priority, then favorites, then
    /// the hierarchy tree.
    @ViewBuilder private var sidebarContent: some View {
        switch browse.searchState {
        case .searching(let partial):
            SearchResultsSidebar(browse: browse, hits: partial, searching: true) {
                activeTerminal = nil
            }
        case .results(let hits):
            SearchResultsSidebar(browse: browse, hits: hits, searching: false) {
                activeTerminal = nil
            }
        case .inactive:
            if browse.showingFavorites {
                FavoritesSidebar(browse: browse) { activeTerminal = nil }
            } else {
                HierarchySidebar(browse: browse) { activeTerminal = nil }
            }
        }
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Bindable var browse: BrowseController
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search folders and projects", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { browse.search(text) }
                .onChange(of: text) { _, newValue in
                    // Debounce-ish: search on change, but the controller
                    // cancels any in-flight search so only the latest runs.
                    browse.search(newValue)
                }
            if !text.isEmpty {
                Button { text = ""; browse.search("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Organization combobox

private struct OrgPicker: View {
    @Bindable var browse: BrowseController

    var body: some View {
        switch browse.organizations {
        case .idle, .loading:
            HStack { ProgressView().controlSize(.small); Text("Loading organizations…") }
                .foregroundStyle(.secondary)
        case .failed(let error):
            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red).font(.callout)
        case .loaded(let orgs):
            Picker("Organization", selection: $browse.selectedParentRootID) {
                Text("Choose your organization…").tag(Optional<String>.none)
                ForEach(orgs) { org in
                    Text(org.displayName).tag(Optional(org.id))
                }
                Text("No organization").tag(Optional(BrowseController.noParentRootID))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: browse.selectedParentRootID) { _, _ in
                // Choosing an org switches back to the hierarchy view
                // and resets search (its cache belonged to the old org).
                browse.showingFavorites = false
                browse.search("")
                browse.clearSearchCache()
            }
        }
    }
}

// MARK: - Lazy hierarchy tree

private struct HierarchySidebar: View {
    @Bindable var browse: BrowseController
    /// Called on every project row click, so the detail pane can bring
    /// the machine list back into focus even when re-clicking the
    /// already-selected project.
    let onProjectTap: () -> Void

    var body: some View {
        List(selection: $browse.selectedProjectID) {
            if let root = browse.selectedParentRootID {
                if root == BrowseController.noParentRootID {
                    OrphanProjectsSection(browse: browse, onProjectTap: onProjectTap)
                } else {
                    // Root org: render its direct children.
                    NodeChildrenView(browse: browse, parent: root, onProjectTap: onProjectTap)
                }
            } else {
                Text("Select an organization").foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .task(id: browse.selectedParentRootID) {
            if let root = browse.selectedParentRootID, root != BrowseController.noParentRootID {
                await browse.loadChildrenIfNeeded(parent: root)
            } else if browse.selectedParentRootID == BrowseController.noParentRootID {
                await browse.loadOrphanProjectsIfNeeded()
            }
        }
    }
}

/// Renders the direct children (subfolders + projects) of a parent,
/// recursing into folders via `FolderDisclosure`.
private struct NodeChildrenView: View {
    @Bindable var browse: BrowseController
    let parent: String
    let onProjectTap: () -> Void

    var body: some View {
        switch browse.childrenByParent[parent] {
        case .none, .some(.idle), .some(.loading):
            HStack { ProgressView().controlSize(.small); Text("Loading…") }
                .foregroundStyle(.secondary)
        case .some(.failed(let error)):
            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .some(.loaded(let children)):
            if children.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            } else {
                ForEach(children.folders) { folder in
                    FolderDisclosure(browse: browse, folder: folder, onProjectTap: onProjectTap)
                }
                ForEach(children.projects) { project in
                    ProjectRow(browse: browse, project: project, onTap: onProjectTap)
                }
            }
        }
    }
}

/// A folder row that expands to show its subfolders and projects,
/// loading them on first expand. Supports arbitrary nesting depth.
private struct FolderDisclosure: View {
    @Bindable var browse: BrowseController
    let folder: Folder
    let onProjectTap: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            NodeChildrenView(browse: browse, parent: folder.id, onProjectTap: onProjectTap)
        } label: {
            HStack {
                Label(folder.displayName, systemImage: "folder")
                Spacer()
                FavoriteStar(browse: browse, kind: .folder,
                             resourceID: folder.id, displayName: folder.displayName)
            }
        }
        .onChange(of: expanded) { _, now in
            if now { Task { await browse.loadChildrenIfNeeded(parent: folder.id) } }
        }
    }
}

private struct ProjectRow: View {
    @Bindable var browse: BrowseController
    let project: Project
    let onTap: () -> Void

    var body: some View {
        HStack {
            // A Button fires on every click — including when the row is
            // already selected — which a List selection binding does
            // not. That's what makes re-clicking a project return to the
            // machine list.
            Button {
                browse.focusProject(project.id)
                onTap()
            } label: {
                Label(project.displayName, systemImage: "cube.box")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FavoriteStar(browse: browse, kind: .project,
                         resourceID: project.id, displayName: project.displayName)
        }
        .tag(project.id)
        .help(project.id)
    }
}

/// A small star toggle shown on the trailing edge of folder/project
/// rows. Filled yellow when the item is a favorite.
private struct FavoriteStar: View {
    @Bindable var browse: BrowseController
    let kind: Favorite.Kind
    let resourceID: String
    let displayName: String

    var body: some View {
        // Derive from the observable `favorites` array so SwiftUI
        // re-renders the star immediately when it changes.
        let on = browse.favorites.contains { $0.resourceID == resourceID }
        Button {
            browse.toggleFavorite(kind: kind, resourceID: resourceID, displayName: displayName)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .foregroundStyle(on ? .yellow : .secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help(on ? "Remove from favorites" : "Add to favorites")
    }
}

/// Favorites list: pinned folders and projects for quick access.
/// Favorites list. A favorited project opens its machines; a favorited
/// folder is fully navigable — it expands into its subfolders and
/// projects using the same lazy tree as the main hierarchy.
private struct FavoritesSidebar: View {
    @Bindable var browse: BrowseController
    let onProjectTap: () -> Void

    var body: some View {
        List(selection: $browse.selectedProjectID) {
            if browse.favorites.isEmpty {
                Text("No favorites yet. Tap the star on a folder or project.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(browse.favorites) { fav in
                    if fav.kind == .folder {
                        FolderDisclosure(
                            browse: browse,
                            folder: Folder(id: fav.resourceID,
                                           displayName: fav.displayName,
                                           parent: ""),
                            onProjectTap: onProjectTap)
                    } else {
                        ProjectRow(
                            browse: browse,
                            project: Project(id: fav.resourceID,
                                             displayName: fav.displayName,
                                             number: nil, parent: nil,
                                             lifecycleState: nil),
                            onTap: onProjectTap)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct OrphanProjectsSection: View {
    @Bindable var browse: BrowseController
    let onProjectTap: () -> Void
    var body: some View {
        switch browse.orphanProjects {
        case .idle, .loading:
            HStack { ProgressView().controlSize(.small); Text("Loading projects…") }
                .foregroundStyle(.secondary)
        case .failed(let error):
            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .loaded(let projects):
            if projects.isEmpty {
                Text("No projects").foregroundStyle(.secondary)
            } else {
                ForEach(projects) {
                    ProjectRow(browse: browse, project: $0, onTap: onProjectTap)
                }
            }
        }
    }
}

/// Flat list of search results (folders and projects) with a breadcrumb
/// showing where each sits. Shown instead of the tree while searching,
/// so the user sees the final result, not the tree expanding.
private struct SearchResultsSidebar: View {
    @Bindable var browse: BrowseController
    let hits: [BrowseController.SearchHit]
    let searching: Bool
    let onProjectTap: () -> Void

    var body: some View {
        List(selection: $browse.selectedProjectID) {
            if searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(hits.isEmpty ? "Searching…" : "Searching… (\(hits.count))")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
            if hits.isEmpty && !searching {
                Text("No matches").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(hits) { hit in
                    Button {
                        if hit.kind == .project {
                            browse.focusProject(hit.id)
                            onProjectTap()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hit.kind == .folder ? "folder" : "cube.box")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.displayName)
                                if !hit.pathLabel.isEmpty {
                                    Text(hit.pathLabel)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(hit.kind == .folder)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Detail (instances)

/// The detail pane: a tab bar of open terminal sessions plus the VM
/// list. Selecting a terminal shows it; otherwise the VM list is shown.
private struct DetailArea: View {
    @Bindable var browse: BrowseController
    let account: Account
    let connectionManager: ConnectionManager
    @Binding var terminals: [TerminalController]
    @Binding var activeTerminal: TerminalController.ID?

    @State private var connectError: String?

    var body: some View {
        VStack(spacing: 0) {
            if !terminals.isEmpty {
                TerminalTabBar(terminals: $terminals, active: $activeTerminal)
                Divider()
            }
            if let connectError {
                Text(connectError)
                    .font(.callout).foregroundStyle(.red)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if let active = activeTerminal,
               let controller = terminals.first(where: { $0.id == active }) {
                TerminalView(controller: controller)
            } else {
                instanceList
            }
        }
        .task(id: browse.selectedProjectID) {
            if let pid = browse.selectedProjectID {
                await browse.selectProject(pid)
            }
        }
        // Re-tapping a project (same id, so the task above doesn't fire)
        // refreshes its instance list, picking up VMs created since.
        .task(id: browse.projectFocusTick) {
            if browse.projectFocusTick > 0, browse.selectedProjectID != nil {
                await browse.selectProject(browse.selectedProjectID!)
            }
        }
    }

    @ViewBuilder private var instanceList: some View {
        if let projectID = browse.selectedProjectID {
            switch browse.instancesByProject[projectID] {
            case .none, .some(.idle), .some(.loading):
                VStack(spacing: 12) {
                    ProgressView(); Text("Loading machines…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .some(.failed(let error)):
                EmptyState(icon: "exclamationmark.triangle",
                           title: "Could not load the machines", subtitle: error.userMessage)
            case .some(.loaded(let instances)):
                if instances.isEmpty {
                    EmptyState(icon: "server.rack", title: "No machines",
                               subtitle: "This project has no Compute Engine instances.")
                } else {
                    InstanceTable(
                        instances: instances,
                        connect: { vm, port in connect(vm, remotePort: port) },
                        defaultUsername: account.email
                            .flatMap(ConnectionManager.posixUsername(fromEmail:)) ?? "")
                }
            }
        } else {
            EmptyState(icon: "server.rack", title: "Select a project",
                       subtitle: "Pick a project in the sidebar to see its machines.")
        }
    }

    /// Opens an embedded terminal running the right gcloud command for
    /// the VM's OS (SSH for Linux, RDP tunnel for Windows). If a live
    /// session for this VM already exists, focuses that tab instead of
    /// opening a duplicate.
    /// Connects to a VM. `remotePort` overrides the default (22 for
    /// SSH, 3389 for RDP) when the VM listens on a non-standard port.
    private func connect(_ vm: Instance, remotePort: Int? = nil) {
        guard vm.status == "RUNNING" else { return }
        connectError = nil

        // Reuse an existing, still-running session for this VM (only
        // when connecting on the default port; a custom port is a new
        // intentional session).
        if remotePort == nil,
           let existing = terminals.first(where: { $0.vmID == vm.id && !$0.finished }) {
            activeTerminal = existing.id
            return
        }

        let target = IAPTarget(project: vm.projectID, zone: vm.zone, instance: vm.name, port: 22)

        let command: ConnectionManager.Command
        let title: String
        var rdpPort: Int?
        if vm.osType == .windows {
            // Pick a free local port so multiple RDP tunnels don't
            // collide on a fixed 3389.
            let port = FreePort.find(default: 3389)
            switch connectionManager.rdpTunnelCommand(
                target: target, localPort: port, remotePort: remotePort ?? 3389) {
            case .success(let c): command = c
            case .failure(let e): connectError = e.userMessage; return
            }
            title = "RDP \(vm.name)"
            rdpPort = port
        } else {
            // Use the OS Login-style username derived from the signed-in
            // account so the Linux identity matches the Cloud Console
            // (and not the local macOS username gcloud would otherwise
            // use when a project has no OS Login).
            let username = account.email.flatMap(ConnectionManager.posixUsername(fromEmail:))
            switch connectionManager.sshCommand(
                target: target, username: username, remotePort: remotePort ?? 22) {
            case .success(let c): command = c
            case .failure(let e): connectError = e.userMessage; return
            }
            title = "SSH \(vm.name)"
        }

        let controller = TerminalController(
            title: title, vmID: vm.id,
            executable: command.executable, arguments: command.arguments)

        // For RDP, open the client only once gcloud reports the tunnel
        // is listening — a fixed delay was racing the tunnel setup.
        if let port = rdpPort {
            let vmName = vm.name
            controller.readyMarker = "Listening on port"
            controller.onReady = {
                if case .failure(let e) = RDPLauncher().open(localPort: port, instanceName: vmName) {
                    connectError = e.userMessage
                }
            }
        }

        controller.start()
        terminals.append(controller)
        activeTerminal = controller.id
    }
}

private struct InstanceTable: View {
    let instances: [Instance]
    let connect: (Instance, Int?) -> Void
    /// Default Windows/Linux username derived from the signed-in account.
    let defaultUsername: String
    @State private var selection: Instance.ID?

    // Custom-port flow state.
    @State private var portVMID: Instance.ID?
    @State private var portText = ""

    // Windows credential flow state.
    @State private var credentialsFor: Instance?
    @State private var credentialsUsername = ""
    @State private var generatedCredentials: WindowsCredentials?
    @State private var generating = false
    @State private var credentialsError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let credentialsError {
                Text(credentialsError)
                    .font(.callout).foregroundStyle(.red)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if generating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating Windows credentials…")
                }
                .font(.callout).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            table
        }
        .sheet(item: $credentialsFor) { vm in
            WindowsCredentialsConfirm(
                instanceName: vm.name,
                username: $credentialsUsername,
                onConfirm: {
                    credentialsFor = nil
                    Task { await generateCredentials(for: vm) }
                },
                onCancel: { credentialsFor = nil })
        }
        .sheet(item: $generatedCredentials) { creds in
            WindowsCredentialsResult(credentials: creds) {
                generatedCredentials = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { portVMID != nil },
            set: { if !$0 { portVMID = nil } })) {
            if let vm = instances.first(where: { $0.id == portVMID }) {
                CustomPortSheet(
                    instance: vm, port: $portText,
                    onConnect: {
                        let p = Int(portText)
                        portVMID = nil
                        if let p { connect(vm, p) }
                    },
                    onCancel: { portVMID = nil })
            }
        }
    }

    private var table: some View {
        Table(instances, selection: $selection) {
            TableColumn("Nombre", value: \.name)
            TableColumn("Zona", value: \.zone)
            TableColumn("SO") { Text(osLabel($0.osType)) }
            TableColumn("Estado") { Text($0.status) }
            TableColumn("IP interna") { Text($0.internalIP ?? "—") }
            TableColumn("IP externa") { Text($0.externalIP ?? "—") }
        }
        // Fixed row height so resizing a column never changes it.
        .environment(\.defaultMinListRowHeight, 24)
        // Double-click connects; right-click opens a context menu.
        .contextMenu(forSelectionType: Instance.ID.self) { ids in
            if let id = ids.first, let vm = instances.first(where: { $0.id == id }) {
                contextMenu(for: vm)
            }
        } primaryAction: { ids in
            if let id = ids.first, let vm = instances.first(where: { $0.id == id }) {
                connect(vm, nil)
            }
        }
    }

    @ViewBuilder private func contextMenu(for vm: Instance) -> some View {
        let running = vm.status == "RUNNING"
        let kind = vm.osType == .windows ? "RDP" : "SSH"

        Button("Connect (\(kind))") { connect(vm, nil) }
            .disabled(!running)

        Button("Connect on a custom port…") {
            portText = vm.osType == .windows ? "3389" : "22"
            portVMID = vm.id
        }
        .disabled(!running)

        if vm.osType == .windows {
            Divider()
            Button("Generate Windows credentials…") {
                credentialsUsername = defaultUsername
                credentialsFor = vm
            }
            .disabled(!running || generating)
        }
    }

    private func generateCredentials(for vm: Instance) async {
        credentialsError = nil
        generating = true
        defer { generating = false }
        let target = IAPTarget(project: vm.projectID, zone: vm.zone,
                               instance: vm.name, port: 3389)
        let result = await WindowsCredentialsService().resetPassword(
            target: target, username: credentialsUsername)
        switch result {
        case .success(let creds): generatedCredentials = creds
        case .failure(let error): credentialsError = error.userMessage
        }
    }

    private func osLabel(_ os: VMOSType) -> String {
        switch os {
        case .windows: return "Windows"
        case .linux: return "Linux"
        case .unknown: return "—"
        }
    }
}

/// Tab bar for open terminal sessions, with close buttons.
private struct TerminalTabBar: View {
    @Binding var terminals: [TerminalController]
    @Binding var active: TerminalController.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    active = nil
                } label: {
                    Label("Machines", systemImage: "list.bullet").font(.caption)
                }
                .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
                .background(active == nil ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))

                ForEach(terminals) { term in
                    HStack(spacing: 4) {
                        Text(term.title).font(.caption).lineLimit(1)
                        Button {
                            close(term)
                        } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                        .buttonStyle(.plain)
                        .help("Close and end the session")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(active == term.id ? Color.accentColor.opacity(0.2) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    // Single click selects the tab; double click closes
                    // it (terminating the session) and its window.
                    .onTapGesture(count: 2) { close(term) }
                    .onTapGesture { active = term.id }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    /// Terminates the session (closing the remote SSH/RDP connection and
    /// its gcloud/tunnel process group) and removes its tab.
    private func close(_ term: TerminalController) {
        term.terminate()
        terminals.removeAll { $0.id == term.id }
        if active == term.id { active = terminals.last?.id }
    }
}

/// Prompts for a custom remote port before connecting (for VMs whose
/// SSH/RDP service listens on a non-standard port).
private struct CustomPortSheet: View {
    let instance: Instance
    @Binding var port: String
    let onConnect: () -> Void
    let onCancel: () -> Void

    private var isWindows: Bool { instance.osType == .windows }
    private var valid: Bool { (Int(port) ?? 0) > 0 && (Int(port) ?? 0) <= 65535 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to \(instance.name)").font(.headline)
            Text("\(isWindows ? "RDP" : "SSH") port on the machine. Change it if the service listens on a non-standard port (default \(isWindows ? "3389" : "22")).")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Port", text: $port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Connect", action: onConnect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
