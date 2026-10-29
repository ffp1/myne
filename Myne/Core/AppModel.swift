import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

extension DocumentReference {
    /// Fire-and-forget write. Firestore queues it offline and syncs in order.
    func write(_ data: [String: Any], merge: Bool = true) {
        setData(data, merge: merge) { _ in }
    }

    func patch(_ data: [String: Any]) {
        updateData(data) { _ in }
    }
}

@MainActor
@Observable
final class AppModel {
    enum AuthState { case loading, signedOut, needsProfile, ready }

    var authState: AuthState = .loading
    var uid: String?
    var me: AppUser?
    var users: [String: AppUser] = [:]
    var rooms: [Room] = []
    var prefs: [String: RoomPrefs] = [:]
    var friends: [Friend] = []
    var notifications: [AppNotification] = []

    var selectedTab: AppTab = .talk
    var talkPath: [Route] = []
    var profilePath: [Route] = []
    var talkSheet: TalkSheet?
    var myScreen: IdentifiedID?
    var isSelectingRooms = false
    var activeRoomId: String?
    var pendingComposer: PendingComposer?
    var searchIndexVersion = 0

    @ObservationIgnored var messageCache: [String: [Message]] = [:]
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var userListeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var knownUnread: [String: Int]?
    @ObservationIgnored private var dataStarted = false

    var db: Firestore { Firestore.firestore() }

    // MARK: - Lifecycle

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.authChanged(user?.uid) }
        }
    }

    private func authChanged(_ newUid: String?) {
        if newUid == uid && authState != .loading { return }
        stopListeners()
        uid = newUid
        guard let newUid else {
            authState = .signedOut
            return
        }
        authState = .loading
        let listener = db.collection("users").document(newUid).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                if snap.exists, let user = try? snap.data(as: AppUser.self) {
                    self.me = user
                    self.users[user.id] = user
                    if !self.dataStarted { self.startDataListeners(newUid) }
                    self.authState = .ready
                } else if !snap.metadata.isFromCache {
                    self.authState = .needsProfile
                }
            }
        }
        listeners.append(listener)
    }

    private func startDataListeners(_ uid: String) {
        dataStarted = true
        let userRef = db.collection("users").document(uid)

        listeners.append(db.collection("rooms").whereField("members", arrayContains: uid).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                let rooms = snap.documents.compactMap { try? $0.data(as: Room.self) }
                self.notifyIncoming(rooms)
                self.rooms = rooms
                for member in Set(rooms.flatMap(\.members)) { self.observeUser(member) }
                UNUserNotificationCenter.current().setBadgeCount(self.totalUnread) { _ in }
            }
        })

        listeners.append(userRef.collection("roomPrefs").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                var prefs: [String: RoomPrefs] = [:]
                for doc in snap.documents {
                    if let pref = try? doc.data(as: RoomPrefs.self) { prefs[doc.documentID] = pref }
                }
                self.prefs = prefs
            }
        })

        listeners.append(userRef.collection("friends").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                self.friends = snap.documents.compactMap { try? $0.data(as: Friend.self) }
                for friend in self.friends { self.observeUser(friend.id) }
            }
        })

        listeners.append(userRef.collection("notifications").order(by: "createdAt", descending: true).limit(to: 50).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap else { return }
                self.notifications = snap.documents.compactMap { try? $0.data(as: AppNotification.self) }
                for n in self.notifications { self.observeUser(n.fromUid) }
            }
        })

        NotificationPresenter.requestAuthorization()
        Task { await ensureMyRoom() }
    }

    var myRoomId: String { "mine_\(uid ?? "")" }

    /// マイルームは全ユーザーに最初から用意する
    private func ensureMyRoom() async {
        guard let uid else { return }
        let ref = db.collection("rooms").document(myRoomId)
        guard let snap = try? await ref.getDocument(), !snap.exists else { return }
        let room = Room(
            id: myRoomId, type: .mine, members: [uid], name: nil, iconId: nil, lastMessage: nil,
            updatedAt: Date(), unread: [:], readAt: [:], createdBy: uid
        )
        try? ref.setData(from: room) { _ in }
    }

    private func stopListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        userListeners.values.forEach { $0.remove() }
        userListeners.removeAll()
        dataStarted = false
        knownUnread = nil
        me = nil
        users = [:]
        rooms = []
        prefs = [:]
        friends = []
        notifications = []
        messageCache = [:]
        talkPath = []
        profilePath = []
    }

    func observeUser(_ id: String) {
        guard !id.isEmpty, userListeners[id] == nil else { return }
        userListeners[id] = db.collection("users").document(id).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                guard let self, let snap, let user = try? snap.data(as: AppUser.self) else { return }
                self.users[id] = user
            }
        }
    }

    private func notifyIncoming(_ newRooms: [Room]) {
        guard let uid else { return }
        var counts: [String: Int] = [:]
        for room in newRooms { counts[room.id] = room.unreadCount(for: uid) }
        defer { knownUnread = counts }
        guard let known = knownUnread,
              UserDefaults.standard.object(forKey: "notify.enabled") as? Bool ?? true else { return }
        let preview = UserDefaults.standard.object(forKey: "notify.preview") as? Bool ?? true
        for room in newRooms {
            guard room.unreadCount(for: uid) > (known[room.id] ?? 0),
                  let last = room.lastMessage, last.senderId != uid,
                  room.id != activeRoomId, !pref(room.id).isMuted else { continue }
            let sender = users[last.senderId]?.name ?? ""
            let title = room.isGroup ? displayName(room) : sender
            let body = preview ? (room.isGroup ? "\(sender): \(last.text)" : last.text) : "新着メッセージがあります"
            NotificationPresenter.post(thread: room.id, title: title, body: body)
        }
    }

    // MARK: - Derived

    func pref(_ roomId: String) -> RoomPrefs { prefs[roomId] ?? RoomPrefs() }

    func unread(_ room: Room) -> Int { room.unreadCount(for: uid) }

    var totalUnread: Int { rooms.reduce(0) { $0 + $1.unreadCount(for: uid) } }

    var visibleRooms: [Room] {
        rooms
            .filter { !pref($0.id).isHidden }
            .sorted { a, b in
                let pa = pref(a.id), pb = pref(b.id)
                if pa.isPinned != pb.isPinned { return pa.isPinned }
                return a.updatedAt > b.updatedAt
            }
    }

    var hiddenRooms: [Room] {
        rooms.filter { pref($0.id).isHidden }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var groupRooms: [Room] {
        rooms.filter(\.isGroup).sorted { displayName($0) < displayName($1) }
    }

    var hasUnreadNotifications: Bool { notifications.contains { !($0.read ?? false) } }

    var bellSymbol: String { hasUnreadNotifications || !birthdayFriends.isEmpty ? "bell.badge" : "bell" }

    func displayName(_ room: Room) -> String {
        if room.isMine { return "マイルーム" }
        if room.isGroup {
            if let name = room.name, !name.isEmpty { return name }
            return room.members.filter { $0 != uid }.compactMap { users[$0]?.name }.joined(separator: ", ")
        }
        return room.partner(of: uid).flatMap { users[$0]?.name } ?? ""
    }

    func isFriend(_ id: String) -> Bool { friends.contains { $0.id == id } }

    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }

    var friendUsers: [AppUser] {
        friends.compactMap { users[$0.id] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var birthdayFriends: [AppUser] {
        friends.compactMap { users[$0.id] }.filter(\.isBirthdayToday)
    }

    /// 誕生日 → 親しい友だち → 最近追加 の順で最大5人
    var featuredFriends: [AppUser] {
        var result: [String] = birthdayFriends.map(\.id)
        let byRecent = friends.sorted { $0.addedAt > $1.addedAt }
        for f in byRecent where f.close && !result.contains(f.id) { result.append(f.id) }
        for f in byRecent where !result.contains(f.id) { result.append(f.id) }
        return result.prefix(5).compactMap { users[$0] }
    }

    func directRoomId(with other: String) -> String {
        [uid ?? "", other].sorted().joined(separator: "_")
    }

    // MARK: - Navigation

    func push(_ route: Route) {
        switch selectedTab {
        case .talk: talkPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func openRoom(_ id: String, composer: Composer? = nil) {
        pendingComposer = composer.map { PendingComposer(roomId: id, composer: $0) }
        myScreen = nil
        talkSheet = nil
        isSelectingRooms = false
        selectedTab = .talk
        talkPath = [.room(id)]
    }

    /// 他のシートが開いているときは閉じてから全画面のマイスクリーンを出す
    func presentMyScreen(_ userId: String, afterDismissing: Bool = false) {
        observeUser(userId)
        if afterDismissing || talkSheet != nil {
            talkSheet = nil
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                myScreen = IdentifiedID(id: userId)
            }
        } else {
            myScreen = IdentifiedID(id: userId)
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "myne", url.host == "add" else { return }
        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/" else { return }
        presentMyScreen(id)
    }

    // MARK: - Search

    func loadSearchIndex() async {
        for room in rooms where messageCache[room.id] == nil {
            let snap = try? await db.collection("rooms").document(room.id).collection("messages")
                .order(by: "sentAt", descending: true).limit(to: 300).getDocuments()
            messageCache[room.id] = snap?.documents.compactMap { try? $0.data(as: Message.self) } ?? []
        }
        searchIndexVersion += 1
    }

    func messagesMatch(roomId: String, query: String) -> Bool {
        let cleared = pref(roomId).clearedAt ?? .distantPast
        let uid = uid ?? ""
        return messageCache[roomId]?.contains {
            $0.sentAt > cleared && !$0.isUnsent && !($0.deletedFor ?? []).contains(uid)
                && ($0.text ?? "").localizedCaseInsensitiveContains(query)
        } ?? false
    }

    func roomMatches(_ room: Room, query: String) -> Bool {
        if displayName(room).localizedCaseInsensitiveContains(query) { return true }
        if room.members.contains(where: { users[$0]?.name.localizedCaseInsensitiveContains(query) ?? false }) { return true }
        let cleared = pref(room.id).clearedAt ?? .distantPast
        if let last = room.lastMessage, last.sentAt > cleared, last.text.localizedCaseInsensitiveContains(query) { return true }
        return messagesMatch(roomId: room.id, query: query)
    }
}
