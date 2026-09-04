import Foundation

/// Wire types.
///
/// Kept separate from the SwiftData models on purpose: `CatchRecord` is what the
/// device owns and can edit offline, while these mirror whatever the server
/// currently returns. Letting one type serve both roles means every schema change
/// on either side becomes a migration on the other.

struct UserProfileDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let handle: String
    let displayName: String
}

struct TokenPairDTO: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserProfileDTO
}

struct CatchDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let handle: String
    let speciesKey: String
    let caughtAt: Date
    let lat: Double?
    let lng: Double?
    let mediaId: UUID?
}

struct CreateCatchDTO: Codable {
    let speciesKey: String
    let caughtAt: Date
    let lat: Double?
    let lng: Double?
    let confidence: Float?
    let mediaId: UUID?
}

struct FriendDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let handle: String
    let displayName: String
    let status: String
    let incoming: Bool
    let speciesCount: Int

    var isAccepted: Bool { status == "accepted" }
    var isPending: Bool { status == "pending" }
}

struct DexEntryDTO: Codable, Hashable {
    let speciesKey: String
    let count: Int
    let firstCaught: Date
}

struct UploadURLDTO: Codable {
    let mediaId: UUID
    let uploadUrl: String
    let expiresInSecs: Int
}

struct MediaDTO: Codable {
    let id: UUID
    let status: String
    let contentType: String
    let byteSize: Int?
}

/// The server's error envelope: `{"error": {"code": "...", "message": "..."}}`.
struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}
