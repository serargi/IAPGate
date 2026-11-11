import SwiftUI
import AppKit
import Transport

/// Confirmation shown before resetting a Windows password, because the
/// operation modifies the instance and can destroy data encrypted with
/// the previous password.
struct WindowsCredentialsConfirm: View {
    let instanceName: String
    @Binding var username: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Generate Windows credentials", systemImage: "key.fill")
                .font(.headline)

            Text("This creates the user (or resets its password) on \(instanceName).")
                .foregroundStyle(.secondary)

            TextField("Windows username", text: $username)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Label("This modifies the machine", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.semibold))
                Text("If the user already exists, resetting its password can cause the loss of data encrypted with the previous password (encrypted files, stored credentials).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Generate", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Shows the generated credentials with copy buttons.
///
/// The password is displayed because the user explicitly requested it,
/// and is never logged or written to disk by IAPGate.
struct WindowsCredentialsResult: View {
    let credentials: WindowsCredentials
    let onDone: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Windows credentials", systemImage: "key.fill").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Username").foregroundStyle(.secondary)
                    Text(credentials.username).textSelection(.enabled)
                    CopyButton(value: credentials.username)
                }
                GridRow {
                    Text("Password").foregroundStyle(.secondary)
                    if revealed {
                        Text(credentials.password)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("••••••••••••")
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 6) {
                        Button(revealed ? "Hide" : "Show") { revealed.toggle() }
                            .buttonStyle(.link)
                        CopyButton(value: credentials.password)
                    }
                }
                if let ip = credentials.ipAddress {
                    GridRow {
                        Text("IP").foregroundStyle(.secondary)
                        Text(ip).textSelection(.enabled)
                        CopyButton(value: ip)
                    }
                }
            }

            Text("Use them in the RDP client when it asks for a username and password. IAPGate does not store them.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct CopyButton: View {
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}
