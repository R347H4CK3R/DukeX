import Foundation
import UIKit
import UserNotifications

struct XBLiveSocialNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
}

enum XBLiveFriendRelationshipStatus: String, Codable, Equatable {
    case none
    case friends
    case incoming
    case outgoing
}

struct XBLiveSocialMessage: Codable, Identifiable, Equatable {
    let id: String
    let sender: String
    let recipient: String?
    let body: String
    let kind: String
    let createdAt: String?
    let readAt: String?
    let filtered: Bool?

    var numericID: Int? {
        Int(id)
    }

    var isRead: Bool {
        readAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func isFromCurrentUser(_ username: String?) -> Bool {
        guard let username else {
            return false
        }

        return Self.normalized(sender) == Self.normalized(username)
    }

    func otherUser(relativeTo username: String?) -> String? {
        let currentUserKey = username?.socialNormalizedKey
        if let sender = sender.nilIfBlank,
           sender.socialNormalizedKey != "unknown",
           sender.socialNormalizedKey != currentUserKey {
            return sender
        }

        if let recipient = recipient?.nilIfBlank,
           recipient.socialNormalizedKey != "unknown",
           recipient.socialNormalizedKey != currentUserKey {
            return recipient
        }

        if isFromCurrentUser(username) {
            return recipient?.nilIfBlank
        }
        return sender.nilIfBlank?.socialNormalizedKey == "unknown" ? nil : sender.nilIfBlank
    }

    func resolvingParticipantNames(currentUser: String?, threadUsername: String) -> XBLiveSocialMessage {
        let threadUser = threadUsername.nilIfBlank ?? sender
        let currentUserKey = currentUser?.socialNormalizedKey
        let threadUserKey = threadUser.socialNormalizedKey
        var resolvedSender = sender
        var resolvedRecipient = recipient

        if sender.nilIfBlank == nil || sender.socialNormalizedKey == "unknown" {
            if let recipientKey = recipient?.socialNormalizedKey,
               let currentUserKey,
               recipientKey == currentUserKey {
                resolvedSender = threadUser
            } else if let recipientKey = recipient?.socialNormalizedKey,
                      recipientKey == threadUserKey,
                      let currentUser = currentUser?.nilIfBlank {
                resolvedSender = currentUser
            } else {
                resolvedSender = threadUser
            }
        }

        if recipient?.nilIfBlank == nil || recipient?.socialNormalizedKey == "unknown" {
            if resolvedSender.socialNormalizedKey == threadUserKey {
                resolvedRecipient = currentUser?.nilIfBlank
            } else {
                resolvedRecipient = threadUser
            }
        }

        return XBLiveSocialMessage(
            id: id,
            sender: resolvedSender,
            recipient: resolvedRecipient,
            body: body,
            kind: kind,
            createdAt: createdAt,
            readAt: readAt,
            filtered: filtered
        )
    }

    static func timestampValue(_ rawValue: String?) -> Double? {
        guard let rawValue = rawValue?.nilIfBlank else {
            return nil
        }

        if let number = Double(rawValue) {
            return number > 9_999_999_999 ? number / 1_000.0 : number
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: rawValue) {
            return date.timeIntervalSince1970
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date.timeIntervalSince1970
        }

        return nil
    }

    static func chronologicalSort(_ lhs: XBLiveSocialMessage, _ rhs: XBLiveSocialMessage) -> Bool {
        if timestampValue(lhs.createdAt) != timestampValue(rhs.createdAt) {
            return (timestampValue(lhs.createdAt) ?? .greatestFiniteMagnitude) <
                (timestampValue(rhs.createdAt) ?? .greatestFiniteMagnitude)
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }

    init(
        id: String,
        sender: String,
        recipient: String?,
        body: String,
        kind: String,
        createdAt: String?,
        readAt: String?,
        filtered: Bool?
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
        self.readAt = readAt
        self.filtered = filtered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        id = container.flexibleString(for: [
            "id",
            "messageId",
            "message_id"
        ]) ?? UUID().uuidString
        sender = container.flexibleString(for: [
            "from",
            "from_user",
            "fromUser",
            "from_username",
            "fromUsername",
            "from_name",
            "fromName",
            "sender",
            "sender_user",
            "senderUser",
            "sender_username",
            "senderUsername",
            "sender_name",
            "senderName",
            "author",
            "username"
        ]) ?? "Unknown"
        recipient = container.flexibleString(for: [
            "to",
            "to_user",
            "toUser",
            "to_username",
            "toUsername",
            "to_name",
            "toName",
            "recipient",
            "recipient_user",
            "recipientUser",
            "recipient_username",
            "recipientUsername",
            "recipient_name",
            "recipientName",
            "target",
            "target_user",
            "targetUser",
            "target_username",
            "targetUsername"
        ])
        body = container.flexibleString(for: [
            "body",
            "message",
            "text",
            "content",
            "preview",
            "snippet"
        ]) ?? ""
        kind = container.flexibleString(for: [
            "kind",
            "type"
        ]) ?? "message"
        createdAt = container.flexibleString(for: [
            "created_at",
            "createdAt",
            "sent_at",
            "sentAt",
            "date",
            "timestamp"
        ])
        let decodedReadAt = container.flexibleString(for: [
            "read_at",
            "readAt",
            "opened_at",
            "openedAt"
        ])
        let readFlag = container.flexibleBool(for: [
            "read",
            "isRead",
            "is_read",
            "opened",
            "seen",
            "viewed"
        ])
        let unreadFlag = container.flexibleBool(for: [
            "unread",
            "isUnread",
            "is_unread",
            "new"
        ])
        if decodedReadAt?.nilIfBlank != nil {
            readAt = decodedReadAt
        } else if readFlag == true || unreadFlag == false {
            readAt = "read"
        } else {
            readAt = nil
        }
        filtered = container.flexibleBool(for: [
            "filtered",
            "was_filtered",
            "wasFiltered"
        ])
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct XBLiveSocialConversation: Codable, Identifiable, Equatable {
    let username: String
    let latestBody: String?
    let latestSender: String?
    let latestRecipient: String?
    let latestAt: String?
    let unreadCount: Int
    let messageCount: Int?
    let avatarURLString: String?

    var id: String { key }
    var key: String { username.socialNormalizedKey }
    var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }

    init(
        username: String,
        latestBody: String?,
        latestSender: String?,
        latestRecipient: String?,
        latestAt: String?,
        unreadCount: Int,
        messageCount: Int?,
        avatarURLString: String?
    ) {
        self.username = username
        self.latestBody = latestBody
        self.latestSender = latestSender
        self.latestRecipient = latestRecipient
        self.latestAt = latestAt
        self.unreadCount = unreadCount
        self.messageCount = messageCount
        self.avatarURLString = avatarURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        let latestMessage: XBLiveSocialMessage? =
            container.flexibleDecode(XBLiveSocialMessage.self, for: ["latest", "lastMessage", "last_message", "message"])
        username = container.flexibleString(for: [
            "with",
            "with_user",
            "withUser",
            "with_username",
            "withUsername",
            "other",
            "other_user",
            "otherUser",
            "other_username",
            "otherUsername",
            "username",
            "user",
            "gamertag",
            "displayName",
            "display_name",
            "friend",
            "friend_username",
            "friendUsername",
            "recipient",
            "recipient_username",
            "recipientUsername",
            "sender",
            "sender_username",
            "senderUsername"
        ]) ?? latestMessage?.sender ?? "Unknown"
        latestBody = container.flexibleString(for: [
            "latestBody",
            "latest_body",
            "lastBody",
            "last_body",
            "body",
            "message",
            "preview",
            "snippet"
        ]) ?? latestMessage?.body
        latestSender = container.flexibleString(for: [
            "latestSender",
            "latest_sender",
            "lastSender",
            "last_sender",
            "from",
            "sender"
        ]) ?? latestMessage?.sender
        latestRecipient = container.flexibleString(for: [
            "latestRecipient",
            "latest_recipient",
            "lastRecipient",
            "last_recipient",
            "to",
            "recipient"
        ]) ?? latestMessage?.recipient
        latestAt = container.flexibleString(for: [
            "latestAt",
            "latest_at",
            "lastAt",
            "last_at",
            "created_at",
            "createdAt",
            "sent_at",
            "sentAt"
        ]) ?? latestMessage?.createdAt
        unreadCount = container.flexibleInt(for: [
            "unread",
            "unread_count",
            "unreadCount",
            "new"
        ]) ?? 0
        messageCount = container.flexibleInt(for: [
            "count",
            "message_count",
            "messageCount",
            "total"
        ])
        avatarURLString = container.flexibleString(for: [
            "avatar",
            "avatar_url",
            "avatarURL",
            "avatarUrl",
            "image_url",
            "imageUrl"
        ])
    }

    func normalized(currentUser: String?) -> XBLiveSocialConversation {
        let currentUserKey = currentUser?.socialNormalizedKey
        let shouldCorrectUsername = username.nilIfBlank == nil ||
            username.socialNormalizedKey == "unknown" ||
            username.socialNormalizedKey == currentUserKey

        guard shouldCorrectUsername else {
            return self
        }

        let correctedUsername: String?
        if let latestSender,
           latestSender.socialNormalizedKey != "unknown",
           latestSender.socialNormalizedKey != currentUserKey {
            correctedUsername = latestSender
        } else if let latestRecipient,
                  latestRecipient.socialNormalizedKey != "unknown",
                  latestRecipient.socialNormalizedKey != currentUserKey {
            correctedUsername = latestRecipient
        } else {
            correctedUsername = nil
        }

        guard let correctedUsername = correctedUsername?.nilIfBlank else {
            return self
        }

        return XBLiveSocialConversation(
            username: correctedUsername,
            latestBody: latestBody,
            latestSender: latestSender,
            latestRecipient: latestRecipient,
            latestAt: latestAt,
            unreadCount: unreadCount,
            messageCount: messageCount,
            avatarURLString: avatarURLString
        )
    }

    func replacingUsername(with username: String) -> XBLiveSocialConversation {
        XBLiveSocialConversation(
            username: username,
            latestBody: latestBody,
            latestSender: latestSender,
            latestRecipient: latestRecipient,
            latestAt: latestAt,
            unreadCount: unreadCount,
            messageCount: messageCount,
            avatarURLString: avatarURLString
        )
    }

    func replacingUnreadCount(with unreadCount: Int) -> XBLiveSocialConversation {
        XBLiveSocialConversation(
            username: username,
            latestBody: latestBody,
            latestSender: latestSender,
            latestRecipient: latestRecipient,
            latestAt: latestAt,
            unreadCount: unreadCount,
            messageCount: messageCount,
            avatarURLString: avatarURLString
        )
    }
}

struct XBLiveSocialFriend: Codable, Identifiable, Equatable {
    let username: String
    let displayName: String?
    let status: String?
    let avatarURLString: String?
    let isOnline: Bool?
    let currentGame: String?
    let lastOnlineAt: Double?

    var id: String { key }
    var key: String { username.socialNormalizedKey }
    var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }
    var title: String { displayName?.nilIfBlank ?? username }

    init(
        username: String,
        displayName: String?,
        status: String?,
        avatarURLString: String?,
        isOnline: Bool?,
        currentGame: String?,
        lastOnlineAt: Double?
    ) {
        self.username = username
        self.displayName = displayName
        self.status = status
        self.avatarURLString = avatarURLString
        self.isOnline = isOnline
        self.currentGame = currentGame
        self.lastOnlineAt = lastOnlineAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        username = container.flexibleString(for: [
            "username",
            "gamertag",
            "displayName",
            "display_name",
            "name",
            "user",
            "friend"
        ]) ?? "Unknown"
        displayName = container.flexibleString(for: [
            "displayName",
            "display_name",
            "gamertag",
            "name"
        ])
        status = container.flexibleString(for: [
            "status",
            "state",
            "lastState",
            "last_state"
        ])
        avatarURLString = container.flexibleString(for: [
            "avatar",
            "avatar_url",
            "avatarURL",
            "avatarUrl",
            "image_url",
            "imageUrl"
        ])
        isOnline = container.flexibleBool(for: [
            "online",
            "isOnline",
            "is_online",
            "active"
        ])
        currentGame = container.flexibleString(for: [
            "currentGame",
            "current_game",
            "game",
            "activeGame",
            "active_game"
        ])
        lastOnlineAt = container.flexibleDouble(for: [
            "lastOnlineAt",
            "last_online_at",
            "lastSeenAt",
            "last_seen_at",
            "lastActiveAt",
            "last_active_at"
        ])
    }

    init(username: String) {
        self.username = username
        displayName = nil
        status = nil
        avatarURLString = nil
        isOnline = nil
        currentGame = nil
        lastOnlineAt = nil
    }
}

struct XBLiveFriendRequest: Codable, Identifiable, Equatable {
    let username: String
    let fromUsername: String?
    let toUsername: String?
    let createdAt: String?
    let message: String?

    var id: String { username.socialNormalizedKey }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        fromUsername = container.flexibleString(for: [
            "from",
            "from_user",
            "fromUser",
            "sender",
            "sender_username",
            "senderUsername"
        ])
        toUsername = container.flexibleString(for: [
            "to",
            "to_user",
            "toUser",
            "recipient",
            "recipient_username",
            "recipientUsername"
        ])
        username = container.flexibleString(for: [
            "username",
            "user",
            "gamertag",
            "displayName",
            "display_name"
        ]) ?? fromUsername ?? toUsername ?? "Unknown"
        createdAt = container.flexibleString(for: [
            "created_at",
            "createdAt",
            "sent_at",
            "sentAt"
        ])
        message = container.flexibleString(for: [
            "message",
            "body",
            "note"
        ])
    }

    init(username: String, createdAt: String? = nil, message: String? = nil) {
        self.username = username
        fromUsername = nil
        toUsername = nil
        self.createdAt = createdAt
        self.message = message
    }

    func withUsername(_ username: String) -> XBLiveFriendRequest {
        XBLiveFriendRequest(username: username, createdAt: createdAt, message: message)
    }
}

struct XBLiveMessagesInboxResponse: Decodable, Equatable {
    let user: String?
    let unread: Int
    let count: Int
    let messages: [XBLiveSocialMessage]
}

struct XBLiveConversationsResponse: Decodable, Equatable {
    let user: String?
    let count: Int
    let conversations: [XBLiveSocialConversation]
}

struct XBLiveMessageThreadResponse: Decodable, Equatable {
    let user: String?
    let with: String
    let count: Int
    let messages: [XBLiveSocialMessage]
}

struct XBLiveMessageableFriendsResponse: Decodable, Equatable {
    let user: String?
    let count: Int
    let friends: [XBLiveSocialFriend]
}

struct XBLiveFriendStatusResponse: Decodable, Equatable {
    let user: String?
    let other: String
    let status: XBLiveFriendRelationshipStatus
}

struct XBLiveFriendRequestsResponse: Decodable, Equatable {
    let user: String?
    let incoming: [XBLiveFriendRequest]
    let outgoing: [XBLiveFriendRequest]
}

struct XBLiveBlocksResponse: Decodable, Equatable {
    let user: String?
    let count: Int
    let blocked: [String]
}

struct XBLiveSendMessageResponse: Decodable, Equatable {
    let success: Bool
    let id: Int?
    let createdAt: String?
    let filtered: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        success = container.flexibleBool(for: ["success"]) ?? true
        id = container.flexibleInt(for: ["id", "messageId", "message_id"])
        createdAt = container.flexibleString(for: [
            "created_at",
            "createdAt",
            "sent_at",
            "sentAt",
            "timestamp"
        ])
        filtered = container.flexibleBool(for: [
            "filtered",
            "was_filtered",
            "wasFiltered"
        ])
    }
}

struct XBLiveFriendActionResponse: Decodable, Equatable {
    let success: Bool
    let status: XBLiveFriendRelationshipStatus?
    let accepted: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        success = container.flexibleBool(for: ["success"]) ?? true
        if let rawStatus = container.flexibleString(for: ["status"]) {
            status = XBLiveFriendRelationshipStatus(rawValue: rawStatus.socialNormalizedKey)
        } else {
            status = nil
        }
        accepted = container.flexibleBool(for: ["accepted"])
    }
}

struct XBLiveReportResponse: Decodable, Equatable {
    let success: Bool
    let id: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
        success = container.flexibleBool(for: ["success"]) ?? true
        id = container.flexibleInt(for: ["id", "reportId", "report_id"])
    }
}

enum XBLiveSocialServiceError: LocalizedError, Equatable {
    case missingSession
    case unauthorized
    case serverMessage(String)
    case blocked(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Sign in with an Insignia account to use XB.Live social features."
        case .unauthorized:
            return "The Insignia session is no longer valid. Sign in again to continue."
        case .serverMessage(let message):
            return message
        case .blocked(let message):
            return message
        case .unavailable:
            return "XB.Live social services are unavailable."
        }
    }
}

enum XBLiveSocialService {
    private static let baseURL = URL(string: "https://xb.live/api")!

    static func fetchInbox(sessionKey: String, kind: String = "message") async throws -> XBLiveMessagesInboxResponse {
        try await decodedResponse(
            XBLiveMessagesInboxResponse.self,
            pathComponents: ["xbl", "messages"],
            queryItems: [URLQueryItem(name: "kind", value: kind)],
            sessionKey: sessionKey
        )
    }

    static func fetchConversations(sessionKey: String) async throws -> XBLiveConversationsResponse {
        try await decodedResponse(
            XBLiveConversationsResponse.self,
            pathComponents: ["xbl", "messages", "conversations"],
            sessionKey: sessionKey
        )
    }

    static func fetchThread(sessionKey: String, with username: String) async throws -> XBLiveMessageThreadResponse {
        try await decodedResponse(
            XBLiveMessageThreadResponse.self,
            pathComponents: ["xbl", "messages", "thread"],
            queryItems: [URLQueryItem(name: "with", value: username)],
            sessionKey: sessionKey
        )
    }

    static func sendMessage(sessionKey: String, to username: String, body: String) async throws -> XBLiveSendMessageResponse {
        try await decodedResponse(
            XBLiveSendMessageResponse.self,
            pathComponents: ["xbl", "messages"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(SendMessageRequest(to: username, body: body))
        )
    }

    static func markRead(sessionKey: String, id: Int) async throws -> ReadResponse {
        try await decodedResponse(
            ReadResponse.self,
            pathComponents: ["xbl", "messages", "read"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(ReadRequest(id: id, all: nil))
        )
    }

    static func markAllRead(sessionKey: String) async throws -> ReadResponse {
        try await decodedResponse(
            ReadResponse.self,
            pathComponents: ["xbl", "messages", "read"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(ReadRequest(id: nil, all: true))
        )
    }

    static func fetchMessageableFriends(sessionKey: String) async throws -> XBLiveMessageableFriendsResponse {
        try await decodedResponse(
            XBLiveMessageableFriendsResponse.self,
            pathComponents: ["xbl", "messageable-friends"],
            sessionKey: sessionKey
        )
    }

    static func fetchFriendStatus(sessionKey: String, user: String) async throws -> XBLiveFriendStatusResponse {
        try await decodedResponse(
            XBLiveFriendStatusResponse.self,
            pathComponents: ["xbl", "friends", "status"],
            queryItems: [URLQueryItem(name: "user", value: user)],
            sessionKey: sessionKey
        )
    }

    static func fetchFriendRequests(sessionKey: String) async throws -> XBLiveFriendRequestsResponse {
        try await decodedResponse(
            XBLiveFriendRequestsResponse.self,
            pathComponents: ["xbl", "friends", "requests"],
            sessionKey: sessionKey
        )
    }

    static func sendFriendRequest(sessionKey: String, to username: String) async throws -> XBLiveFriendActionResponse {
        try await decodedResponse(
            XBLiveFriendActionResponse.self,
            pathComponents: ["xbl", "friends", "request"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(UserTargetRequest(to: username))
        )
    }

    static func respondToFriendRequest(
        sessionKey: String,
        from username: String,
        action: FriendRequestAction
    ) async throws -> XBLiveFriendActionResponse {
        try await decodedResponse(
            XBLiveFriendActionResponse.self,
            pathComponents: ["xbl", "friends", "respond"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(FriendResponseRequest(from: username, action: action.rawValue))
        )
    }

    static func cancelFriendRequest(sessionKey: String, to username: String) async throws -> XBLiveFriendActionResponse {
        try await decodedResponse(
            XBLiveFriendActionResponse.self,
            pathComponents: ["xbl", "friends", "cancel"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(UserTargetRequest(to: username))
        )
    }

    static func removeFriend(sessionKey: String, user: String) async throws -> XBLiveFriendActionResponse {
        try await decodedResponse(
            XBLiveFriendActionResponse.self,
            pathComponents: ["xbl", "friends", "remove"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(UserRequest(user: user))
        )
    }

    static func blockUser(sessionKey: String, user: String, reason: String?) async throws -> BlockResponse {
        try await decodedResponse(
            BlockResponse.self,
            pathComponents: ["xbl", "block"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(BlockRequest(user: user, reason: reason))
        )
    }

    static func unblockUser(sessionKey: String, user: String) async throws -> UnblockResponse {
        try await decodedResponse(
            UnblockResponse.self,
            pathComponents: ["xbl", "unblock"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(UserRequest(user: user))
        )
    }

    static func fetchBlocks(sessionKey: String) async throws -> XBLiveBlocksResponse {
        try await decodedResponse(
            XBLiveBlocksResponse.self,
            pathComponents: ["xbl", "blocks"],
            sessionKey: sessionKey
        )
    }

    static func report(
        sessionKey: String,
        reported: String,
        context: String,
        messageId: Int?,
        body: String?,
        source: String?,
        reason: String?
    ) async throws -> XBLiveReportResponse {
        try await decodedResponse(
            XBLiveReportResponse.self,
            pathComponents: ["xbl", "report"],
            method: "POST",
            sessionKey: sessionKey,
            body: try JSONEncoder().encode(
                ReportRequest(
                    reported: reported,
                    context: context,
                    messageId: messageId,
                    body: body,
                    source: source,
                    reason: reason
                )
            )
        )
    }

    private static func decodedResponse<T: Decodable>(
        _ type: T.Type,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        sessionKey: String,
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: endpointURL(pathComponents: pathComponents, queryItems: queryItems))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XBLiveSocialServiceError.unavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw XBLiveSocialServiceError.unauthorized
            }

            if let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = error.error?.nilIfBlank {
                if httpResponse.statusCode == 403, error.blocked == true {
                    throw XBLiveSocialServiceError.blocked(message)
                }
                throw XBLiveSocialServiceError.serverMessage(message)
            }

            throw XBLiveSocialServiceError.unavailable
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private static func endpointURL(pathComponents: [String], queryItems: [URLQueryItem]) -> URL {
        var url = baseURL
        for component in pathComponents {
            url.appendPathComponent(component)
        }

        guard !queryItems.isEmpty else {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    enum FriendRequestAction: String {
        case accept
        case decline
    }

    struct ReadResponse: Decodable, Equatable {
        let success: Bool
        let unread: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
            success = container.flexibleBool(for: ["success"]) ?? true
            unread = container.flexibleInt(for: ["unread", "unread_count", "unreadCount"]) ?? 0
        }
    }

    struct BlockResponse: Decodable, Equatable {
        let success: Bool
        let blocked: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
            success = container.flexibleBool(for: ["success"]) ?? true
            blocked = container.flexibleString(for: ["blocked", "user", "username"]) ?? ""
        }
    }

    struct UnblockResponse: Decodable, Equatable {
        let success: Bool
        let unblocked: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: SocialFlexibleCodingKey.self)
            success = container.flexibleBool(for: ["success"]) ?? true
            unblocked = container.flexibleString(for: ["unblocked", "user", "username"]) ?? ""
        }
    }

    private struct SendMessageRequest: Encodable {
        let to: String
        let body: String
    }

    private struct ReadRequest: Encodable {
        let id: Int?
        let all: Bool?
    }

    private struct UserTargetRequest: Encodable {
        let to: String
    }

    private struct UserRequest: Encodable {
        let user: String
    }

    private struct FriendResponseRequest: Encodable {
        let from: String
        let action: String
    }

    private struct BlockRequest: Encodable {
        let user: String
        let reason: String?
    }

    private struct ReportRequest: Encodable {
        let reported: String
        let context: String
        let messageId: Int?
        let body: String?
        let source: String?
        let reason: String?
    }

    private struct APIErrorResponse: Decodable {
        let error: String?
        let blocked: Bool?
        let filtered: Bool?
    }
}

@MainActor
final class XBLiveSocialStore: ObservableObject {
    @Published private(set) var currentUsername: String?
    @Published private(set) var conversations: [XBLiveSocialConversation] = []
    @Published private(set) var inboxMessages: [XBLiveSocialMessage] = []
    @Published private(set) var messageableFriends: [XBLiveSocialFriend] = []
    @Published private(set) var incomingRequests: [XBLiveFriendRequest] = []
    @Published private(set) var outgoingRequests: [XBLiveFriendRequest] = []
    @Published private(set) var blockedUsers: [String] = []
    @Published private(set) var relationshipStatuses: [String: XBLiveFriendRelationshipStatus] = [:]
    @Published private(set) var threadMessagesByUser: [String: [XBLiveSocialMessage]] = [:]
    @Published private(set) var messageableFriendProfiles: [String: XBLiveFriendProfile] = [:]
    @Published private(set) var unreadCount = 0
    @Published private(set) var isRefreshingMessages = false
    @Published private(set) var isRefreshingFriends = false
    @Published var notice: XBLiveSocialNotice?

    private var notificationCustomAvatarImage: ((String) -> UIImage?)?
    private var notificationGameTitle: ((String, String?) -> String)?
    private var notificationGameLocalCoverURL: ((String) -> URL?)?
    private var messageThreadUsernamesByID: [String: String] = [:]
    private var messageThreadUsernamesBySignature: [String: String] = [:]
    private var messageIDsSentByCurrentUser: Set<String> = []
    private var locallyReadMessageIDs: Set<String> = []
    private var observedNotificationMessageKeys: Set<String> = []
    private var hasLoadedNotificationMessageBaseline = false
    private var lastOnlineNotificationStates: [String: Bool] = [:]
    private var hasLoadedOnlineNotificationBaseline = false
    private var activeThreadKey: String?

    private static let messageThreadUsernamesByIDKey = "XBLiveSocialStore.messageThreadUsernamesByID"
    private static let messageThreadUsernamesBySignatureKey = "XBLiveSocialStore.messageThreadUsernamesBySignature"
    private static let sentMessageIDsKey = "XBLiveSocialStore.sentMessageIDs"
    private static let locallyReadMessageIDsKey = "XBLiveSocialStore.locallyReadMessageIDs"
    private static let observedNotificationMessageKeysKey = "XBLiveSocialStore.observedNotificationMessageKeys"
    private static let maxObservedNotificationMessageKeys = 500

    init() {
        loadMessageIdentityCache()
        XBLiveSocialLocalNotificationPresenter.shared.activateForegroundPresentation()
    }

    var unreadMessagesText: String {
        "\(unreadCount) Unread"
    }

    var xbLiveFriendsText: String {
        let requestCount = incomingRequests.count
        if requestCount > 0 {
            return "\(requestCount) Pending"
        }
        return messageableFriends.isEmpty ? "None" : "\(messageableFriends.count)"
    }

    func clear() {
        currentUsername = nil
        conversations = []
        inboxMessages = []
        messageableFriends = []
        incomingRequests = []
        outgoingRequests = []
        blockedUsers = []
        relationshipStatuses = [:]
        threadMessagesByUser = [:]
        messageableFriendProfiles = [:]
        messageThreadUsernamesByID = [:]
        messageThreadUsernamesBySignature = [:]
        messageIDsSentByCurrentUser = []
        locallyReadMessageIDs = []
        hasLoadedNotificationMessageBaseline = false
        lastOnlineNotificationStates = [:]
        hasLoadedOnlineNotificationBaseline = false
        activeThreadKey = nil
        unreadCount = 0
        isRefreshingMessages = false
        isRefreshingFriends = false
        notice = nil
    }

    func configureLocalNotifications(
        customAvatarImage: @escaping (String) -> UIImage?,
        gameTitle: @escaping (String, String?) -> String,
        gameLocalCoverURL: @escaping (String) -> URL?
    ) {
        notificationCustomAvatarImage = customAvatarImage
        notificationGameTitle = gameTitle
        notificationGameLocalCoverURL = gameLocalCoverURL
        XBLiveSocialLocalNotificationPresenter.shared.activateForegroundPresentation()
    }

    func beginReadingThread(with username: String) {
        activeThreadKey = username.socialNormalizedKey
    }

    func endReadingThread(with username: String) {
        guard activeThreadKey == username.socialNormalizedKey else {
            return
        }

        activeThreadKey = nil
    }

    func refreshAll() async {
        await refreshMessages()
        await refreshFriends()
    }

    func refreshMessages() async {
        guard !isRefreshingMessages else {
            return
        }

        isRefreshingMessages = true
        defer { isRefreshingMessages = false }

        do {
            let sessionKey = try sessionKey()
            let inbox = try await XBLiveSocialService.fetchInbox(sessionKey: sessionKey)
            let conversationResponse = try await XBLiveSocialService.fetchConversations(sessionKey: sessionKey)
            let friendsResponse = try? await XBLiveSocialService.fetchMessageableFriends(sessionKey: sessionKey)

            currentUsername = inbox.user ?? conversationResponse.user ?? friendsResponse?.user ?? currentUsername
            let baseConversations = conversationResponse.conversations
                .map { $0.normalized(currentUser: currentUsername) }
                .filter(isKnownConversation)
            let resolvedInboxMessages = inbox.messages
                .map { normalizedInboxMessage($0, conversations: baseConversations) }
                .filter { isKnownMessage($0, currentUser: currentUsername) }
                .sorted(by: XBLiveSocialMessage.chronologicalSort)
            inboxMessages = resolvedInboxMessages
            unreadCount = resolvedInboxMessages.filter {
                !$0.isFromCurrentUser(currentUsername) && !$0.isRead
            }.count
            notifyForNewIncomingMessages(resolvedInboxMessages)
            conversations = baseConversations
                .map {
                    normalizedConversation(
                        $0,
                        currentUser: currentUsername,
                        inboxMessages: resolvedInboxMessages
                    )
                }
                .filter(isKnownConversation)
                .sorted(by: conversationSort)
            saveMessageIdentityCache()
            if let friendsResponse {
                let friends = friendsResponse.friends.sorted(by: friendSort)
                messageableFriends = friends
            }
        } catch {
            handle(error, title: "Messages Not Synced")
        }
    }

    func refreshFriends() async {
        guard !isRefreshingFriends else {
            return
        }

        isRefreshingFriends = true
        defer { isRefreshingFriends = false }

        do {
            let sessionKey = try sessionKey()
            let requests = try await XBLiveSocialService.fetchFriendRequests(sessionKey: sessionKey)
            let friendsResponse = try? await XBLiveSocialService.fetchMessageableFriends(sessionKey: sessionKey)
            let blocksResponse = try? await XBLiveSocialService.fetchBlocks(sessionKey: sessionKey)

            currentUsername = requests.user ?? friendsResponse?.user ?? blocksResponse?.user ?? currentUsername
            incomingRequests = requests.incoming
                .map { $0.withUsername($0.fromUsername ?? $0.username) }
                .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
            outgoingRequests = requests.outgoing
                .map { $0.withUsername($0.toUsername ?? $0.username) }
                .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
            if let friendsResponse {
                let friends = friendsResponse.friends.sorted(by: friendSort)
                messageableFriends = friends
                messageableFriendProfiles = await fetchMessageableFriendProfiles(
                    for: friends,
                    existingProfiles: messageableFriendProfiles
                )
                notifyForFriendsComingOnline(friends, profiles: messageableFriendProfiles)
            }
            if let blocksResponse {
                blockedUsers = blocksResponse.blocked.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
        } catch {
            handle(error, title: "Friends Not Synced")
        }
    }

    func messages(for username: String) -> [XBLiveSocialMessage] {
        threadMessagesByUser[username.socialNormalizedKey] ?? []
    }

    func inboxMessages(for username: String) -> [XBLiveSocialMessage] {
        inboxMessages
            .filter { $0.otherUser(relativeTo: currentUsername)?.socialNormalizedKey == username.socialNormalizedKey }
            .sorted(by: XBLiveSocialMessage.chronologicalSort)
    }

    func loadThread(with username: String) async {
        do {
            let sessionKey = try sessionKey()
            let response = try await XBLiveSocialService.fetchThread(sessionKey: sessionKey, with: username)
            currentUsername = response.user ?? currentUsername
            let threadUsername = response.with.nilIfBlank ?? username
            let messages = response.messages
                .map {
                    $0.resolvingParticipantNames(
                        currentUser: currentUsername,
                        threadUsername: threadUsername
                    )
                }
                .filter { isKnownThreadMessage($0, threadUsername: threadUsername) }
                .sorted(by: XBLiveSocialMessage.chronologicalSort)
            threadMessagesByUser[threadUsername.socialNormalizedKey] = messages
            if threadUsername.socialNormalizedKey != username.socialNormalizedKey {
                threadMessagesByUser[username.socialNormalizedKey] = messages
            }
            for message in messages {
                rememberThreadUsername(threadUsername, for: message)
                if message.isFromCurrentUser(currentUsername) {
                    messageIDsSentByCurrentUser.insert(message.id)
                }
            }
            let incomingMessages = messages.filter {
                !$0.isFromCurrentUser(currentUsername)
            }
            locallyReadMessageIDs.formUnion(incomingMessages.map(\.id))
            rememberObservedNotificationMessages(messages)
            saveMessageIdentityCache()

            let readIDs = incomingMessages.compactMap(\.numericID)
            for id in readIDs {
                _ = try? await XBLiveSocialService.markRead(sessionKey: sessionKey, id: id)
            }

            if !incomingMessages.isEmpty {
                await refreshMessages()
            }
        } catch {
            handle(error, title: "Thread Not Loaded")
        }
    }

    @discardableResult
    func sendMessage(to username: String, body: String) async -> Bool {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !trimmedBody.isEmpty else {
            notice = XBLiveSocialNotice(title: "Message Not Sent", detail: "Enter a recipient and message.")
            return false
        }
        guard trimmedBody.count <= 320 else {
            notice = XBLiveSocialNotice(title: "Message Not Sent", detail: "Messages are limited to 320 characters.")
            return false
        }

        do {
            let sessionKey = try sessionKey()
            let response = try await XBLiveSocialService.sendMessage(sessionKey: sessionKey, to: trimmedUser, body: trimmedBody)
            if let id = response.id {
                let messageID = "\(id)"
                messageThreadUsernamesByID[messageID] = trimmedUser
                messageIDsSentByCurrentUser.insert(messageID)
            }
            if let createdAt = response.createdAt,
               let signature = messageSignature(body: trimmedBody, createdAt: createdAt) {
                messageThreadUsernamesBySignature[signature] = trimmedUser
            }
            saveMessageIdentityCache()
            if response.filtered == true {
                notice = XBLiveSocialNotice(title: "Message Sent", detail: "XB.Live filtered part of the message before delivery.")
            }
            await loadThread(with: trimmedUser)
            await refreshMessages()
            return true
        } catch {
            handle(error, title: "Message Not Sent")
            return false
        }
    }

    func sendFriendRequest(to username: String) async {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else {
            notice = XBLiveSocialNotice(title: "Friend Request Not Sent", detail: "Enter a username.")
            return
        }

        do {
            let sessionKey = try sessionKey()
            let response = try await XBLiveSocialService.sendFriendRequest(sessionKey: sessionKey, to: trimmedUser)
            if response.accepted == true {
                notice = XBLiveSocialNotice(title: "Friend Added", detail: "\(trimmedUser) had already sent you a request.")
            }
            await refreshFriends()
        } catch {
            handle(error, title: "Friend Request Not Sent")
        }
    }

    func acceptFriendRequest(from username: String) async {
        await respondToFriendRequest(from: username, action: .accept, failureTitle: "Friend Request Not Accepted")
    }

    func declineFriendRequest(from username: String) async {
        await respondToFriendRequest(from: username, action: .decline, failureTitle: "Friend Request Not Declined")
    }

    func cancelFriendRequest(to username: String) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.cancelFriendRequest(sessionKey: sessionKey, to: username)
            await refreshFriends()
        } catch {
            handle(error, title: "Friend Request Not Canceled")
        }
    }

    func removeFriend(_ username: String) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.removeFriend(sessionKey: sessionKey, user: username)
            relationshipStatuses[username.socialNormalizedKey] = XBLiveFriendRelationshipStatus.none
            await refreshFriends()
        } catch {
            handle(error, title: "Friend Not Removed")
        }
    }

    func fetchStatus(for username: String) async {
        do {
            let sessionKey = try sessionKey()
            let response = try await XBLiveSocialService.fetchFriendStatus(sessionKey: sessionKey, user: username)
            relationshipStatuses[username.socialNormalizedKey] = response.status
            currentUsername = response.user ?? currentUsername
        } catch {
            handle(error, title: "Friend Status Not Loaded")
        }
    }

    func blockUser(_ username: String, reason: String? = nil) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.blockUser(sessionKey: sessionKey, user: username, reason: reason)
            notice = XBLiveSocialNotice(title: "User Blocked", detail: "\(username) can no longer message you.")
            await refreshFriends()
            await refreshMessages()
        } catch {
            handle(error, title: "User Not Blocked")
        }
    }

    func unblockUser(_ username: String) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.unblockUser(sessionKey: sessionKey, user: username)
            await refreshFriends()
        } catch {
            handle(error, title: "User Not Unblocked")
        }
    }

    func reportUser(_ username: String, reason: String?) async {
        await report(username, context: "user", messageId: nil, body: nil, reason: reason)
    }

    func reportMessage(_ message: XBLiveSocialMessage, reason: String?) async {
        await report(
            message.sender,
            context: "xbl_message",
            messageId: message.numericID,
            body: message.body,
            reason: reason
        )
    }

    private func respondToFriendRequest(
        from username: String,
        action: XBLiveSocialService.FriendRequestAction,
        failureTitle: String
    ) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.respondToFriendRequest(sessionKey: sessionKey, from: username, action: action)
            await refreshFriends()
        } catch {
            handle(error, title: failureTitle)
        }
    }

    private func report(
        _ username: String,
        context: String,
        messageId: Int?,
        body: String?,
        reason: String?
    ) async {
        do {
            let sessionKey = try sessionKey()
            _ = try await XBLiveSocialService.report(
                sessionKey: sessionKey,
                reported: username,
                context: context,
                messageId: messageId,
                body: body,
                source: "DukeX iOS",
                reason: reason
            )
            notice = XBLiveSocialNotice(title: "Report Sent", detail: "XB.Live moderation has received the report.")
        } catch {
            handle(error, title: "Report Not Sent")
        }
    }

    private func normalizedInboxMessage(
        _ message: XBLiveSocialMessage,
        conversations: [XBLiveSocialConversation]
    ) -> XBLiveSocialMessage {
        let threadUsername = message.otherUser(relativeTo: currentUsername) ??
            rememberedThreadUsername(for: message) ??
            rememberedThreadUsernameForSignature(of: message) ??
            inferredThreadUsername(for: message, conversations: conversations) ??
            message.sender
        let resolvedMessage = message.resolvingParticipantNames(
            currentUser: currentUsername,
            threadUsername: threadUsername
        )
        if messageIDsSentByCurrentUser.contains(message.id),
           let currentUsername = currentUsername?.nilIfBlank,
           let recipient = threadUsername.nilIfBlank {
            let sentMessage = XBLiveSocialMessage(
                id: resolvedMessage.id,
                sender: currentUsername,
                recipient: recipient,
                body: resolvedMessage.body,
                kind: resolvedMessage.kind,
                createdAt: resolvedMessage.createdAt,
                readAt: resolvedMessage.readAt,
                filtered: resolvedMessage.filtered
            )
            rememberThreadUsername(recipient, for: sentMessage)
            return applyingLocalReadState(to: sentMessage)
        }

        if let resolvedUsername = resolvedMessage.otherUser(relativeTo: currentUsername) {
            rememberThreadUsername(resolvedUsername, for: resolvedMessage)
        }
        return applyingLocalReadState(to: resolvedMessage)
    }

    private func applyingLocalReadState(to message: XBLiveSocialMessage) -> XBLiveSocialMessage {
        guard locallyReadMessageIDs.contains(message.id),
              !message.isRead else {
            return message
        }

        return XBLiveSocialMessage(
            id: message.id,
            sender: message.sender,
            recipient: message.recipient,
            body: message.body,
            kind: message.kind,
            createdAt: message.createdAt,
            readAt: "read",
            filtered: message.filtered
        )
    }

    private func inferredThreadUsername(
        for message: XBLiveSocialMessage,
        conversations: [XBLiveSocialConversation]
    ) -> String? {
        let scoredMatches = conversations.compactMap { conversation -> (username: String, score: Int)? in
            guard let username = conversation.username.nilIfBlank,
                  username.socialNormalizedKey != "unknown",
                  username.socialNormalizedKey != currentUsername?.socialNormalizedKey else {
                return nil
            }

            let score = conversationMatchScore(conversation, message: message)
            return score > 0 ? (username, score) : nil
        }

        return scoredMatches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
            }
            .first?
            .username
    }

    private func normalizedConversation(
        _ conversation: XBLiveSocialConversation,
        currentUser: String?,
        inboxMessages: [XBLiveSocialMessage]
    ) -> XBLiveSocialConversation {
        let normalized = conversation.normalized(currentUser: currentUser)
        let currentUserKey = currentUser?.socialNormalizedKey
        let needsUsername = normalized.username.nilIfBlank == nil ||
            normalized.username.socialNormalizedKey == "unknown" ||
            normalized.username.socialNormalizedKey == currentUserKey
        let resolvedConversation: XBLiveSocialConversation
        if needsUsername,
           let username = inferredConversationUsername(for: normalized, inboxMessages: inboxMessages) {
            resolvedConversation = normalized.replacingUsername(with: username)
        } else {
            resolvedConversation = normalized
        }

        return conversationWithLocallyComputedUnread(
            resolvedConversation,
            currentUser: currentUser,
            inboxMessages: inboxMessages
        )
    }

    private func conversationWithLocallyComputedUnread(
        _ conversation: XBLiveSocialConversation,
        currentUser: String?,
        inboxMessages: [XBLiveSocialMessage]
    ) -> XBLiveSocialConversation {
        let matchingMessages = inboxMessages.filter {
            $0.otherUser(relativeTo: currentUser)?.socialNormalizedKey == conversation.key
        }
        guard !matchingMessages.isEmpty else {
            return conversation
        }

        let unreadCount = matchingMessages.filter {
            !$0.isFromCurrentUser(currentUser) && !$0.isRead
        }.count
        return conversation.replacingUnreadCount(with: unreadCount)
    }

    private func isKnownConversation(_ conversation: XBLiveSocialConversation) -> Bool {
        let key = conversation.username.socialNormalizedKey
        return !key.isEmpty && key != "unknown"
    }

    private func isKnownMessage(_ message: XBLiveSocialMessage, currentUser: String?) -> Bool {
        if let otherUser = message.otherUser(relativeTo: currentUser)?.nilIfBlank {
            let key = otherUser.socialNormalizedKey
            return !key.isEmpty && key != "unknown"
        }

        if !message.isFromCurrentUser(currentUser) {
            let key = message.sender.socialNormalizedKey
            return !key.isEmpty && key != "unknown"
        }

        guard let recipient = message.recipient?.nilIfBlank else {
            return false
        }
        let key = recipient.socialNormalizedKey
        return !key.isEmpty && key != "unknown"
    }

    private func isKnownThreadMessage(_ message: XBLiveSocialMessage, threadUsername: String) -> Bool {
        let threadKey = threadUsername.socialNormalizedKey
        guard !threadKey.isEmpty, threadKey != "unknown" else {
            return false
        }

        let senderKey = message.sender.socialNormalizedKey
        guard !senderKey.isEmpty, senderKey != "unknown" else {
            return false
        }

        if message.isFromCurrentUser(currentUsername),
           let recipient = message.recipient?.nilIfBlank {
            let recipientKey = recipient.socialNormalizedKey
            return !recipientKey.isEmpty && recipientKey != "unknown"
        }

        return true
    }

    private func inferredConversationUsername(
        for conversation: XBLiveSocialConversation,
        inboxMessages: [XBLiveSocialMessage]
    ) -> String? {
        let scoredMatches = inboxMessages.compactMap { message -> (username: String, score: Int)? in
            guard let username = message.otherUser(relativeTo: currentUsername)?.nilIfBlank,
                  username.socialNormalizedKey != "unknown" else {
                return nil
            }

            let score = conversationMatchScore(conversation, message: message)
            return score > 0 ? (username, score) : nil
        }

        return scoredMatches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
            }
            .first?
            .username
    }

    private func conversationMatchScore(
        _ conversation: XBLiveSocialConversation,
        message: XBLiveSocialMessage
    ) -> Int {
        var score = 0
        if let latestBody = conversation.latestBody?.nilIfBlank,
           let messageBody = message.body.nilIfBlank,
           latestBody == messageBody {
            score += 3
        }

        if let conversationTimestamp = XBLiveSocialMessage.timestampValue(conversation.latestAt),
           let messageTimestamp = XBLiveSocialMessage.timestampValue(message.createdAt),
           abs(conversationTimestamp - messageTimestamp) < 1.0 {
            score += 3
        } else if conversation.latestAt?.nilIfBlank == message.createdAt?.nilIfBlank {
            score += 2
        }

        if let latestSender = conversation.latestSender?.nilIfBlank,
           latestSender.socialNormalizedKey == message.sender.socialNormalizedKey {
            score += 1
        }

        if let latestRecipient = conversation.latestRecipient?.nilIfBlank,
           let recipient = message.recipient?.nilIfBlank,
           latestRecipient.socialNormalizedKey == recipient.socialNormalizedKey {
            score += 1
        }

        return score
    }

    private func rememberThreadUsername(_ username: String, for message: XBLiveSocialMessage) {
        guard let username = username.nilIfBlank,
              username.socialNormalizedKey != "unknown" else {
            return
        }

        messageThreadUsernamesByID[message.id] = username
        if let signature = messageSignature(for: message) {
            messageThreadUsernamesBySignature[signature] = username
        }
    }

    private func rememberedThreadUsername(for message: XBLiveSocialMessage) -> String? {
        messageThreadUsernamesByID[message.id]?.nilIfBlank
    }

    private func rememberedThreadUsernameForSignature(of message: XBLiveSocialMessage) -> String? {
        guard let signature = messageSignature(for: message) else {
            return nil
        }

        return messageThreadUsernamesBySignature[signature]?.nilIfBlank
    }

    private func messageSignature(for message: XBLiveSocialMessage) -> String? {
        messageSignature(body: message.body, createdAt: message.createdAt)
    }

    private func messageSignature(body: String, createdAt: String?) -> String? {
        guard let body = body.nilIfBlank,
              let timestamp = XBLiveSocialMessage.timestampValue(createdAt) else {
            return nil
        }

        return "\(body.socialNormalizedKey)|\(Int(timestamp.rounded()))"
    }

    private func loadMessageIdentityCache() {
        messageThreadUsernamesByID =
            UserDefaults.standard.dictionary(forKey: Self.messageThreadUsernamesByIDKey) as? [String: String] ?? [:]
        messageThreadUsernamesBySignature =
            UserDefaults.standard.dictionary(forKey: Self.messageThreadUsernamesBySignatureKey) as? [String: String] ?? [:]
        messageIDsSentByCurrentUser =
            Set(UserDefaults.standard.stringArray(forKey: Self.sentMessageIDsKey) ?? [])
        locallyReadMessageIDs =
            Set(UserDefaults.standard.stringArray(forKey: Self.locallyReadMessageIDsKey) ?? [])
        observedNotificationMessageKeys =
            Set(UserDefaults.standard.stringArray(forKey: Self.observedNotificationMessageKeysKey) ?? [])
    }

    private func saveMessageIdentityCache() {
        UserDefaults.standard.set(messageThreadUsernamesByID, forKey: Self.messageThreadUsernamesByIDKey)
        UserDefaults.standard.set(messageThreadUsernamesBySignature, forKey: Self.messageThreadUsernamesBySignatureKey)
        UserDefaults.standard.set(Array(messageIDsSentByCurrentUser).sorted(), forKey: Self.sentMessageIDsKey)
        UserDefaults.standard.set(Array(locallyReadMessageIDs).sorted(), forKey: Self.locallyReadMessageIDsKey)
        UserDefaults.standard.set(Array(observedNotificationMessageKeys).sorted(), forKey: Self.observedNotificationMessageKeysKey)
    }

    private func notifyForNewIncomingMessages(_ messages: [XBLiveSocialMessage]) {
        let incomingMessages = messages.filter { !$0.isFromCurrentUser(currentUsername) }
        let currentKeys = Set(incomingMessages.map { notificationKey(for: $0) })

        guard hasLoadedNotificationMessageBaseline else {
            observedNotificationMessageKeys.formUnion(currentKeys)
            trimObservedNotificationMessageKeys()
            hasLoadedNotificationMessageBaseline = true
            saveMessageIdentityCache()
            return
        }

        let newMessages = incomingMessages.filter {
            !observedNotificationMessageKeys.contains(notificationKey(for: $0))
        }
        guard !newMessages.isEmpty else {
            observedNotificationMessageKeys.formUnion(currentKeys)
            trimObservedNotificationMessageKeys()
            saveMessageIdentityCache()
            return
        }

        observedNotificationMessageKeys.formUnion(currentKeys)
        trimObservedNotificationMessageKeys()
        saveMessageIdentityCache()

        for message in newMessages.sorted(by: XBLiveSocialMessage.chronologicalSort) {
            scheduleNotification(forIncomingMessage: message)
        }
    }

    private func rememberObservedNotificationMessages(_ messages: [XBLiveSocialMessage]) {
        let incomingKeys = messages
            .filter { !$0.isFromCurrentUser(currentUsername) }
            .map { notificationKey(for: $0) }
        observedNotificationMessageKeys.formUnion(incomingKeys)
        trimObservedNotificationMessageKeys()
    }

    private func notifyForFriendsComingOnline(
        _ friends: [XBLiveSocialFriend],
        profiles: [String: XBLiveFriendProfile]
    ) {
        let currentStates = Dictionary(uniqueKeysWithValues: friends.map { friend in
            (friend.key, isFriendOnline(friend, profile: profiles[friend.key]))
        })

        guard hasLoadedOnlineNotificationBaseline else {
            lastOnlineNotificationStates = currentStates
            hasLoadedOnlineNotificationBaseline = true
            return
        }

        for friend in friends where currentStates[friend.key] == true && lastOnlineNotificationStates[friend.key] == false {
            scheduleNotification(forOnlineFriend: friend, profile: profiles[friend.key])
        }
        lastOnlineNotificationStates = currentStates
    }

    private func scheduleNotification(forIncomingMessage message: XBLiveSocialMessage) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        let sender = message.otherUser(relativeTo: currentUsername) ?? message.sender
        guard !isActivelyReadingThread(with: sender) else {
            return
        }

        let senderName = displayName(for: sender)
        if let invite = XBLiveSocialNotificationGameInvite(messageBody: message.body) {
            let gameTitle = resolvedNotificationGameTitle(
                titleID: invite.titleID,
                embeddedTitle: invite.title
            )
            let iconURL = Self.mobCatIconURL(for: invite.titleID)
            let localImageURL = notificationGameLocalCoverURL?(invite.titleID)
            Task {
                await XBLiveSocialLocalNotificationPresenter.shared.schedule(
                    identifier: "xblive-invite-\(notificationKey(for: message))",
                    title: "\(senderName) invited you",
                    body: "Play \(gameTitle)",
                    threadIdentifier: "xblive.thread.\(sender.socialNormalizedKey)",
                    customImage: nil,
                    remoteImageURL: iconURL,
                    localImageURL: localImageURL
                )
            }
            return
        }

        let avatarImage = notificationCustomAvatarImage?(sender)
        let remoteAvatarURL = avatarURL(for: sender)
        Task {
            await XBLiveSocialLocalNotificationPresenter.shared.schedule(
                identifier: "xblive-message-\(notificationKey(for: message))",
                title: senderName,
                body: message.body.nilIfBlank ?? "New message",
                threadIdentifier: "xblive.thread.\(sender.socialNormalizedKey)",
                customImage: avatarImage,
                remoteImageURL: remoteAvatarURL,
                localImageURL: nil
            )
        }
    }

    private func scheduleNotification(
        forOnlineFriend friend: XBLiveSocialFriend,
        profile: XBLiveFriendProfile?
    ) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        let displayName = profile?.gamertag.nilIfBlank ?? friend.title
        let currentGame = profile?.currentGame?.nilIfBlank ?? friend.currentGame?.nilIfBlank
        let avatarImage = notificationCustomAvatarImage?(displayName) ?? notificationCustomAvatarImage?(friend.username)
        let remoteAvatarURL = profile?.avatarURL ?? friend.avatarURL
        Task {
            await XBLiveSocialLocalNotificationPresenter.shared.schedule(
                identifier: "xblive-online-\(friend.key)-\(Int(Date().timeIntervalSince1970))",
                title: "\(displayName) is online",
                body: currentGame.map { "Playing \($0)" } ?? "Online now",
                threadIdentifier: "xblive.online",
                customImage: avatarImage,
                remoteImageURL: remoteAvatarURL,
                localImageURL: nil
            )
        }
    }

    private func notificationKey(for message: XBLiveSocialMessage) -> String {
        let currentUserKey = currentUsername?.socialNormalizedKey ?? "unknown"
        let stableMessageKey = messageSignature(for: message) ?? message.id
        return "\(currentUserKey)|\(stableMessageKey)"
    }

    private func trimObservedNotificationMessageKeys() {
        guard observedNotificationMessageKeys.count > Self.maxObservedNotificationMessageKeys else {
            return
        }

        observedNotificationMessageKeys = Set(
            observedNotificationMessageKeys
                .sorted()
                .suffix(Self.maxObservedNotificationMessageKeys)
        )
    }

    private func isFriendOnline(_ friend: XBLiveSocialFriend, profile: XBLiveFriendProfile?) -> Bool {
        profile?.isOnline == true ||
            profile?.currentGame?.nilIfBlank != nil ||
            friend.isOnline == true ||
            friend.currentGame?.nilIfBlank != nil
    }

    private func displayName(for username: String) -> String {
        let key = username.socialNormalizedKey
        if let friend = messageableFriends.first(where: { $0.key == key || $0.title.socialNormalizedKey == key }) {
            return friend.title
        }
        if let profile = messageableFriendProfiles[key] ??
            messageableFriendProfiles.values.first(where: { $0.gamertag.socialNormalizedKey == key }) {
            return profile.gamertag
        }
        return username
    }

    private func avatarURL(for username: String) -> URL? {
        let key = username.socialNormalizedKey
        let friend = messageableFriends.first { $0.key == key || $0.title.socialNormalizedKey == key }
        let profile = messageableFriendProfiles[key] ??
            messageableFriendProfiles.values.first { $0.gamertag.socialNormalizedKey == key }
        return profile?.avatarURL ?? friend?.avatarURL
    }

    private func resolvedNotificationGameTitle(titleID: String, embeddedTitle: String?) -> String {
        notificationGameTitle?(titleID, embeddedTitle) ??
            embeddedTitle?.nilIfBlank ??
            "Title \(titleID)"
    }

    private func isActivelyReadingThread(with username: String) -> Bool {
        activeThreadKey == username.socialNormalizedKey
    }

    private static func mobCatIconURL(for titleID: String) -> URL? {
        guard let normalizedTitleID = GameLaunchLink.normalizedTitleID(titleID),
              normalizedTitleID.count >= 4 else {
            return nil
        }

        let prefix = String(normalizedTitleID.prefix(4))
        return URL(string: "https://raw.githubusercontent.com/MobCat/MobCats-original-xbox-game-list/main/icon/\(prefix)/\(normalizedTitleID).png")
    }

    private func fetchMessageableFriendProfiles(
        for friends: [XBLiveSocialFriend],
        existingProfiles: [String: XBLiveFriendProfile]
    ) async -> [String: XBLiveFriendProfile] {
        let currentKeys = Set(friends.map(\.key))
        var profiles = existingProfiles.filter { currentKeys.contains($0.key) }

        await withTaskGroup(of: (String, XBLiveFriendProfile)?.self) { group in
            for friend in friends {
                group.addTask {
                    guard let xbProfile = try? await XBLiveService.fetchProfile(username: friend.username) else {
                        return nil
                    }

                    let existingProfile = existingProfiles[friend.key]
                    let games = (try? await XBLiveService.fetchGamesPlayed(username: friend.username)) ??
                        existingProfile?.gamesPlayed ??
                        []
                    let lastGame = games.first { $0.gameName == xbProfile.lastPlayedGame } ?? games.first
                    let isOnline = xbProfile.isOnline || friend.isOnline == true || friend.currentGame?.nilIfBlank != nil
                    let totalMinutes = xbProfile.totalMinutes ?? Self.totalMinutes(from: games)
                    let lastOnlineAt = Self.lastOnlineTimestamp(
                        isOnline: isOnline,
                        profile: xbProfile,
                        friend: friend
                    )
                    let profile = XBLiveFriendProfile(
                        gamertag: friend.title,
                        avatarURLString: xbProfile.avatarURLString ?? friend.avatarURLString,
                        isOnline: isOnline,
                        lastState: xbProfile.lastState ?? friend.status,
                        currentGame: xbProfile.currentGame ?? (isOnline ? friend.currentGame : nil),
                        lastPlayedGame: xbProfile.lastPlayedGame ?? lastGame?.gameName,
                        lastPlayedAt: xbProfile.lastPlayedAt,
                        lastOnlineAt: lastOnlineAt,
                        lastCheckedAt: xbProfile.lastCheckedAt,
                        achievementScore: xbProfile.achievementScore,
                        achievementCount: xbProfile.achievementCount,
                        totalMinutes: totalMinutes,
                        lastPlayedImageURLString: lastGame?.imageUrl,
                        gamesPlayed: games,
                        achievements: existingProfile?.achievements
                    )
                    return (friend.key, profile)
                }
            }

            for await result in group {
                guard let result else {
                    continue
                }
                profiles[result.0] = result.1
            }
        }

        return profiles
    }

    nonisolated private static func lastOnlineTimestamp(
        isOnline: Bool,
        profile: XBLiveProfileSnapshot,
        friend: XBLiveSocialFriend
    ) -> Double? {
        if isOnline {
            return profile.lastCheckedAt ?? profile.lastOnlineAt ?? friend.lastOnlineAt ?? Date().timeIntervalSince1970
        }
        return profile.lastOnlineAt ?? profile.lastPlayedAt ?? friend.lastOnlineAt
    }

    nonisolated private static func totalMinutes(from games: [XBLiveGamePlayed]) -> Double? {
        let values = games.compactMap(\.totalMinutes)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private func sessionKey() throws -> String {
        guard let sessionKey = try InsigniaProfileStore.storedSessionKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionKey.isEmpty else {
            throw XBLiveSocialServiceError.missingSession
        }

        return sessionKey
    }

    private func handle(_ error: Error, title: String) {
        if let socialError = error as? XBLiveSocialServiceError,
           socialError == .unauthorized {
            clear()
        }

        notice = XBLiveSocialNotice(
            title: title,
            detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }

    private func conversationSort(_ lhs: XBLiveSocialConversation, _ rhs: XBLiveSocialConversation) -> Bool {
        if lhs.unreadCount != rhs.unreadCount {
            return lhs.unreadCount > rhs.unreadCount
        }

        if XBLiveSocialMessage.timestampValue(lhs.latestAt) != XBLiveSocialMessage.timestampValue(rhs.latestAt) {
            return (XBLiveSocialMessage.timestampValue(lhs.latestAt) ?? -Double.greatestFiniteMagnitude) >
                (XBLiveSocialMessage.timestampValue(rhs.latestAt) ?? -Double.greatestFiniteMagnitude)
        }

        return lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
    }

    private func friendSort(_ lhs: XBLiveSocialFriend, _ rhs: XBLiveSocialFriend) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private struct XBLiveSocialNotificationGameInvite {
    let titleID: String
    let title: String?

    init?(messageBody: String) {
        let trimmedBody = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.launchURLCandidate(in: trimmedBody)
        guard let url = URL(string: candidate),
              let titleID = GameLaunchLink.titleID(from: url) else {
            return nil
        }

        self.titleID = titleID
        title = GameLaunchLink.titleName(from: url)
    }

    private static func launchURLCandidate(in body: String) -> String {
        if body.lowercased().hasPrefix("\(GameLaunchLink.scheme)://") {
            return body
        }

        return body
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { $0.lowercased().hasPrefix("\(GameLaunchLink.scheme)://") } ?? body
    }
}

private final class XBLiveSocialLocalNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = XBLiveSocialLocalNotificationPresenter()

    private let notificationCenter = UNUserNotificationCenter.current()
    private var hasActivatedForegroundPresentation = false

    func activateForegroundPresentation() {
        guard !hasActivatedForegroundPresentation else {
            return
        }

        hasActivatedForegroundPresentation = true
        notificationCenter.delegate = self
    }

    func schedule(
        identifier: String,
        title: String,
        body: String,
        threadIdentifier: String,
        customImage: UIImage?,
        remoteImageURL: URL?,
        localImageURL: URL?
    ) async {
        activateForegroundPresentation()
        guard await notificationPermissionGranted() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        if let attachment = await attachment(
            customImage: customImage,
            remoteImageURL: remoteImageURL,
            localImageURL: localImageURL
        ) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: sanitizedIdentifier(identifier),
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func notificationPermissionGranted() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func attachment(
        customImage: UIImage?,
        remoteImageURL: URL?,
        localImageURL: URL?
    ) async -> UNNotificationAttachment? {
        if let customImage,
           let data = customImage.jpegData(compressionQuality: 0.9),
           let url = writeAttachmentData(data, preferredExtension: "jpg") {
            return try? UNNotificationAttachment(identifier: "image", url: url)
        }

        if let localImageURL,
           FileManager.default.fileExists(atPath: localImageURL.path),
           let attachment = try? UNNotificationAttachment(identifier: "image", url: localImageURL) {
            return attachment
        }

        guard let remoteImageURL,
              let (data, response) = try? await URLSession.shared.data(from: remoteImageURL),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) != false,
              let url = writeAttachmentData(data, preferredExtension: imageExtension(for: remoteImageURL)) else {
            return nil
        }

        return try? UNNotificationAttachment(identifier: "image", url: url)
    }

    private func writeAttachmentData(_ data: Data, preferredExtension: String) -> URL? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XBLiveNotificationAttachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = "\(UUID().uuidString).\(preferredExtension)"
            let url = directory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func imageExtension(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "jpg", "jpeg", "png", "gif":
            return pathExtension
        default:
            return "png"
        }
    }

    private func sanitizedIdentifier(_ identifier: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return identifier.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
    }
}

private struct SocialFlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == SocialFlexibleCodingKey {
    func flexibleString(for keys: [String]) -> String? {
        for keyName in keys {
            guard let key = SocialFlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let string = try? decode(String.self, forKey: key) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let int = try? decode(Int.self, forKey: key) {
                return "\(int)"
            }

            if let double = try? decode(Double.self, forKey: key) {
                return "\(double)"
            }

            if let bool = try? decode(Bool.self, forKey: key) {
                return bool ? "true" : "false"
            }
        }

        return nil
    }

    func flexibleInt(for keys: [String]) -> Int? {
        for keyName in keys {
            guard let key = SocialFlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let int = try? decode(Int.self, forKey: key) {
                return int
            }

            if let double = try? decode(Double.self, forKey: key) {
                return Int(double)
            }

            if let string = try? decode(String.self, forKey: key),
               let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return int
            }

            if let bool = try? decode(Bool.self, forKey: key) {
                return bool ? 1 : 0
            }
        }

        return nil
    }

    func flexibleDouble(for keys: [String]) -> Double? {
        for keyName in keys {
            guard let key = SocialFlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let double = try? decode(Double.self, forKey: key) {
                return double
            }

            if let int = try? decode(Int.self, forKey: key) {
                return Double(int)
            }

            if let string = try? decode(String.self, forKey: key),
               let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return double
            }
        }

        return nil
    }

    func flexibleBool(for keys: [String]) -> Bool? {
        for keyName in keys {
            guard let key = SocialFlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let bool = try? decode(Bool.self, forKey: key) {
                return bool
            }

            if let int = try? decode(Int.self, forKey: key) {
                return int != 0
            }

            if let string = try? decode(String.self, forKey: key) {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "1", "true", "yes", "online", "active":
                    return true
                case "0", "false", "no", "offline", "inactive":
                    return false
                default:
                    break
                }
            }
        }

        return nil
    }

    func flexibleDecode<T: Decodable>(_ type: T.Type, for keys: [String]) -> T? {
        for keyName in keys {
            guard let key = SocialFlexibleCodingKey(stringValue: keyName),
                  let value = try? decode(T.self, forKey: key) else {
                continue
            }
            return value
        }

        return nil
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var socialNormalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
