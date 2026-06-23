import Foundation

enum XBLiveEmulatorPresenceService {
    private static let presenceURL = URL(string: "https://xb.live/api/emulator/presence")!

    struct Response: Decodable, Equatable {
        let success: Bool?
        let ok: Bool?
        let status: Int?
        let online: Bool?
        let titleId: String?
        let gameName: String?
        let creditedMinutes: Double?
        let totalMinutes: Double?
        let recommendedPingMs: Int?
        let offlineAfterMs: Int?
        let maxCreditMinutesPerPing: Double?
    }

    enum PresenceError: LocalizedError, Equatable {
        case unauthorized
        case banned(String)
        case server(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "XB.Live session expired. Sign in again to update emulator presence."
            case .banned(let message):
                return message
            case .server(let message):
                return message
            case .invalidResponse:
                return "XB.Live returned an invalid emulator presence response."
            }
        }
    }

    static func postOnline(sessionKey: String, titleID: String) async throws -> Response {
        try await post(sessionKey: sessionKey, titleID: titleID, online: true)
    }

    static func postOffline(sessionKey: String) async throws -> Response {
        try await post(sessionKey: sessionKey, titleID: nil, online: false)
    }

    private static func post(sessionKey: String, titleID: String?, online: Bool) async throws -> Response {
        var request = URLRequest(url: presenceURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        request.httpBody = try JSONEncoder().encode(
            PresenceRequest(titleID: titleID.map(apiTitleID), online: online)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PresenceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw PresenceError.unauthorized
            }

            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let message = errorResponse?.error ?? "XB.Live emulator presence failed with status \(httpResponse.statusCode)."
            if httpResponse.statusCode == 403, errorResponse?.banned == true {
                throw PresenceError.banned(message)
            }
            throw PresenceError.server(message)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func apiTitleID(_ titleID: String) -> String {
        titleID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private struct PresenceRequest: Encodable {
        let titleID: String?
        let online: Bool

        enum CodingKeys: String, CodingKey {
            case titleID = "title_id"
            case online
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let banned: Bool?
    }
}

@MainActor
final class XBLiveEmulatorPresenceCoordinator: ObservableObject {
    private struct ActiveSession: Equatable, Sendable {
        let sessionKey: String
        let titleID: String
        let gameName: String
    }

    private enum HeartbeatOutcome {
        case sent(XBLiveEmulatorPresenceService.Response)
        case authenticationFailure(String)
        case failed
        case cancelled
    }

    nonisolated private static let defaultHeartbeatMilliseconds = 240_000
    nonisolated private static let expirySafetyMarginMilliseconds = 60_000
    nonisolated private static let minimumHeartbeatMilliseconds = 5_000
    nonisolated private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    private var activeSession: ActiveSession?
    private var heartbeatTask: Task<Void, Never>?

    var onAuthenticationFailure: ((String) -> Void)?

    func start(titleID: String?, gameName: String) {
        guard let titleID = GameLaunchLink.normalizedTitleID(titleID) else {
            NSLog("XB.Live emulator presence skipped for %@: missing title ID", gameName)
            stopTimerOnly()
            activeSession = nil
            return
        }

        guard let sessionKey = try? InsigniaProfileStore.storedSessionKey(),
              !sessionKey.isEmpty else {
            NSLog("XB.Live emulator presence skipped for %@: missing session key", gameName)
            stopTimerOnly()
            activeSession = nil
            return
        }

        let session = ActiveSession(sessionKey: sessionKey, titleID: titleID, gameName: gameName)
        if activeSession == session, heartbeatTask?.isCancelled == false {
            return
        }

        stopTimerOnly()
        activeSession = session
        heartbeatTask = Task.detached(priority: .background) { [weak self] in
            if let authenticationFailure = await Self.runOnlineHeartbeatLoop(for: session) {
                await MainActor.run {
                    self?.handleAuthenticationFailure(authenticationFailure, for: session)
                }
            }
        }
    }

    func stop(reason: String) {
        stopTimerOnly()
        guard let session = activeSession else {
            return
        }

        activeSession = nil
        Task {
            await sendOffline(for: session, reason: reason)
        }
    }

    private func stopTimerOnly() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    nonisolated private static var defaultHeartbeatNanoseconds: UInt64 {
        UInt64(defaultHeartbeatMilliseconds) * nanosecondsPerMillisecond
    }

    nonisolated private static func runOnlineHeartbeatLoop(for session: ActiveSession) async -> String? {
        var nextHeartbeatNanoseconds = defaultHeartbeatNanoseconds
        switch await sendOnlineHeartbeat(for: session, isInitial: true) {
        case .sent(let response):
            nextHeartbeatNanoseconds = heartbeatNanoseconds(after: response)
            logNextHeartbeat(nextHeartbeatNanoseconds, for: session)
        case .authenticationFailure(let message):
            return message
        case .failed:
            break
        case .cancelled:
            return nil
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: nextHeartbeatNanoseconds)
            } catch {
                return nil
            }

            guard !Task.isCancelled else {
                return nil
            }

            switch await sendOnlineHeartbeat(for: session, isInitial: false) {
            case .sent(let response):
                nextHeartbeatNanoseconds = heartbeatNanoseconds(after: response)
                logNextHeartbeat(nextHeartbeatNanoseconds, for: session)
            case .authenticationFailure(let message):
                return message
            case .failed:
                nextHeartbeatNanoseconds = defaultHeartbeatNanoseconds
            case .cancelled:
                return nil
            }
        }

        return nil
    }

    nonisolated private static func heartbeatNanoseconds(after response: XBLiveEmulatorPresenceService.Response) -> UInt64 {
        var milliseconds = defaultHeartbeatMilliseconds
        if let recommendedPingMs = response.recommendedPingMs,
           recommendedPingMs > 0 {
            milliseconds = min(milliseconds, recommendedPingMs)
        }
        if let offlineAfterMs = response.offlineAfterMs,
           offlineAfterMs > 0 {
            let safeExpiryMilliseconds: Int
            if offlineAfterMs > expirySafetyMarginMilliseconds + minimumHeartbeatMilliseconds {
                safeExpiryMilliseconds = offlineAfterMs - expirySafetyMarginMilliseconds
            } else {
                safeExpiryMilliseconds = max(minimumHeartbeatMilliseconds, offlineAfterMs / 2)
            }
            milliseconds = min(milliseconds, safeExpiryMilliseconds)
        }
        return UInt64(max(minimumHeartbeatMilliseconds, milliseconds)) * nanosecondsPerMillisecond
    }

    nonisolated private static func logNextHeartbeat(_ nanoseconds: UInt64, for session: ActiveSession) {
        NSLog(
            "XB.Live emulator presence next heartbeat scheduled: %@ in %.0f seconds",
            session.titleID,
            Double(nanoseconds) / 1_000_000_000
        )
    }

    nonisolated private static func sendOnlineHeartbeat(
        for session: ActiveSession,
        isInitial: Bool
    ) async -> HeartbeatOutcome {
        guard !Task.isCancelled else {
            return .cancelled
        }
        do {
            let response = try await XBLiveEmulatorPresenceService.postOnline(
                sessionKey: session.sessionKey,
                titleID: session.titleID
            )
            NSLog(
                "XB.Live emulator presence %@ heartbeat sent: %@ %@ credited=%@ total=%@",
                isInitial ? "initial" : "interval",
                session.titleID,
                response.gameName ?? session.gameName,
                response.creditedMinutes.map(String.init(describing:)) ?? "nil",
                response.totalMinutes.map(String.init(describing:)) ?? "nil"
            )
            return .sent(response)
        } catch {
            if Task.isCancelled {
                return .cancelled
            }
            return heartbeatOutcome(for: error)
        }
    }

    nonisolated private static func heartbeatOutcome(for error: Error) -> HeartbeatOutcome {
        NSLog("XB.Live emulator presence failed: %@", error.localizedDescription)

        if let presenceError = error as? XBLiveEmulatorPresenceService.PresenceError {
            switch presenceError {
            case .unauthorized, .banned:
                return .authenticationFailure(presenceError.localizedDescription)
            case .server, .invalidResponse:
                return .failed
            }
        }

        return .failed
    }

    private func handleAuthenticationFailure(_ message: String, for session: ActiveSession) {
        guard activeSession == session else {
            return
        }
        stopTimerOnly()
        activeSession = nil
        onAuthenticationFailure?(message)
    }

    private func sendOffline(for session: ActiveSession, reason: String) async {
        do {
            let response = try await XBLiveEmulatorPresenceService.postOffline(sessionKey: session.sessionKey)
            NSLog(
                "XB.Live emulator presence offline sent (%@): credited=%@ online=%@",
                reason,
                response.creditedMinutes.map(String.init(describing:)) ?? "nil",
                response.online.map(String.init(describing:)) ?? "nil"
            )
        } catch {
            handlePresenceError(error)
        }
    }

    private func handlePresenceError(_ error: Error) {
        NSLog("XB.Live emulator presence failed: %@", error.localizedDescription)

        if let presenceError = error as? XBLiveEmulatorPresenceService.PresenceError {
            switch presenceError {
            case .unauthorized, .banned:
                stopTimerOnly()
                activeSession = nil
                onAuthenticationFailure?(presenceError.localizedDescription)
            case .server, .invalidResponse:
                break
            }
        }
    }
}
