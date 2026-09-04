import Foundation
import os

/// App-level session: who is signed in, and the one `APIClient` everything uses.
///
/// Views talk to this rather than to `APIClient` directly, so that sign-in state
/// and the loading/error handling around it live in one observable place instead
/// of being re-implemented per screen.
@MainActor
@Observable
final class SessionStore {

    let tokens = TokenStore()
    private(set) var client: APIClient!

    var isSignedIn: Bool { tokens.isSignedIn }
    var currentUser: UserProfileDTO? { tokens.currentUser }

    private(set) var friends: [FriendDTO] = []
    private(set) var isBusy = false
    var errorMessage: String?

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "session")

    init() {
        client = APIClient(tokens: tokens)
    }

    // MARK: - Auth

    func register(handle: String, email: String, password: String, displayName: String) async {
        await run { try await self.client.register(handle: handle, email: email, password: password, displayName: displayName) }
    }

    func login(handle: String, password: String) async {
        await run { try await self.client.login(handle: handle, password: password) }
    }

    func signOut() async {
        await client.logout()
        friends = []
    }

    // MARK: - Friends

    func loadFriends() async {
        guard isSignedIn else { return }
        do {
            friends = try await client.friends()
        } catch {
            log.error("loading friends failed: \(error.localizedDescription)")
        }
    }

    func addFriend(handle: String) async {
        await run {
            _ = try await self.client.requestFriend(handle: handle)
            await self.loadFriends()
        }
    }

    func accept(_ friend: FriendDTO) async {
        await run {
            try await self.client.acceptFriend(id: friend.id)
            await self.loadFriends()
        }
    }

    func decline(_ friend: FriendDTO) async {
        await run {
            try await self.client.declineFriend(id: friend.id)
            await self.loadFriends()
        }
    }

    /// Wraps a call with the busy flag and turns thrown errors into a message the
    /// UI can show. Every screen needs exactly this, so it exists once.
    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
