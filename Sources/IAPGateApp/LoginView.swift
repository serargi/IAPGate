import SwiftUI
import Auth
import CloudGateCore

/// The login screen: the only thing shown when there is no session.
struct LoginView: View {
    @Environment(SessionController.self) private var session
    let lastError: CloudGateError?
    let configError: String?

    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("IAPGate")
                    .font(.largeTitle.bold())
                Text("Sign in with Google to continue")
                    .foregroundStyle(.secondary)
            }

            GoogleSignInButton(isLoading: isSigningIn) {
                Task { await signIn() }
            }
            .disabled(isSigningIn || configError != nil)

            if isSigningIn {
                Text("Your browser has opened. Complete the Google sign-in and come back here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let configError {
                Text(configError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .textSelection(.enabled)
            }

            if let lastError {
                Text(lastError.userMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .accessibilityLabel("Error: \(lastError.userMessage)")
            }

            Spacer()

            Text("Version \(Self.appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Version \(Self.appVersion)")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The app's marketing version (CFBundleShortVersionString), shown so
    /// it's clear this is a pre-1.0 beta.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        await session.signIn()
    }
}

/// "Sign in with Google" button using Google's official button asset
/// (light theme, with label, square shape), shipped in the app's asset
/// catalog. The asset is used unmodified per Google's brand guidelines.
/// See https://developers.google.com/identity/branding-guidelines
///
/// The official asset's intrinsic size is 188×44 pt; it is shown at that
/// size so proportions, colors, and spacing match the guidelines exactly.
private struct GoogleSignInButton: View {
    let isLoading: Bool
    let action: () -> Void

    private static let buttonWidth: CGFloat = 188
    private static let buttonHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                // Official Google button asset. Kept at native size and
                // not recolored or distorted, per brand guidelines.
                Image("SignInWithGoogle", bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.buttonWidth, height: Self.buttonHeight)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    // Keep the official button's footprint stable while
                    // the browser-based sign-in is in progress.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color(red: 0.455, green: 0.463, blue: 0.459),
                                              lineWidth: 1))
                        .frame(width: Self.buttonWidth, height: Self.buttonHeight)
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 0.122, green: 0.122, blue: 0.122))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign in with Google")
    }
}
