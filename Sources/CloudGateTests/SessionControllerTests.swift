import Foundation
import TestKit
import Auth
import CloudGateCore

/// Scripted AuthenticationProvider double for gate-logic tests.
final class StubAuthProvider: AuthenticationProvider, @unchecked Sendable {
    var restoreResult: Result<Account?, CloudGateError>
    var signInResult: Result<Account, CloudGateError>
    private(set) var signOutCalled = false

    init(
        restore: Result<Account?, CloudGateError> = .success(nil),
        signIn: Result<Account, CloudGateError> = .success(Account(id: "x", email: nil, displayName: nil))
    ) {
        self.restoreResult = restore
        self.signInResult = signIn
    }

    func restoreSession() async -> Result<Account?, CloudGateError> { restoreResult }
    func signIn() async -> Result<Account, CloudGateError> { signInResult }
    func signOut(account: Account) async { signOutCalled = true }
}

func sessionControllerSuite() -> TestSuite {
    let s = TestSuite("SessionController (auth gate)")

    let account = Account(id: "sub-123", email: "user@example.com", displayName: "User")

    s.test("no stored session → unauthenticated (show login only)") { t in
        await MainActor.run {}
        let provider = StubAuthProvider(restore: .success(nil))
        let controller = await SessionController(provider: provider)
        await controller.start()
        let state = await controller.state
        t.expect(state == .unauthenticated(lastError: nil), "should gate to login")
        t.expect(!state.isAuthenticated)
    }

    s.test("valid stored session → authenticated at launch") { t in
        let provider = StubAuthProvider(restore: .success(account))
        let controller = await SessionController(provider: provider)
        await controller.start()
        let state = await controller.state
        t.expect(state == .authenticated(account))
        t.expect(state.isAuthenticated)
    }

    s.test("restore failure still gates to login, retaining error") { t in
        let err = CloudGateError.make(.networkTimeout, userMessage: "offline")
        let provider = StubAuthProvider(restore: .failure(err))
        let controller = await SessionController(provider: provider)
        await controller.start()
        let state = await controller.state
        if case .unauthenticated(let lastError) = state {
            t.expectEqual(lastError?.kind, .networkTimeout)
        } else {
            t.expect(false, "should be unauthenticated")
        }
    }

    s.test("successful sign-in transitions to authenticated") { t in
        let provider = StubAuthProvider(restore: .success(nil), signIn: .success(account))
        let controller = await SessionController(provider: provider)
        await controller.start()
        await controller.signIn()
        let state = await controller.state
        t.expect(state == .authenticated(account))
    }

    s.test("failed sign-in stays on login with error") { t in
        let err = CloudGateError.make(.authenticationFailed, userMessage: "denied")
        let provider = StubAuthProvider(restore: .success(nil), signIn: .failure(err))
        let controller = await SessionController(provider: provider)
        await controller.start()
        await controller.signIn()
        let state = await controller.state
        if case .unauthenticated(let lastError) = state {
            t.expectEqual(lastError?.kind, .authenticationFailed)
        } else {
            t.expect(false, "should remain unauthenticated")
        }
    }

    s.test("sign-out returns to login and calls provider") { t in
        let provider = StubAuthProvider(restore: .success(account))
        let controller = await SessionController(provider: provider)
        await controller.start()
        await controller.signOut()
        let state = await controller.state
        t.expect(state == .unauthenticated(lastError: nil))
        t.expect(provider.signOutCalled)
    }

    return s
}
