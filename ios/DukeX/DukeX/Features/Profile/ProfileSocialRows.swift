import SwiftUI
import UIKit

struct ProfileSocialMessagesView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    let legacyMessages: [InsigniaMessage]
    let legacyUnreadMessages: [InsigniaMessage]
    let friendProfileImages: [String: UIImage]
    let friendProfiles: [String: XBLiveFriendProfile]
    let socialFriends: [XBLiveSocialFriend]
    let markLegacyMessageViewed: (InsigniaMessage) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let currentUserAchievements: XBLiveAchievementsSnapshot?
    let launchGameFromInvite: (LibraryFile) -> Void

    @State private var isComposePresented = false

    var body: some View {
        List {
            Section("Conversations") {
                if conversations.isEmpty {
                    if socialStore.isRefreshingMessages {
                        ProfileSocialLoadingRow(title: "Loading messages...")
                    } else {
                        ProfileEmptyRow(title: "No conversations", systemImage: "envelope")
                    }
                } else {
                    ForEach(conversations) { conversation in
                        NavigationLink {
                            ProfileSocialThreadView(
                                socialStore: socialStore,
                                username: conversation.username,
                                legacyMessages: legacyMessages,
                                friendProfileImages: friendProfileImages,
                                friendProfiles: friendProfiles,
                                socialFriends: socialFriends,
                                markLegacyMessageViewed: markLegacyMessageViewed,
                                installedGames: installedGames,
                                inviteEligibleGames: inviteEligibleGames,
                                currentUserAchievements: currentUserAchievements,
                                launchGameFromInvite: launchGameFromInvite
                            )
                        } label: {
                            ProfileSocialConversationRow(
                                conversation: conversation,
                                avatar: avatarResolver.avatar(
                                    for: conversation.username,
                                    fallbackURL: conversation.avatarURL
                                )
                            )
                        }
                    }
                }
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isComposePresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Compose Message")
            }
        }
        .task {
            await socialStore.refreshMessages()
        }
        .refreshable {
            await socialStore.refreshMessages()
        }
        .sheet(isPresented: $isComposePresented) {
            NavigationStack {
                ProfileSocialComposeView(
                    socialStore: socialStore,
                    initialRecipient: nil
                )
            }
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var conversations: [XBLiveSocialConversation] {
        ProfileSocialConversationMerge.merged(
            socialConversations: socialStore.conversations,
            inboxMessages: socialStore.inboxMessages,
            threadMessagesByUser: socialStore.threadMessagesByUser,
            currentUsername: socialStore.currentUsername,
            legacyMessages: legacyMessages,
            legacyUnreadMessages: legacyUnreadMessages
        )
    }

    private var avatarResolver: ProfileSocialAvatarResolver {
        ProfileSocialAvatarResolver(
            customImages: friendProfileImages,
            friendProfiles: mergedFriendProfiles,
            socialFriends: socialFriends
        )
    }

    private var mergedFriendProfiles: [String: XBLiveFriendProfile] {
        friendProfiles.merging(socialStore.messageableFriendProfiles) { existing, _ in existing }
    }
}

private struct ProfileSocialAvatarData {
    let image: UIImage?
    let url: URL?
    let initial: String
}

private struct ProfileSocialAvatarResolver {
    let customImages: [String: UIImage]
    let friendProfiles: [String: XBLiveFriendProfile]
    let socialFriends: [XBLiveSocialFriend]

    func avatar(for username: String, fallbackURL: URL? = nil) -> ProfileSocialAvatarData {
        let key = username.socialNormalizedKey
        let socialFriend = socialFriends.first {
            $0.key == key || $0.title.socialNormalizedKey == key
        }
        let friendProfile = friendProfiles[key] ??
            friendProfiles.values.first { $0.gamertag.socialNormalizedKey == key }
        let customImage = customImages[key] ??
            friendProfile.flatMap { customImages[$0.gamertag.socialNormalizedKey] } ??
            socialFriend.flatMap { customImages[$0.key] }
        let displayName = socialFriend?.title ?? friendProfile?.gamertag ?? username

        return ProfileSocialAvatarData(
            image: customImage,
            url: friendProfile?.avatarURL ?? socialFriend?.avatarURL ?? fallbackURL,
            initial: initial(for: displayName)
        )
    }

    private func initial(for username: String) -> String {
        String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct ProfileSocialConversationRow: View {
    let conversation: XBLiveSocialConversation
    let avatar: ProfileSocialAvatarData

    var body: some View {
        HStack(spacing: 12) {
            ProfileSocialAvatar(image: avatar.image, url: avatar.url, initial: avatar.initial)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.username)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .accessibilityLabel("\(conversation.unreadCount) unread messages")
                    }
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let latestAt = ProfileSocialTimestamp.displayText(conversation.latestAt) {
                Text(latestAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 54)
    }

    private var detail: String {
        if let body = conversation.latestBody,
           let invite = ProfileSocialGameInvite(messageBody: body) {
            return "Game invite: \(invite.title.trimmedNonEmpty ?? invite.titleID)"
        }
        return conversation.latestBody?.trimmedNonEmpty ?? "No preview available"
    }
}

private enum ProfileSocialConversationMerge {
    static func merged(
        socialConversations: [XBLiveSocialConversation],
        inboxMessages: [XBLiveSocialMessage],
        threadMessagesByUser: [String: [XBLiveSocialMessage]],
        currentUsername: String?,
        legacyMessages: [InsigniaMessage],
        legacyUnreadMessages: [InsigniaMessage]
    ) -> [XBLiveSocialConversation] {
        var conversationsByUser: [String: XBLiveSocialConversation] = [:]
        for conversation in socialConversations {
            let resolvedConversation = resolvedSocialConversation(
                conversation,
                inboxMessages: inboxMessages,
                threadMessagesByUser: threadMessagesByUser,
                currentUsername: currentUsername
            )
            if let existingConversation = conversationsByUser[resolvedConversation.key] {
                conversationsByUser[resolvedConversation.key] = mergedSocialConversation(
                    existingConversation,
                    resolvedConversation
                )
            } else {
                conversationsByUser[resolvedConversation.key] = resolvedConversation
            }
        }

        mergeInboxMessages(
            inboxMessages,
            currentUsername: currentUsername,
            into: &conversationsByUser
        )
        mergeThreadMessages(
            threadMessagesByUser,
            currentUsername: currentUsername,
            into: &conversationsByUser
        )

        let legacyMessagesBySender = Dictionary(grouping: legacyMessages) { $0.sender.socialNormalizedKey }
            .filter { !$0.key.isEmpty && $0.key != "unknown" }
        let legacyUnreadCounts = Dictionary(grouping: legacyUnreadMessages) { $0.sender.socialNormalizedKey }
            .mapValues(\.count)

        for (senderKey, messages) in legacyMessagesBySender {
            guard let latestMessage = messages.sorted(by: legacyMessageSortAscending).last else {
                continue
            }

            let unreadCount = legacyUnreadCounts[senderKey] ?? 0
            if let existingConversation = conversationsByUser[senderKey] {
                conversationsByUser[senderKey] = mergedConversation(
                    existingConversation,
                    latestLegacyMessage: latestMessage,
                    legacyCount: messages.count,
                    legacyUnreadCount: unreadCount
                )
            } else {
                conversationsByUser[senderKey] = XBLiveSocialConversation(
                    username: latestMessage.sender.trimmedNonEmpty ?? "Unknown",
                    latestBody: legacyBody(for: latestMessage),
                    latestSender: latestMessage.sender,
                    latestRecipient: nil,
                    latestAt: legacyCreatedAt(for: latestMessage),
                    unreadCount: unreadCount,
                    messageCount: messages.count,
                    avatarURLString: nil
                )
            }
        }

        return conversationsByUser.values
            .filter(isKnownConversation)
            .sorted(by: conversationSort)
    }

    private static func resolvedSocialConversation(
        _ conversation: XBLiveSocialConversation,
        inboxMessages: [XBLiveSocialMessage],
        threadMessagesByUser: [String: [XBLiveSocialMessage]],
        currentUsername: String?
    ) -> XBLiveSocialConversation {
        let currentUserKey = currentUsername?.socialNormalizedKey
        let needsUsername = conversation.username.trimmedNonEmpty == nil ||
            conversation.username.socialNormalizedKey == "unknown" ||
            conversation.username.socialNormalizedKey == currentUserKey
        guard needsUsername,
              let username = inferredConversationUsername(
                for: conversation,
                inboxMessages: inboxMessages,
                threadMessagesByUser: threadMessagesByUser,
                currentUsername: currentUsername
              ) else {
            return conversation
        }

        return conversation.replacingUsername(with: username)
    }

    private static func inferredConversationUsername(
        for conversation: XBLiveSocialConversation,
        inboxMessages: [XBLiveSocialMessage],
        threadMessagesByUser: [String: [XBLiveSocialMessage]],
        currentUsername: String?
    ) -> String? {
        let threadMessages = threadMessagesByUser.values.flatMap { $0 }
        let candidateMessages = inboxMessages + threadMessages
        let scoredMatches = candidateMessages.compactMap { message -> (username: String, score: Int)? in
            guard let username = message.otherUser(relativeTo: currentUsername)?.trimmedNonEmpty,
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

    private static func conversationMatchScore(
        _ conversation: XBLiveSocialConversation,
        message: XBLiveSocialMessage
    ) -> Int {
        var score = 0
        if let latestBody = conversation.latestBody?.trimmedNonEmpty,
           let messageBody = message.body.trimmedNonEmpty,
           latestBody == messageBody {
            score += 3
        }

        if let conversationTimestamp = ProfileSocialTimestamp.value(conversation.latestAt),
           let messageTimestamp = ProfileSocialTimestamp.value(message.createdAt),
           abs(conversationTimestamp - messageTimestamp) < 1.0 {
            score += 3
        } else if conversation.latestAt?.trimmedNonEmpty == message.createdAt?.trimmedNonEmpty {
            score += 2
        }

        return score
    }

    private static func mergedSocialConversation(
        _ lhs: XBLiveSocialConversation,
        _ rhs: XBLiveSocialConversation
    ) -> XBLiveSocialConversation {
        let rhsIsLatest = ProfileSocialTimestamp.isLater(rhs.latestAt, than: lhs.latestAt)
        let username = lhs.username.socialNormalizedKey == "unknown" ? rhs.username : lhs.username

        return XBLiveSocialConversation(
            username: username,
            latestBody: rhsIsLatest ? rhs.latestBody : lhs.latestBody,
            latestSender: rhsIsLatest ? rhs.latestSender : lhs.latestSender,
            latestRecipient: rhsIsLatest ? rhs.latestRecipient : lhs.latestRecipient,
            latestAt: rhsIsLatest ? rhs.latestAt : lhs.latestAt,
            unreadCount: max(lhs.unreadCount, rhs.unreadCount),
            messageCount: max(lhs.messageCount ?? 0, rhs.messageCount ?? 0),
            avatarURLString: lhs.avatarURLString ?? rhs.avatarURLString
        )
    }

    private static func mergeInboxMessages(
        _ messages: [XBLiveSocialMessage],
        currentUsername: String?,
        into conversationsByUser: inout [String: XBLiveSocialConversation]
    ) {
        let messagesByUser = Dictionary(grouping: messages) { message in
            message.otherUser(relativeTo: currentUsername)?.socialNormalizedKey ?? ""
        }
        .filter { !$0.key.isEmpty }
        .filter { $0.key != "unknown" }

        for (userKey, messages) in messagesByUser {
            let sortedMessages = messages.sorted(by: XBLiveSocialMessage.chronologicalSort)
            guard let latestMessage = sortedMessages.last,
                  let username = latestMessage.otherUser(relativeTo: currentUsername)?.trimmedNonEmpty ??
                    sortedMessages.compactMap({ $0.otherUser(relativeTo: currentUsername)?.trimmedNonEmpty }).first else {
                continue
            }

            let unreadCount = sortedMessages.filter {
                !$0.isFromCurrentUser(currentUsername) && !$0.isRead
            }.count

            if let existingConversation = conversationsByUser[userKey] {
                conversationsByUser[userKey] = mergedInboxConversation(
                    existingConversation,
                    latestMessage: latestMessage,
                    messageCount: sortedMessages.count,
                    unreadCount: unreadCount,
                    username: username
                )
            } else {
                conversationsByUser[userKey] = XBLiveSocialConversation(
                    username: username,
                    latestBody: latestMessage.body,
                    latestSender: latestMessage.sender,
                    latestRecipient: latestMessage.recipient,
                    latestAt: latestMessage.createdAt,
                    unreadCount: unreadCount,
                    messageCount: sortedMessages.count,
                    avatarURLString: nil
                )
            }
        }
    }

    private static func mergedInboxConversation(
        _ conversation: XBLiveSocialConversation,
        latestMessage: XBLiveSocialMessage,
        messageCount: Int,
        unreadCount: Int,
        username: String
    ) -> XBLiveSocialConversation {
        let inboxIsLatest = ProfileSocialTimestamp.isLater(
            latestMessage.createdAt,
            than: conversation.latestAt
        )

        return XBLiveSocialConversation(
            username: conversation.username.trimmedNonEmpty ?? username,
            latestBody: inboxIsLatest ? latestMessage.body : conversation.latestBody,
            latestSender: inboxIsLatest ? latestMessage.sender : conversation.latestSender,
            latestRecipient: inboxIsLatest ? latestMessage.recipient : conversation.latestRecipient,
            latestAt: inboxIsLatest ? latestMessage.createdAt : conversation.latestAt,
            unreadCount: unreadCount,
            messageCount: max(conversation.messageCount ?? 0, messageCount),
            avatarURLString: conversation.avatarURLString
        )
    }

    private static func mergeThreadMessages(
        _ threadMessagesByUser: [String: [XBLiveSocialMessage]],
        currentUsername: String?,
        into conversationsByUser: inout [String: XBLiveSocialConversation]
    ) {
        var messagesByUser: [String: [String: XBLiveSocialMessage]] = [:]
        var usernamesByUser: [String: String] = [:]

        for (threadKey, messages) in threadMessagesByUser {
            for message in messages {
                let username = message.otherUser(relativeTo: currentUsername)?.trimmedNonEmpty ??
                    conversationsByUser[threadKey]?.username.trimmedNonEmpty ??
                    normalizedThreadUsername(threadKey)
                guard let username,
                      username.socialNormalizedKey != "unknown" else {
                    continue
                }

                let userKey = username.socialNormalizedKey
                messagesByUser[userKey, default: [:]][message.id] = message
                if let existingUsername = conversationsByUser[userKey]?.username.trimmedNonEmpty,
                   existingUsername.socialNormalizedKey != "unknown" {
                    usernamesByUser[userKey] = existingUsername
                } else if usernamesByUser[userKey] == nil || usernamesByUser[userKey] == userKey {
                    usernamesByUser[userKey] = username
                }
            }
        }

        for (userKey, messagesByID) in messagesByUser {
            let sortedMessages = Array(messagesByID.values).sorted(by: XBLiveSocialMessage.chronologicalSort)
            guard let latestMessage = sortedMessages.last else {
                continue
            }

            let username = usernamesByUser[userKey] ??
                latestMessage.otherUser(relativeTo: currentUsername)?.trimmedNonEmpty ??
                normalizedThreadUsername(userKey) ??
                "Unknown"

            if let existingConversation = conversationsByUser[userKey] {
                conversationsByUser[userKey] = mergedThreadConversation(
                    existingConversation,
                    latestMessage: latestMessage,
                    messageCount: sortedMessages.count,
                    username: username
                )
            } else {
                conversationsByUser[userKey] = XBLiveSocialConversation(
                    username: username,
                    latestBody: latestMessage.body,
                    latestSender: latestMessage.sender,
                    latestRecipient: latestMessage.recipient,
                    latestAt: latestMessage.createdAt,
                    unreadCount: 0,
                    messageCount: sortedMessages.count,
                    avatarURLString: nil
                )
            }
        }
    }

    private static func mergedThreadConversation(
        _ conversation: XBLiveSocialConversation,
        latestMessage: XBLiveSocialMessage,
        messageCount: Int,
        username: String
    ) -> XBLiveSocialConversation {
        let threadIsLatest = shouldUseThreadLatest(latestMessage, over: conversation)

        return XBLiveSocialConversation(
            username: conversation.username.trimmedNonEmpty ?? username,
            latestBody: threadIsLatest ? latestMessage.body : conversation.latestBody,
            latestSender: threadIsLatest ? latestMessage.sender : conversation.latestSender,
            latestRecipient: threadIsLatest ? latestMessage.recipient : conversation.latestRecipient,
            latestAt: threadIsLatest ? latestMessage.createdAt : conversation.latestAt,
            unreadCount: conversation.unreadCount,
            messageCount: max(conversation.messageCount ?? 0, messageCount),
            avatarURLString: conversation.avatarURLString
        )
    }

    private static func shouldUseThreadLatest(
        _ message: XBLiveSocialMessage,
        over conversation: XBLiveSocialConversation
    ) -> Bool {
        let messageTimestamp = ProfileSocialTimestamp.value(message.createdAt)
        let conversationTimestamp = ProfileSocialTimestamp.value(conversation.latestAt)
        if let messageTimestamp,
           let conversationTimestamp {
            return messageTimestamp >= conversationTimestamp
        }

        if messageTimestamp != nil {
            return true
        }

        return conversation.latestAt?.trimmedNonEmpty == nil
    }

    private static func normalizedThreadUsername(_ value: String) -> String? {
        let trimmedValue = value.trimmedNonEmpty
        guard trimmedValue?.socialNormalizedKey != "unknown" else {
            return nil
        }
        return trimmedValue
    }

    private static func mergedConversation(
        _ conversation: XBLiveSocialConversation,
        latestLegacyMessage: InsigniaMessage,
        legacyCount: Int,
        legacyUnreadCount: Int
    ) -> XBLiveSocialConversation {
        let legacyTimestamp = legacyCreatedAt(for: latestLegacyMessage)
        let legacyIsLatest = ProfileSocialTimestamp.isLater(legacyTimestamp, than: conversation.latestAt)

        return XBLiveSocialConversation(
            username: conversation.username.trimmedNonEmpty ?? latestLegacyMessage.sender,
            latestBody: legacyIsLatest ? legacyBody(for: latestLegacyMessage) : conversation.latestBody,
            latestSender: legacyIsLatest ? latestLegacyMessage.sender : conversation.latestSender,
            latestRecipient: legacyIsLatest ? nil : conversation.latestRecipient,
            latestAt: legacyIsLatest ? legacyTimestamp : conversation.latestAt,
            unreadCount: conversation.unreadCount + legacyUnreadCount,
            messageCount: (conversation.messageCount ?? 0) + legacyCount,
            avatarURLString: conversation.avatarURLString
        )
    }

    private static func conversationSort(_ lhs: XBLiveSocialConversation, _ rhs: XBLiveSocialConversation) -> Bool {
        if lhs.unreadCount != rhs.unreadCount {
            return lhs.unreadCount > rhs.unreadCount
        }
        if ProfileSocialTimestamp.value(lhs.latestAt) != ProfileSocialTimestamp.value(rhs.latestAt) {
            return ProfileSocialTimestamp.isLater(lhs.latestAt, than: rhs.latestAt)
        }
        return lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
    }

    private static func isKnownConversation(_ conversation: XBLiveSocialConversation) -> Bool {
        let key = conversation.username.socialNormalizedKey
        return !key.isEmpty && key != "unknown"
    }

    private static func legacyMessageSortAscending(_ lhs: InsigniaMessage, _ rhs: InsigniaMessage) -> Bool {
        let lhsTimestamp = legacyCreatedAt(for: lhs)
        let rhsTimestamp = legacyCreatedAt(for: rhs)
        if ProfileSocialTimestamp.value(lhsTimestamp) != ProfileSocialTimestamp.value(rhsTimestamp) {
            return ProfileSocialTimestamp.isEarlier(lhsTimestamp, than: rhsTimestamp)
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}

struct ProfileSocialThreadView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    let username: String
    let legacyMessages: [InsigniaMessage]
    let friendProfileImages: [String: UIImage]
    let friendProfiles: [String: XBLiveFriendProfile]
    let socialFriends: [XBLiveSocialFriend]
    let markLegacyMessageViewed: (InsigniaMessage) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let currentUserAchievements: XBLiveAchievementsSnapshot?
    let launchGameFromInvite: (LibraryFile) -> Void

    @State private var draft = ""
    @State private var isSending = false
    @State private var reportTarget: ProfileSocialReportTarget?
    @State private var isBlockConfirmationPresented = false
    @State private var isInviteSheetPresented = false

    var body: some View {
        ScrollViewReader { scrollProxy in
            List {
                Section {
                    if messages.isEmpty {
                        if socialStore.isRefreshingMessages {
                            ProfileSocialLoadingRow(title: "Loading thread...")
                        } else {
                            ProfileEmptyRow(title: "No messages in this thread", systemImage: "bubble.left.and.bubble.right")
                        }
                    } else {
                        ForEach(messages) { message in
	                            ProfileSocialMessageBubble(
	                                message: message,
	                                isMine: message.isFromCurrentUser(socialStore.currentUsername),
	                                avatar: avatar(for: message),
	                                invite: inviteContext(for: message)
	                            )
                            .id(message.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    reportTarget = ProfileSocialReportTarget(message: message)
                                } label: {
                                    Label("Report", systemImage: "flag")
                                }
                                .tint(.orange)

                                if !message.isFromCurrentUser(socialStore.currentUsername) {
                                    Button(role: .destructive) {
                                        isBlockConfirmationPresented = true
                                    } label: {
                                        Label("Block", systemImage: "hand.raised")
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    reportTarget = ProfileSocialReportTarget(message: message)
                                } label: {
                                    Label("Report Message", systemImage: "flag")
                                }

                                if !message.isFromCurrentUser(socialStore.currentUsername) {
                                    Button(role: .destructive) {
                                        isBlockConfirmationPresented = true
                                    } label: {
                                        Label("Block User", systemImage: "hand.raised")
                                    }
                                }
                            }
                        }
                    }
                }

                Color.clear
                    .frame(height: 1)
                    .id(bottomAnchorID)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .dukeXThemedListBackground(dimming: 0.18)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ProfileSocialReplyComposer(
                    draft: $draft,
                    isSending: isSending,
                    showInvitePicker: {
                        isInviteSheetPresented = true
                    },
                    send: sendDraft
                )
            }
            .onAppear {
                socialStore.beginReadingThread(with: username)
                scrollToLatestMessage(using: scrollProxy, animated: false)
            }
            .onDisappear {
                socialStore.endReadingThread(with: username)
            }
            .onChange(of: latestMessageID) { _ in
                scrollToLatestMessage(using: scrollProxy)
            }
            .task(id: username) {
                socialStore.beginReadingThread(with: username)
                await socialStore.loadThread(with: username)
                markLegacyMessagesViewed()
                scrollToLatestMessage(using: scrollProxy, animated: false)
            }
            .refreshable {
                await socialStore.loadThread(with: username)
                markLegacyMessagesViewed()
                scrollToLatestMessage(using: scrollProxy, animated: false)
            }
            .navigationTitle(username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
	                    Menu {
	                        Button {
	                            reportTarget = ProfileSocialReportTarget(username: username)
	                        } label: {
                            Label("Report User", systemImage: "flag")
                        }

                        Button(role: .destructive) {
                            isBlockConfirmationPresented = true
                        } label: {
                            Label("Block User", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Conversation Actions")
	                }
	            }
	            .sheet(isPresented: $isInviteSheetPresented) {
	                NavigationStack {
	                    ProfileSocialGameInviteView(
	                        socialStore: socialStore,
	                        username: username,
	                        inviteEligibleGames: inviteEligibleGames
	                    )
	                }
	            }
	            .sheet(item: $reportTarget) { target in
                NavigationStack {
                    ProfileSocialReportView(target: target) { reason in
                        Task {
                            if let message = target.message {
                                await socialStore.reportMessage(message, reason: reason)
                            } else {
                                await socialStore.reportUser(target.username, reason: reason)
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Block \(username)?",
                isPresented: $isBlockConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Block User", role: .destructive) {
                    Task {
                        await socialStore.blockUser(username)
                    }
                }
                Button("Cancel", role: .cancel) {
                    isBlockConfirmationPresented = false
                }
            } message: {
                Text("Blocked users can no longer message you on XB.Live.")
            }
            .alert(item: $socialStore.notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.detail),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var bottomAnchorID: String {
        "profile-social-thread-bottom-\(username.socialNormalizedKey)"
    }

    private var latestMessageID: String {
        messages.last?.id ?? "empty"
    }

    private var messages: [XBLiveSocialMessage] {
        let socialMessages = mergedSocialMessages
        return (socialMessages + legacySocialMessages)
            .filter(isKnownThreadMessage)
            .sorted(by: socialMessageSortAscending)
    }

    private var mergedSocialMessages: [XBLiveSocialMessage] {
        let sourceMessages = socialStore.inboxMessages(for: username) + socialStore.messages(for: username)
        var messagesByID: [String: XBLiveSocialMessage] = [:]
        for message in sourceMessages {
            let resolvedMessage = message.resolvingParticipantNames(
                currentUser: socialStore.currentUsername,
                threadUsername: username
            )
            messagesByID[resolvedMessage.id] = resolvedMessage
        }

        return Array(messagesByID.values)
    }

    private var legacySocialMessages: [XBLiveSocialMessage] {
        legacyMessages
            .filter { $0.sender.socialNormalizedKey == username.socialNormalizedKey }
            .filter { $0.sender.socialNormalizedKey != "unknown" }
            .map {
                XBLiveSocialMessage(
                    id: "insignia-\($0.id)",
                    sender: $0.sender.trimmedNonEmpty ?? username,
                    recipient: socialStore.currentUsername,
                    body: legacyBody(for: $0),
                    kind: $0.type.trimmedNonEmpty ?? "console",
                    createdAt: legacyCreatedAt(for: $0),
                    readAt: "read",
                    filtered: nil
                )
            }
    }

    private func markLegacyMessagesViewed() {
        for message in legacyMessages where message.sender.socialNormalizedKey == username.socialNormalizedKey {
            markLegacyMessageViewed(message)
        }
    }

    private func socialMessageSortAscending(_ lhs: XBLiveSocialMessage, _ rhs: XBLiveSocialMessage) -> Bool {
        if ProfileSocialTimestamp.value(lhs.createdAt) != ProfileSocialTimestamp.value(rhs.createdAt) {
            return ProfileSocialTimestamp.isEarlier(lhs.createdAt, than: rhs.createdAt)
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }

    private func isKnownThreadMessage(_ message: XBLiveSocialMessage) -> Bool {
        let senderKey = message.sender.socialNormalizedKey
        guard !senderKey.isEmpty, senderKey != "unknown" else {
            return false
        }

        if message.isFromCurrentUser(socialStore.currentUsername),
           let recipientKey = message.recipient?.trimmedNonEmpty?.socialNormalizedKey {
            return !recipientKey.isEmpty && recipientKey != "unknown"
        }

        return username.socialNormalizedKey != "unknown"
    }

    private func sendDraft() {
        let body = draft
        isSending = true
        Task {
            let sent = await socialStore.sendMessage(to: username, body: body)
            if sent {
                draft = ""
            }
            isSending = false
        }
    }

    private var avatarResolver: ProfileSocialAvatarResolver {
        ProfileSocialAvatarResolver(
            customImages: friendProfileImages,
            friendProfiles: mergedFriendProfiles,
            socialFriends: socialFriends
        )
    }

    private var mergedFriendProfiles: [String: XBLiveFriendProfile] {
        friendProfiles.merging(socialStore.messageableFriendProfiles) { existing, _ in existing }
    }

    private func avatar(for message: XBLiveSocialMessage) -> ProfileSocialAvatarData {
        let avatarUsername = message.isFromCurrentUser(socialStore.currentUsername) ? username : message.sender
        return avatarResolver.avatar(for: avatarUsername)
    }

    private func inviteContext(for message: XBLiveSocialMessage) -> ProfileSocialGameInviteContext? {
        guard let invite = ProfileSocialGameInvite(messageBody: message.body) else {
            return nil
        }

        let installedGame = installedGames.first {
            GameLaunchLink.normalizedTitleID($0.titleID) == invite.titleID
        }
        let resolvedTitle = invite.title.trimmedNonEmpty ??
            installedGame?.displayName ??
            inviteEligibleGames.first { GameLaunchLink.normalizedTitleID($0.titleID) == invite.titleID }?.displayName ??
            "Title \(invite.titleID)"
        let score = ProfileSocialGameInviteScore.score(
            forTitleID: invite.titleID,
            title: resolvedTitle,
            achievements: currentUserAchievements
        )

        return ProfileSocialGameInviteContext(
            invite: invite.replacingTitle(resolvedTitle),
            installedGame: installedGame,
            score: score,
            senderName: message.sender.trimmedNonEmpty ?? username,
            recipientName: username,
            launch: launchGameFromInvite
        )
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            let action = {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }

            if animated {
                withAnimation(.easeOut(duration: 0.22), action)
            } else {
                action()
            }
        }
    }
}

private struct ProfileSocialReplyComposer: View {
    @Binding var draft: String
    let isSending: Bool
    let showInvitePicker: () -> Void
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: showInvitePicker) {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .regular))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Invite to Game")

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.leading, 13)
                    .padding(.vertical, 9)
                    .accessibilityLabel("Message")

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.46))
                        .frame(width: 31, height: 31)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .padding(.trailing, 5)
                .padding(.bottom, 5)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var canSend: Bool {
        !isSending && draft.trimmedNonEmpty != nil && draft.count <= 320
    }
}

private struct ProfileSocialMessageBubbleBackground: View {
    let isMine: Bool

    var body: some View {
        ProfileSocialMessageBubbleShape(isMine: isMine)
            .fill(isMine ? Color.accentColor : Color.secondary.opacity(0.18))
    }
}

private struct ProfileSocialMessageBubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: min(CGFloat(21), rect.height / 2), height: min(CGFloat(21), rect.height / 2)),
            style: .continuous
        )
        return path
    }
}

private struct ProfileSocialMessageBubble: View {
    let message: XBLiveSocialMessage
    let isMine: Bool
    let avatar: ProfileSocialAvatarData
    let invite: ProfileSocialGameInviteContext?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMine {
                Spacer(minLength: 44)
            } else {
                ProfileSocialAvatar(image: avatar.image, url: avatar.url, initial: avatar.initial)
                    .frame(width: 32, height: 32)
                    .padding(.top, 4)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if let invite {
                    ProfileSocialGameInviteCard(
                        context: invite,
                        isMine: isMine
                    )
                } else {
                    Text(message.body.isEmpty ? " " : message.body)
                        .font(.body)
                        .foregroundStyle(isMine ? .white : .primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(ProfileSocialMessageBubbleBackground(isMine: isMine))
                }

                if let createdAt = ProfileSocialTimestamp.displayText(message.createdAt) {
                    Text(createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !isMine {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

private struct ProfileSocialGameInvite {
    let titleID: String
    let title: String
    let url: URL

    init?(messageBody: String) {
        let trimmedBody = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.launchURLCandidate(in: trimmedBody)
        guard let url = URL(string: candidate),
              let titleID = GameLaunchLink.titleID(from: url) else {
            return nil
        }

        self.titleID = titleID
        title = GameLaunchLink.titleName(from: url) ?? ""
        self.url = url
    }

    init(titleID: String, title: String, url: URL) {
        self.titleID = titleID
        self.title = title
        self.url = url
    }

    func replacingTitle(_ title: String) -> ProfileSocialGameInvite {
        ProfileSocialGameInvite(titleID: titleID, title: title, url: url)
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

private struct ProfileSocialGameInviteContext {
    let invite: ProfileSocialGameInvite
    let installedGame: LibraryFile?
    let score: Int?
    let senderName: String
    let recipientName: String
    let launch: (LibraryFile) -> Void
}

private enum ProfileSocialGameInviteScore {
    static func score(
        forTitleID titleID: String,
        title: String,
        achievements: XBLiveAchievementsSnapshot?
    ) -> Int? {
        guard let achievements else {
            return nil
        }

        let titleIDKey = titleID.uppercased()
        let titleKey = normalizedTitle(title)
        let matchingAchievements = achievements.achievements.filter { achievement in
            if achievement.gameTitleID?.uppercased() == titleIDKey {
                return true
            }
            if let gameTitle = achievement.gameTitle,
               normalizedTitle(gameTitle) == titleKey {
                return true
            }
            return false
        }

        guard !matchingAchievements.isEmpty else {
            return nil
        }

        return matchingAchievements
            .filter { $0.isUnlocked != false }
            .compactMap(\.score)
            .reduce(0, +)
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
}

private struct ProfileSocialGameInviteCard: View {
    @Environment(\.dukeXTheme) private var theme

    let context: ProfileSocialGameInviteContext
    let isMine: Bool

    var body: some View {
        Button {
            if let game = context.installedGame {
                context.launch(game)
            }
        } label: {
            HStack(spacing: 12) {
                ProfileSocialGameInviteIcon(
                    iconURL: XboxTitleIconCatalog.mobCatIconURL(for: context.invite.titleID),
                    localCoverURL: context.installedGame?.coverURL
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(context.invite.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    metadata
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(theme.surfaceColor.opacity(0.86))
            }
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var headline: String {
        if isMine {
            return "You invited \(context.recipientName) to join you in \(context.invite.title)."
        }
        return "\(context.senderName) invited you to play \(context.invite.title) with them."
    }

    private var scoreText: String {
        if let score = context.score {
            return "\(score) GS"
        }
        return "GS not synced"
    }

    private var actionText: String {
        context.installedGame == nil ? "Install to play" : "Tap to launch"
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            metadataRow(scoreText, systemImage: "trophy")
            metadataRow(actionText, systemImage: context.installedGame == nil ? "arrow.down.circle" : "play.circle")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func metadataRow(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .frame(width: 13)

            Text(text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityText: String {
        if isMine {
            return "You invited \(context.recipientName) to play \(context.invite.title). \(actionText)."
        }
        return "\(context.senderName) invited you to play \(context.invite.title). \(actionText)."
    }
}

private struct ProfileSocialGameInviteIcon: View {
    let iconURL: URL?
    let localCoverURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))

            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    default:
                        localCoverOrFallback
                    }
                }
            } else {
                localCoverOrFallback
            }
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var localCoverOrFallback: some View {
        if let localCoverURL,
           let image = UIImage(contentsOfFile: localCoverURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: "gamecontroller")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct ProfileSocialGameInviteView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    let username: String
    let inviteEligibleGames: [LibraryFile]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedGameID: String?
    @State private var isSending = false

    var body: some View {
        List {
            if inviteEligibleGames.isEmpty {
                ProfileEmptyRow(title: "No Live games installed", systemImage: "gamecontroller")
            } else {
                Section("Game") {
                    Picker("Title", selection: selectedGameBinding) {
                        ForEach(inviteEligibleGames) { game in
                            Text(game.displayName).tag(Optional(game.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let selectedGame {
                        ProfileSocialGameInvitePreviewRow(game: selectedGame)
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("Invite to Game")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .onAppear {
            selectedGameID = selectedGameID ?? inviteEligibleGames.first?.id
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    sendInvite()
                }
                .disabled(isSending || selectedGame == nil)
            }
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var selectedGameBinding: Binding<String?> {
        Binding(
            get: { selectedGameID ?? inviteEligibleGames.first?.id },
            set: { selectedGameID = $0 }
        )
    }

    private var selectedGame: LibraryFile? {
        let id = selectedGameID ?? inviteEligibleGames.first?.id
        return inviteEligibleGames.first { $0.id == id }
    }

    private func sendInvite() {
        guard let selectedGame,
              let url = GameLaunchLink.url(for: selectedGame) else {
            return
        }

        isSending = true
        Task {
            let sent = await socialStore.sendMessage(to: username, body: url.absoluteString)
            isSending = false
            if sent {
                dismiss()
            }
        }
    }
}

private struct ProfileSocialGameInvitePreviewRow: View {
    let game: LibraryFile

    var body: some View {
        HStack(spacing: 12) {
            ProfileSocialGameInviteIcon(
                iconURL: XboxTitleIconCatalog.mobCatIconURL(for: game.titleID),
                localCoverURL: game.coverURL
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(GameLaunchLink.normalizedTitleID(game.titleID) ?? "Launch link ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
    }
}

struct ProfileSocialComposeView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    let initialRecipient: String?

    @Environment(\.dismiss) private var dismiss
    @State private var recipient: String
    @State private var messageBody = ""
    @State private var isSending = false

    init(socialStore: XBLiveSocialStore, initialRecipient: String?) {
        self.socialStore = socialStore
        self.initialRecipient = initialRecipient
        _recipient = State(initialValue: initialRecipient ?? "")
    }

    var body: some View {
        List {
            Section("To") {
                TextField("Gamertag", text: $recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !socialStore.messageableFriends.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(socialStore.messageableFriends) { friend in
                                Button {
                                    recipient = friend.username
                                } label: {
                                    Label(friend.title, systemImage: "person.crop.circle")
                                        .labelStyle(.titleOnly)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .dukeXThemedListRowBackground()

            Section {
                TextEditor(text: $messageBody)
                    .frame(minHeight: 120)
                    .accessibilityLabel("Message")

                HStack {
                    Text("\(messageBody.count)/320")
                        .font(.caption)
                        .foregroundStyle(messageBody.count > 320 ? .red : .secondary)
                        .monospacedDigit()
                    Spacer()
                }
            } header: {
                Text("Message")
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("New Message")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    send()
                }
                .disabled(isSending || recipient.trimmedNonEmpty == nil || messageBody.trimmedNonEmpty == nil || messageBody.count > 320)
            }
        }
        .task {
            await socialStore.refreshMessages()
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func send() {
        let to = recipient
        let message = messageBody
        isSending = true
        Task {
            let sent = await socialStore.sendMessage(to: to, body: message)
            isSending = false
            if sent {
                dismiss()
            }
        }
    }
}

struct ProfileXBLiveFriendsView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    @State private var isAddFriendPresented = false

    var body: some View {
        List {
            Section("Requests") {
                if socialStore.incomingRequests.isEmpty && socialStore.outgoingRequests.isEmpty {
                    ProfileEmptyRow(title: "No XB.Live friend requests", systemImage: "person.crop.circle.badge.plus")
                } else {
                    ForEach(socialStore.incomingRequests) { request in
                        ProfileSocialFriendRequestRow(request: request, direction: .incoming) {
                            Task {
                                await socialStore.acceptFriendRequest(from: request.username)
                            }
                        } secondaryAction: {
                            Task {
                                await socialStore.declineFriendRequest(from: request.username)
                            }
                        }
                    }

                    ForEach(socialStore.outgoingRequests) { request in
                        ProfileSocialFriendRequestRow(
                            request: request,
                            direction: .outgoing,
                            primaryAction: {
                                Task {
                                    await socialStore.cancelFriendRequest(to: request.username)
                                }
                            },
                            secondaryAction: nil
                        )
                    }
                }
            }
            .dukeXThemedListRowBackground()

            Section("Messageable Friends") {
                if socialStore.messageableFriends.isEmpty {
                    if socialStore.isRefreshingFriends {
                        ProfileSocialLoadingRow(title: "Loading friends...")
                    } else {
                        ProfileEmptyRow(title: "No XB.Live friends available", systemImage: "person.2")
                    }
                } else {
                    ForEach(socialStore.messageableFriends) { friend in
                        NavigationLink {
                            ProfileXBLiveFriendDetailView(
                                socialStore: socialStore,
                                friend: friend,
                                customProfileImage: nil,
                                supportedGames: [],
                                legacyMessages: [],
                                markLegacyMessageViewed: { _ in },
                                installedGames: [],
                                inviteEligibleGames: [],
                                currentUserAchievements: nil,
                                launchGameFromInvite: { _ in },
                                changeProfileImage: {}
                            )
                        } label: {
                            ProfileSocialFriendRow(
                                friend: friend,
                                profile: socialStore.messageableFriendProfiles[friend.key]
                            )
                        }
                    }
                }
            }
            .dukeXThemedListRowBackground()

            if !socialStore.blockedUsers.isEmpty {
                Section("Blocked") {
                    ForEach(socialStore.blockedUsers, id: \.self) { username in
                        HStack {
                            Label(username, systemImage: "hand.raised")
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    await socialStore.unblockUser(username)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("XB.Live Friends")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddFriendPresented = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add XB.Live Friend")
            }
        }
        .task {
            await socialStore.refreshFriends()
        }
        .refreshable {
            await socialStore.refreshFriends()
        }
        .sheet(isPresented: $isAddFriendPresented) {
            NavigationStack {
                ProfileSocialFriendRequestComposer(socialStore: socialStore)
            }
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct ProfileSocialFriendRequestRow: View {
    enum Direction {
        case incoming
        case outgoing
    }

    let request: XBLiveFriendRequest
    let direction: Direction
    let primaryAction: () -> Void
    let secondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction == .incoming ? "tray.and.arrow.down" : "paperplane")
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.username)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(direction == .incoming ? "Incoming request" : "Outgoing request")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if direction == .incoming {
                Button("Accept", action: primaryAction)
                    .buttonStyle(.borderless)
                if let secondaryAction {
                    Button("Decline", action: secondaryAction)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
            } else {
                Button("Cancel", action: primaryAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
        }
        .frame(minHeight: 52)
    }
}

struct ProfileSocialFriendRow: View {
    let friend: XBLiveSocialFriend
    let profile: XBLiveFriendProfile?
    let customProfileImage: UIImage?

    init(
        friend: XBLiveSocialFriend,
        profile: XBLiveFriendProfile? = nil,
        customProfileImage: UIImage? = nil
    ) {
        self.friend = friend
        self.profile = profile
        self.customProfileImage = customProfileImage
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileSocialAvatar(image: customProfileImage, url: profile?.avatarURL ?? friend.avatarURL, initial: initial)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Circle()
                        .fill(isOnline ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let imageURL = profile?.lastPlayedImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.secondary.opacity(0.18)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(minHeight: 54)
    }

    private var initial: String {
        String(friend.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var detail: String {
        if isOnline,
           let currentGame = profile?.currentGame?.trimmedNonEmpty ?? friend.currentGame?.trimmedNonEmpty {
            return "Online in \(currentGame)"
        }
        if isOnline {
            return "Online"
        }
        if let lastOnlineAt = profile?.lastOnlineAt ?? friend.lastOnlineAt,
           let relativeText = ProfileSocialFriendOnlineText.relativeLastOnlineText(from: lastOnlineAt) {
            return "Last Online: \(relativeText)"
        }
        return fallbackStatusText
    }

    private var isOnline: Bool {
        profile?.isOnline == true ||
            profile?.currentGame?.trimmedNonEmpty != nil ||
            friend.isOnline == true ||
            friend.currentGame?.trimmedNonEmpty != nil
    }

    private var fallbackStatusText: String {
        let state = profile?.lastState?.trimmedNonEmpty ?? friend.status?.trimmedNonEmpty
        guard let state,
              state.caseInsensitiveCompare("offline") != .orderedSame,
              state.caseInsensitiveCompare("unknown") != .orderedSame else {
            return "Last Online: Unknown"
        }
        return state
    }
}

private enum ProfileSocialFriendOnlineText {
    static func relativeLastOnlineText(from timestamp: Double) -> String? {
        guard timestamp > 0 else {
            return nil
        }

        var epochSeconds = timestamp
        if epochSeconds > 9_999_999_999 {
            epochSeconds /= 1_000
        }

        let elapsedSeconds = max(0, Date().timeIntervalSince1970 - epochSeconds)
        let minutes = max(1, Int(elapsedSeconds / 60))
        if minutes < 60 {
            return "\(minutes) \(unit("minute", count: minutes)) ago"
        }

        let hours = max(1, Int(elapsedSeconds / 3_600))
        if hours < 24 {
            return "\(hours) \(unit("hour", count: hours)) ago"
        }

        let days = max(1, Int(elapsedSeconds / 86_400))
        return "\(days) \(unit("day", count: days)) ago"
    }

    private static func unit(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}

struct ProfileXBLiveFriendDetailView: View {
    @ObservedObject var socialStore: XBLiveSocialStore
    let friend: XBLiveSocialFriend
    let customProfileImage: UIImage?
    let supportedGames: [InsigniaSupportedGame]
    let legacyMessages: [InsigniaMessage]
    let markLegacyMessageViewed: (InsigniaMessage) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let currentUserAchievements: XBLiveAchievementsSnapshot?
    let launchGameFromInvite: (LibraryFile) -> Void
    let changeProfileImage: () -> Void

    @State private var isComposePresented = false
    @State private var isRemoveConfirmationPresented = false
    @State private var isBlockConfirmationPresented = false
    @State private var reportTarget: ProfileSocialReportTarget?
    @State private var profile: XBLiveFriendProfile?
    @State private var isLoadingProfile = false
    @State private var profileLoadFailed = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ProfileSocialAvatar(image: customProfileImage, url: effectiveProfile?.avatarURL ?? friend.avatarURL, initial: initial)
                        .frame(width: 74, height: 74)
                        .contextMenu {
                            Button(action: changeProfileImage) {
                                Label("Set Picture", systemImage: "photo")
                            }
                        }

                    VStack(spacing: 4) {
                        Text(friend.title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(isOnline ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .dukeXThemedListRowBackground()

            Section("Profile") {
                if let profile = effectiveProfile {
                    if let score = profile.achievementScore {
                        ProfileInfoRow(title: "Gamerscore", value: "\(score)", systemImage: "trophy")
                    }

                    NavigationLink {
                        ProfileAchievementsView(
                            snapshot: profile.achievements,
                            profileScore: profile.achievementScore,
                            profileCount: profile.achievementCount,
                            supportedGames: supportedGames,
                            gamesPlayed: profile.gamesPlayed ?? []
                        )
                    } label: {
                        ProfileInfoRow(title: "Achievements", value: achievementsSummaryText, systemImage: "medal")
                    }

                    NavigationLink {
                        ProfilePlaytimeView(
                            totalMinutes: profile.totalMinutes,
                            games: profile.gamesPlayed ?? []
                        )
                    } label: {
                        ProfileInfoRow(title: "Play Time", value: playtimeSummaryText, systemImage: "timer")
                    }

                    if let lastPlayed = profile.lastPlayedGame?.trimmedNonEmpty {
                        ProfileInfoRow(title: "Last Played", value: lastPlayed, systemImage: "clock")
                    }
                } else if isLoadingProfile {
                    ProfileSocialLoadingRow(title: "Loading profile...")
                } else {
                    ProfileEmptyRow(
                        title: profileLoadFailed ? "Profile unavailable" : "Profile not loaded",
                        systemImage: "person.crop.circle"
                    )
                }
            }
            .dukeXThemedListRowBackground()

            Section("XB.Live") {
                NavigationLink {
                    ProfileSocialThreadView(
                        socialStore: socialStore,
                        username: friend.username,
                        legacyMessages: legacyMessages,
                        friendProfileImages: threadProfileImages,
                        friendProfiles: threadFriendProfiles,
                        socialFriends: [friend],
                        markLegacyMessageViewed: markLegacyMessageViewed,
                        installedGames: installedGames,
                        inviteEligibleGames: inviteEligibleGames,
                        currentUserAchievements: currentUserAchievements,
                        launchGameFromInvite: launchGameFromInvite
                    )
                } label: {
                    ProfileInfoRow(title: "Messages", value: "Open", systemImage: "bubble.left.and.bubble.right")
                }

                Button {
                    isComposePresented = true
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
            }
            .dukeXThemedListRowBackground()

            Section("Moderation") {
                Button {
                    reportTarget = ProfileSocialReportTarget(username: friend.username)
                } label: {
                    Label("Report User", systemImage: "flag")
                }

                Button(role: .destructive) {
                    isBlockConfirmationPresented = true
                } label: {
                    Label("Block User", systemImage: "hand.raised")
                }

                Button(role: .destructive) {
                    isRemoveConfirmationPresented = true
                } label: {
                    Label("Remove Friend", systemImage: "person.crop.circle.badge.minus")
                }
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle(friend.title)
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: changeProfileImage) {
                    Image(systemName: "photo")
                }
                .accessibilityLabel("Set Profile Picture")
            }
        }
        .task(id: friend.username) {
            await loadProfile()
        }
        .sheet(isPresented: $isComposePresented) {
            NavigationStack {
                ProfileSocialComposeView(
                    socialStore: socialStore,
                    initialRecipient: friend.username
                )
            }
        }
        .sheet(item: $reportTarget) { target in
            NavigationStack {
                ProfileSocialReportView(target: target) { reason in
                    Task {
                        await socialStore.reportUser(target.username, reason: reason)
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove \(friend.title)?",
            isPresented: $isRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Friend", role: .destructive) {
                Task {
                    await socialStore.removeFriend(friend.username)
                }
            }
            Button("Cancel", role: .cancel) {
                isRemoveConfirmationPresented = false
            }
        } message: {
            Text("This removes the XB.Live friendship and does not affect Insignia friends.")
        }
        .confirmationDialog(
            "Block \(friend.title)?",
            isPresented: $isBlockConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Block User", role: .destructive) {
                Task {
                    await socialStore.blockUser(friend.username)
                }
            }
            Button("Cancel", role: .cancel) {
                isBlockConfirmationPresented = false
            }
        } message: {
            Text("Blocked users can no longer message you on XB.Live.")
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var initial: String {
        String(friend.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var statusLine: String {
        if let currentGame = effectiveProfile?.currentGame?.trimmedNonEmpty ?? friend.currentGame?.trimmedNonEmpty {
            return "Online in \(currentGame)"
        }
        if effectiveProfile?.isOnline == true || friend.isOnline == true {
            return "Online"
        }
        if let lastOnlineAt = effectiveProfile?.lastOnlineAt ?? friend.lastOnlineAt,
           let relativeText = ProfileSocialFriendOnlineText.relativeLastOnlineText(from: lastOnlineAt) {
            return "Last Online: \(relativeText)"
        }
        let state = effectiveProfile?.lastState?.trimmedNonEmpty ?? friend.status?.trimmedNonEmpty
        guard let state,
              state.caseInsensitiveCompare("offline") != .orderedSame,
              state.caseInsensitiveCompare("unknown") != .orderedSame else {
            return "Last Online: Unknown"
        }
        return state
    }

    private var isOnline: Bool {
        effectiveProfile?.isOnline == true ||
            effectiveProfile?.currentGame?.trimmedNonEmpty != nil ||
            friend.isOnline == true ||
            friend.currentGame?.trimmedNonEmpty != nil
    }

    private var threadProfileImages: [String: UIImage] {
        guard let customProfileImage else {
            return [:]
        }

        return [friend.key: customProfileImage]
    }

    private var threadFriendProfiles: [String: XBLiveFriendProfile] {
        guard let profile = effectiveProfile else {
            return [:]
        }

        return [friend.key: profile]
    }

    private var achievementsSummaryText: String {
        effectiveProfile?.achievements?.summaryText ??
            effectiveProfile?.achievementCount.map(String.init) ??
            "Not Synced"
    }

    private var playtimeSummaryText: String {
        if let minutes = effectiveProfile?.totalMinutes {
            return playTimeText(minutes)
        }

        let games = effectiveProfile?.gamesPlayed ?? []
        if !games.isEmpty {
            return "\(games.count) Game\(games.count == 1 ? "" : "s")"
        }

        return "Not Synced"
    }

    private func loadProfile() async {
        guard !isLoadingProfile else {
            return
        }

        if profile == nil {
            profile = socialStore.messageableFriendProfiles[friend.key]
        }

        isLoadingProfile = true
        profileLoadFailed = false
        defer {
            isLoadingProfile = false
        }

        do {
            let username = friend.username
            let xbProfile = try await XBLiveService.fetchProfile(username: username)
            let games = (try? await XBLiveService.fetchGamesPlayed(username: username)) ?? []
            let achievements = try? await XBLiveService.fetchAchievements(username: username)
            let lastGame = games.first { $0.gameName == xbProfile.lastPlayedGame } ?? games.first
            let isOnline = xbProfile.isOnline || friend.isOnline == true

            profile = XBLiveFriendProfile(
                gamertag: friend.title,
                avatarURLString: xbProfile.avatarURLString ?? friend.avatarURLString,
                isOnline: isOnline,
                lastState: xbProfile.lastState ?? friend.status,
                currentGame: xbProfile.currentGame ?? (isOnline ? friend.currentGame : nil),
                lastPlayedGame: xbProfile.lastPlayedGame ?? lastGame?.gameName,
                lastPlayedAt: xbProfile.lastPlayedAt,
                lastOnlineAt: lastOnlineTimestamp(isOnline: isOnline, profile: xbProfile),
                lastCheckedAt: xbProfile.lastCheckedAt,
                achievementScore: xbProfile.achievementScore,
                achievementCount: xbProfile.achievementCount,
                totalMinutes: xbProfile.totalMinutes ?? totalMinutes(from: games),
                lastPlayedImageURLString: lastGame?.imageUrl,
                gamesPlayed: games,
                achievements: achievements
            )
        } catch {
            profileLoadFailed = true
        }
    }

    private func lastOnlineTimestamp(isOnline: Bool, profile: XBLiveProfileSnapshot) -> Double? {
        if isOnline {
            return profile.lastCheckedAt ?? profile.lastOnlineAt ?? friend.lastOnlineAt
        }
        return profile.lastOnlineAt ?? profile.lastPlayedAt ?? friend.lastOnlineAt
    }

    private func totalMinutes(from games: [XBLiveGamePlayed]) -> Double? {
        let minutes = games.compactMap(\.totalMinutes)
        guard !minutes.isEmpty else {
            return nil
        }
        return minutes.reduce(0, +)
    }

    private func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }

    private var effectiveProfile: XBLiveFriendProfile? {
        profile ?? socialStore.messageableFriendProfiles[friend.key]
    }
}

struct ProfileSocialFriendRequestComposer: View {
    @ObservedObject var socialStore: XBLiveSocialStore

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isSending = false

    var body: some View {
        List {
            Section("Friend") {
                TextField("Gamertag", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Add Friend")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    send()
                }
                .disabled(isSending || username.trimmedNonEmpty == nil)
            }
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func send() {
        let target = username
        isSending = true
        Task {
            await socialStore.sendFriendRequest(to: target)
            isSending = false
            dismiss()
        }
    }
}

struct ProfileSocialReportView: View {
    let target: ProfileSocialReportTarget
    let submit: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        List {
            Section("Report") {
                ProfileInfoRow(title: "User", value: target.username, systemImage: "person")

                if target.message != nil {
                    ProfileInfoRow(title: "Context", value: "Message", systemImage: "envelope")
                } else {
                    ProfileInfoRow(title: "Context", value: "User", systemImage: "person.crop.circle")
                }
            }
            .dukeXThemedListRowBackground()

            Section("Reason") {
                TextEditor(text: $reason)
                    .frame(minHeight: 96)
                    .accessibilityLabel("Report Reason")
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    submit(reason.trimmedNonEmpty)
                    dismiss()
                }
            }
        }
    }
}

struct ProfileSocialReportTarget: Identifiable {
    let id = UUID()
    let username: String
    let message: XBLiveSocialMessage?

    init(username: String) {
        self.username = username
        message = nil
    }

    init(message: XBLiveSocialMessage) {
        username = message.sender
        self.message = message
    }
}

private func legacyBody(for message: InsigniaMessage) -> String {
    if let game = message.game?.trimmedNonEmpty {
        return "[message from \(game)]"
    }

    if let type = message.type.trimmedNonEmpty {
        return "[\(type)]"
    }

    return "[console message]"
}

private func legacyCreatedAt(for message: InsigniaMessage) -> String? {
    if message.sentAt?.trimmedNonEmpty != nil {
        return message.sentAt
    }
    if let numericID = Double(message.id),
       numericID > 1_000_000_000 {
        return message.id
    }
    return message.sentAt
}

private enum ProfileSocialTimestamp {
    static func value(_ rawValue: String?) -> Double? {
        guard let rawValue = rawValue?.trimmedNonEmpty else {
            return nil
        }

        if let number = Double(rawValue) {
            return number > 9_999_999_999 ? number / 1_000.0 : number
        }

        if let relativeValue = relativeTimestampValue(rawValue) {
            return relativeValue
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

        for formatter in fallbackFormatters {
            if let date = formatter.date(from: rawValue) {
                return date.timeIntervalSince1970
            }
        }

        return nil
    }

    static func isEarlier(_ lhs: String?, than rhs: String?) -> Bool {
        guard let lhsValue = value(lhs) else {
            return false
        }
        guard let rhsValue = value(rhs) else {
            return true
        }
        return lhsValue < rhsValue
    }

    static func isLater(_ lhs: String?, than rhs: String?) -> Bool {
        guard let lhsValue = value(lhs) else {
            return false
        }
        guard let rhsValue = value(rhs) else {
            return true
        }
        return lhsValue > rhsValue
    }

    static func displayText(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmedNonEmpty else {
            return nil
        }

        guard let timestamp = value(rawValue) else {
            return rawValue
        }

        return displayFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss Z",
            "M/d/yy, h:mm a",
            "M/d/yyyy, h:mm a",
            "MMM d, yyyy, h:mm a",
            "MMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy 'at' h:mm a"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static func relativeTimestampValue(_ rawValue: String) -> Double? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "just now" || normalized == "now" {
            return Date().timeIntervalSince1970
        }
        if normalized == "yesterday" {
            return Date().timeIntervalSince1970 - 86_400
        }

        let parts = normalized.split(separator: " ")
        guard parts.count >= 3,
              parts.last == "ago",
              let amount = Double(parts[0]) else {
            return nil
        }

        let unit = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "s"))
        let seconds: Double
        switch unit {
        case "second", "sec":
            seconds = amount
        case "minute", "min":
            seconds = amount * 60
        case "hour", "hr":
            seconds = amount * 3_600
        case "day":
            seconds = amount * 86_400
        case "week":
            seconds = amount * 604_800
        case "month":
            seconds = amount * 2_592_000
        case "year":
            seconds = amount * 31_536_000
        default:
            return nil
        }

        return Date().timeIntervalSince1970 - seconds
    }
}

struct ProfileSocialLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }
}

private struct ProfileSocialAvatar: View {
    let image: UIImage?
    let url: URL?
    let initial: String

    init(image: UIImage? = nil, url: URL?, initial: String) {
        self.image = image
        self.url = url
        self.initial = initial
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallback
                }
            }
            .clipShape(Circle())
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
            Text(initial)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var socialNormalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
