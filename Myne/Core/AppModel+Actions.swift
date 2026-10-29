import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

struct MyneError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension AppModel {
    private var userRef: DocumentReference { db.collection("users").document(uid ?? "_") }
    private func roomRef(_ id: String) -> DocumentReference { db.collection("rooms").document(id) }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw MyneError(message: "Googleログインが設定されていません")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = UIApplication.shared.topViewController else { return }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw MyneError(message: "Googleログインに失敗しました")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        try await Auth.auth().signIn(with: credential)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        guard let uid, let me else { return }
        db.collection("myneIds").document(me.myneId).delete { _ in }
        try await db.collection("users").document(uid).delete()
        do {
            try await Auth.auth().currentUser?.delete()
        } catch {
            signOut()
            throw MyneError(message: "再ログイン後にもう一度お試しください")
        }
    }

    static func isValidMyneId(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9._]{4,20}$", options: .regularExpression) != nil
    }

    private func claim(myneId: String, releasing old: String? = nil) async throws {
        guard let uid else { return }
        let db = self.db
        let ref = db.collection("myneIds").document(myneId)
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snap = try transaction.getDocument(ref)
                if snap.exists, (snap.get("uid") as? String) != uid {
                    errorPointer?.pointee = NSError(domain: "Myne", code: 409, userInfo: [NSLocalizedDescriptionKey: "このIDは既に使われています"])
                    return nil
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            transaction.setData(["uid": uid], forDocument: ref)
            if let old, old != myneId {
                transaction.deleteDocument(db.collection("myneIds").document(old))
            }
            return true
        }
    }

    func createProfile(name: String, myneId: String, birthday: Date?, icon: UIImage?) async throws {
        guard let uid else { return }
        let id = myneId.lowercased()
        guard Self.isValidMyneId(id) else { throw MyneError(message: "IDは英小文字・数字・._ の4〜20文字です") }
        try await claim(myneId: id)
        var iconId: String?
        if let icon { iconId = await ImageStore.shared.upload(icon, owner: uid, maxDimension: 512) }
        let user = AppUser(
            id: uid, name: name, myneId: id, bio: nil,
            birthday: birthday.map { Fmt.storage.string(from: $0) },
            iconId: iconId, backgroundId: nil, allowIdSearch: true, showBirthday: true, createdAt: Date()
        )
        try db.collection("users").document(uid).setData(from: user) { _ in }
    }

    func changeMyneId(_ newId: String) async throws {
        guard let me else { return }
        let id = newId.lowercased()
        guard Self.isValidMyneId(id) else { throw MyneError(message: "IDは英小文字・数字・._ の4〜20文字です") }
        guard id != me.myneId else { return }
        try await claim(myneId: id, releasing: me.myneId)
        userRef.patch(["myneId": id])
    }

    // MARK: - Profile

    func updateProfile(_ fields: [String: Any]) {
        userRef.patch(fields)
    }

    func setIcon(_ image: UIImage) async {
        guard let uid, let id = await ImageStore.shared.upload(image, owner: uid, maxDimension: 512) else { return }
        userRef.patch(["iconId": id])
    }

    func setBackground(_ image: UIImage) async {
        guard let uid, let id = await ImageStore.shared.upload(image, owner: uid, maxDimension: 1600) else { return }
        userRef.patch(["backgroundId": id])
    }

    func findUser(myneId: String) async -> AppUser? {
        let id = myneId.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !id.isEmpty,
              let snap = try? await db.collection("users").whereField("myneId", isEqualTo: id).limit(to: 1).getDocuments(),
              let user = snap.documents.first.flatMap({ try? $0.data(as: AppUser.self) }),
              user.allowIdSearch != false || user.id == uid else { return nil }
        users[user.id] = user
        return user
    }

    // MARK: - Friends

    func addFriend(_ other: String) {
        guard let uid, other != uid else { return }
        userRef.collection("friends").document(other).write([
            "id": other, "addedAt": Timestamp(date: Date()), "isClose": false
        ], merge: false)
        let ref = db.collection("users").document(other).collection("notifications").document()
        ref.write([
            "id": ref.documentID, "kind": "friendAdded", "fromUid": uid,
            "createdAt": Timestamp(date: Date()), "read": false
        ], merge: false)
        Haptics.success()
    }

    func removeFriend(_ other: String) {
        userRef.collection("friends").document(other).delete { _ in }
    }

    func toggleClose(_ other: String) {
        let current = friend(other)?.close ?? false
        userRef.collection("friends").document(other).patch(["isClose": !current])
    }

    func markNotificationsRead() {
        for n in notifications where !(n.read ?? false) {
            userRef.collection("notifications").document(n.id).patch(["read": true])
        }
    }

    // MARK: - Rooms

    func setPref(_ roomId: String, _ data: [String: Any]) {
        userRef.collection("roomPrefs").document(roomId).write(data)
    }

    func togglePin(_ roomId: String) {
        setPref(roomId, ["pinned": !pref(roomId).isPinned, "pinnedAt": Timestamp(date: Date())])
    }

    func toggleMute(_ roomId: String) {
        setPref(roomId, ["muted": !pref(roomId).isMuted])
    }

    func hide(_ ids: [String]) {
        for id in ids where id != myRoomId { setPref(id, ["hidden": true, "pinned": false]) }
    }

    func unhide(_ id: String) {
        setPref(id, ["hidden": false])
    }

    /// 会話データを自分の側から消去し、非表示にする
    func deleteRooms(_ ids: [String]) {
        for id in ids {
            markRead(id)
            // マイルームは中身だけ消して一覧には残す
            let hides = id != myRoomId
            setPref(id, ["hidden": hides, "pinned": hides ? false : pref(id).isPinned, "clearedAt": Timestamp(date: Date())])
            messageCache[id] = nil
        }
    }

    func markRead(_ roomId: String) {
        guard let uid, let room = rooms.first(where: { $0.id == roomId }) else { return }
        let last = room.lastMessage?.sentAt ?? .distantPast
        let readAt = room.readAt?[uid] ?? .distantPast
        guard room.unreadCount(for: uid) > 0 || readAt < last else { return }
        roomRef(roomId).patch(["unread.\(uid)": 0, "readAt.\(uid)": Timestamp(date: Date())])
    }

    func markRead(_ ids: [String]) { ids.forEach { markRead($0) } }

    func markAllRead() { rooms.forEach { markRead($0.id) } }

    func ensureDirectRoom(with other: String) async -> String? {
        guard let uid else { return nil }
        let id = directRoomId(with: other)
        if rooms.contains(where: { $0.id == id }) { return id }
        let ref = roomRef(id)
        if let snap = try? await ref.getDocument(), snap.exists { return id }
        let room = Room(
            id: id, type: .direct, members: [uid, other], name: nil, iconId: nil, lastMessage: nil,
            updatedAt: Date(), unread: [:], readAt: [:], createdBy: uid
        )
        try? ref.setData(from: room) { _ in }
        return id
    }

    func createGroup(name: String, members: [String], icon: UIImage?) async -> String? {
        guard let uid else { return nil }
        let ref = db.collection("rooms").document()
        var iconId: String?
        if let icon { iconId = await ImageStore.shared.upload(icon, owner: uid, maxDimension: 512) }
        let room = Room(
            id: ref.documentID, type: .group, members: Array(Set(members + [uid])), name: name, iconId: iconId,
            lastMessage: nil, updatedAt: Date(), unread: [:], readAt: [:], createdBy: uid
        )
        try? ref.setData(from: room) { _ in }
        return ref.documentID
    }

    func addMembers(_ ids: [String], to roomId: String) {
        guard !ids.isEmpty else { return }
        roomRef(roomId).patch(["members": FieldValue.arrayUnion(ids)])
    }

    func leaveGroup(_ roomId: String) {
        guard let uid else { return }
        roomRef(roomId).patch(["members": FieldValue.arrayRemove([uid])])
        talkPath.removeAll()
    }

    // MARK: - Messages

    func send(
        roomId: String, kind: MessageKind = .text, text: String?, images: [UIImage] = [],
        replyTo: ReplyRef? = nil, poll: Poll? = nil, amida: Amida? = nil, card: BirthdayCard? = nil,
        forwarded: Bool = false
    ) async {
        guard let uid else { return }
        var room = rooms.first { $0.id == roomId }
        if room == nil {
            room = try? await roomRef(roomId).getDocument().data(as: Room.self)
        }
        guard let room else { return }

        var imageIds: [String] = []
        for image in images {
            if let id = await ImageStore.shared.upload(image, owner: uid, maxDimension: 1280) { imageIds.append(id) }
        }

        let ref = roomRef(roomId).collection("messages").document()
        let now = Date()
        let message = Message(
            id: ref.documentID, senderId: uid, kind: kind, text: text,
            imageIds: imageIds.isEmpty ? nil : imageIds, replyTo: replyTo, poll: poll, amida: amida, card: card,
            sentAt: now, deletedFor: nil, unsent: nil, forwarded: forwarded ? true : nil
        )
        try? ref.setData(from: message) { _ in }

        var update: [String: Any] = [
            "lastMessage": ["text": message.previewText, "senderId": uid, "sentAt": Timestamp(date: now)],
            "updatedAt": Timestamp(date: now),
            "unread.\(uid)": 0,
            "readAt.\(uid)": Timestamp(date: now),
        ]
        for member in room.members where member != uid {
            update["unread.\(member)"] = FieldValue.increment(Int64(1))
        }
        roomRef(roomId).patch(update)
        if pref(roomId).isHidden { unhide(roomId) }
        messageCache[roomId]?.insert(message, at: 0)
    }

    func forward(_ message: Message, to roomIds: [String]) async {
        for id in roomIds {
            await sendCopy(of: message, to: id)
        }
    }

    private func sendCopy(of message: Message, to roomId: String) async {
        guard let uid, let room = rooms.first(where: { $0.id == roomId }) else { return }
        let ref = roomRef(roomId).collection("messages").document()
        let now = Date()
        var copy = message
        copy.id = ref.documentID
        copy.senderId = uid
        copy.sentAt = now
        copy.replyTo = nil
        copy.deletedFor = nil
        copy.forwarded = true
        if var poll = copy.poll { poll.votes = nil; copy.poll = poll }
        try? ref.setData(from: copy) { _ in }
        var update: [String: Any] = [
            "lastMessage": ["text": copy.previewText, "senderId": uid, "sentAt": Timestamp(date: now)],
            "updatedAt": Timestamp(date: now),
            "readAt.\(uid)": Timestamp(date: now),
        ]
        for member in room.members where member != uid {
            update["unread.\(member)"] = FieldValue.increment(Int64(1))
        }
        roomRef(roomId).patch(update)
    }

    func deleteForMe(_ message: Message, in roomId: String) {
        guard let uid else { return }
        roomRef(roomId).collection("messages").document(message.id).patch(["deletedFor": FieldValue.arrayUnion([uid])])
    }

    func unsend(_ message: Message, in roomId: String) {
        roomRef(roomId).collection("messages").document(message.id).patch([
            "unsent": true, "text": "", "imageIds": [],
            "poll": FieldValue.delete(), "amida": FieldValue.delete(), "card": FieldValue.delete(),
        ])
        if let last = rooms.first(where: { $0.id == roomId })?.lastMessage,
           abs(last.sentAt.timeIntervalSince(message.sentAt)) < 0.01 {
            roomRef(roomId).patch(["lastMessage.text": "送信取消"])
        }
    }

    func vote(_ message: Message, option: Int, in roomId: String) {
        guard let uid else { return }
        let current = message.poll?.votes?[uid]
        let value: Any = current == option ? FieldValue.delete() as Any : option as Any
        roomRef(roomId).collection("messages").document(message.id).patch(["poll.votes.\(uid)": value])
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
