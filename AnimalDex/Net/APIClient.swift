import Foundation
import os

enum APIError: LocalizedError {
    case unauthorized
    case server(code: String, message: String, status: Int)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .server(_, let message, _):
            return message
        case .transport:
            return "Couldn't reach the AnimalDex server."
        case .decoding:
            return "The server sent something unexpected."
        }
    }
}

/// HTTP client with automatic access-token refresh.
///
/// An `actor` rather than a class, because the refresh path needs single-flight
/// behaviour: when several requests 401 at once — which is exactly what happens
/// when the app wakes up with an expired token — only one refresh should go out.
/// Without that, N concurrent 401s trigger N rotations, and since rotation
/// invalidates the previous token, all but one would be rejected and the user
/// would be signed out for no reason.
actor APIClient {

    private let tokens: TokenStore
    private let session: URLSession
    private let log = Logger(subsystem: "com.abhay.animaldex", category: "api")

    /// The in-flight refresh, if any. Later callers await this instead of
    /// starting their own.
    private var refreshTask: Task<Void, Error>?

    init(tokens: TokenStore) {
        self.tokens = tokens
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public surface

    func register(handle: String, email: String, password: String, displayName: String) async throws {
        struct Body: Encodable {
            let handle: String, email: String, password: String, displayName: String
        }
        let pair: TokenPairDTO = try await send(
            .post, "/auth/register",
            body: Body(handle: handle, email: email, password: password, displayName: displayName),
            authenticated: false
        )
        await MainActor.run { tokens.store(pair) }
    }

    func login(handle: String, password: String) async throws {
        struct Body: Encodable { let handle: String, password: String }
        let pair: TokenPairDTO = try await send(
            .post, "/auth/login",
            body: Body(handle: handle, password: password),
            authenticated: false
        )
        await MainActor.run { tokens.store(pair) }
    }

    func logout() async {
        if let refresh = await MainActor.run(body: { tokens.refreshToken }) {
            struct Body: Encodable { let refreshToken: String }
            // Best effort: if the server never hears about it the token still
            // expires, and refusing to sign the user out locally because the
            // network is down would be absurd.
            _ = try? await sendVoid(.post, "/auth/logout",
                                    body: Body(refreshToken: refresh), authenticated: false)
        }
        await MainActor.run { tokens.clear() }
    }

    func me() async throws -> UserProfileDTO {
        try await send(.get, "/auth/me")
    }

    func createCatch(_ body: CreateCatchDTO) async throws -> CatchDTO {
        try await send(.post, "/catches", body: body)
    }

    func myCatches() async throws -> [CatchDTO] {
        try await send(.get, "/catches/me")
    }

    func nearby(lat: Double, lng: Double, radiusM: Double) async throws -> [CatchDTO] {
        try await send(.get, "/catches/nearby?lat=\(lat)&lng=\(lng)&radius_m=\(Int(radiusM))")
    }

    func friends() async throws -> [FriendDTO] {
        try await send(.get, "/friends")
    }

    func requestFriend(handle: String) async throws -> FriendDTO {
        struct Body: Encodable { let handle: String }
        return try await send(.post, "/friends/request", body: Body(handle: handle))
    }

    func acceptFriend(id: UUID) async throws {
        try await sendVoid(.post, "/friends/\(id.uuidString)/accept")
    }

    func declineFriend(id: UUID) async throws {
        try await sendVoid(.post, "/friends/\(id.uuidString)/decline")
    }

    func friendDex(id: UUID) async throws -> [DexEntryDTO] {
        try await send(.get, "/friends/\(id.uuidString)/dex")
    }

    // MARK: - Media

    func requestUploadURL(contentType: String, byteSize: Int) async throws -> UploadURLDTO {
        struct Body: Encodable { let contentType: String, byteSize: Int }
        return try await send(
            .post, "/media/upload-url",
            body: Body(contentType: contentType, byteSize: byteSize),
            base: APIConfig.mediaAPI
        )
    }

    /// PUT the bytes straight to object storage using the presigned URL.
    /// They never pass through our API — that is the entire point of presigning.
    func uploadImageData(_ data: Data, to presignedURL: String, contentType: String) async throws {
        guard let url = URL(string: presignedURL) else {
            throw APIError.server(code: "bad_url", message: "Invalid upload URL.", status: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.server(code: "upload_failed", message: "Upload rejected by storage.", status: status)
        }
    }

    func completeUpload(mediaId: UUID) async throws -> MediaDTO {
        try await send(.post, "/media/\(mediaId.uuidString)/complete", base: APIConfig.mediaAPI)
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST", delete = "DELETE" }

    private func send<T: Decodable>(
        _ method: Method,
        _ path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        base: URL? = nil
    ) async throws -> T {
        let data = try await perform(method, path, body: body, authenticated: authenticated, base: base)
        do {
            return try APIConfig.decoder.decode(T.self, from: data)
        } catch {
            log.error("decode failed for \(path, privacy: .public): \(error)")
            throw APIError.decoding(error)
        }
    }

    @discardableResult
    private func sendVoid(
        _ method: Method,
        _ path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        base: URL? = nil
    ) async throws -> Data {
        try await perform(method, path, body: body, authenticated: authenticated, base: base)
    }

    private func perform(
        _ method: Method,
        _ path: String,
        body: (any Encodable)?,
        authenticated: Bool,
        base: URL?
    ) async throws -> Data {
        let (data, status) = try await rawRequest(method, path, body: body, authenticated: authenticated, base: base)

        // 401 on an authenticated call means the access token aged out. Refresh
        // once, then retry exactly once — retrying in a loop would spin forever
        // against a genuinely revoked session.
        if status == 401 && authenticated {
            try await refreshIfNeeded()
            let (retryData, retryStatus) = try await rawRequest(
                method, path, body: body, authenticated: true, base: base
            )
            guard (200..<300).contains(retryStatus) else {
                throw error(from: retryData, status: retryStatus)
            }
            return retryData
        }

        guard (200..<300).contains(status) else {
            throw error(from: data, status: status)
        }
        return data
    }

    private func rawRequest(
        _ method: Method,
        _ path: String,
        body: (any Encodable)?,
        authenticated: Bool,
        base: URL?
    ) async throws -> (Data, Int) {
        let root = base ?? APIConfig.coreAPI
        guard let url = URL(string: root.absoluteString + path) else {
            throw APIError.server(code: "bad_url", message: "Invalid URL.", status: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = await MainActor.run(body: { tokens.accessToken }) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try APIConfig.encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Single-flight token refresh.
    private func refreshIfNeeded() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [tokens] in
            guard let refresh = await MainActor.run(body: { tokens.refreshToken }) else {
                throw APIError.unauthorized
            }
            struct Body: Encodable { let refreshToken: String }
            let (data, status) = try await rawRequest(
                .post, "/auth/refresh",
                body: Body(refreshToken: refresh),
                authenticated: false,
                base: nil
            )
            guard status == 200 else {
                // The refresh token is dead — expired, revoked, or its family was
                // burned by reuse detection. Clearing state signs the user out
                // rather than leaving the app in a permanently failing loop.
                await MainActor.run { tokens.clear() }
                throw APIError.unauthorized
            }
            let pair = try APIConfig.decoder.decode(TokenPairDTO.self, from: data)
            await MainActor.run { tokens.store(pair) }
        }

        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func error(from data: Data, status: Int) -> APIError {
        if status == 401 { return .unauthorized }
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return .server(code: body.error.code, message: body.error.message, status: status)
        }
        return .server(code: "unknown", message: "Request failed (\(status)).", status: status)
    }
}
