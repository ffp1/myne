import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("chat.fontSize") private var fontSize = ChatFontSize.standard
    @AppStorage("notify.enabled") private var notifyEnabled = true
    @AppStorage("notify.preview") private var notifyPreview = true
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var providers: String {
        let ids = Auth.auth().currentUser?.providerData.map(\.providerID) ?? []
        return ids.map { $0 == "google.com" ? "Google" : ($0 == "password" ? "メール" : $0) }.joined(separator: ", ")
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                NavigationLink(value: Route.editProfile(.all)) {
                    HStack(spacing: 14) {
                        AvatarView(userId: model.uid, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.me?.name ?? "").font(.headline)
                            Text("@\(model.me?.myneId ?? "")").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("アカウント") {
                NavigationLink(value: Route.myneId) {
                    LabeledContent("ID", value: "@\(model.me?.myneId ?? "")")
                }
                LabeledContent("メールアドレス", value: Auth.auth().currentUser?.email ?? "-")
                LabeledContent("ログイン方法", value: providers)
            }

            Section("プライバシー") {
                Toggle("IDで友だち追加を許可", isOn: Binding(
                    get: { model.me?.allowIdSearch ?? true },
                    set: { model.updateProfile(["allowIdSearch": $0]) }
                ))
                Toggle("誕生日を友だちに公開", isOn: Binding(
                    get: { model.me?.showBirthday ?? true },
                    set: { model.updateProfile(["showBirthday": $0]) }
                ))
                NavigationLink(value: Route.hiddenRooms) {
                    Label("非表示リスト", systemImage: "eye.slash")
                }
            }

            Section("通知") {
                Toggle("新着メッセージ通知", isOn: $notifyEnabled)
                Toggle("メッセージ内容を表示", isOn: $notifyPreview)
                    .disabled(!notifyEnabled)
                Button("iOSの通知設定を開く") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("トーク") {
                Picker("文字サイズ", selection: $fontSize) {
                    ForEach(ChatFontSize.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("表示") {
                Picker("外観", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("ストレージ") {
                Button("画像キャッシュを削除") {
                    ImageStore.shared.clearCache()
                    Haptics.success()
                }
            }

            Section("情報") {
                LabeledContent("バージョン", value: version)
            }

            Section {
                Button("ログアウト", role: .destructive) { confirmSignOut = true }
                Button("アカウントを削除", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ログアウトしますか？", isPresented: $confirmSignOut) {
            Button("ログアウト", role: .destructive) { model.signOut() }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("アカウントを削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                Task {
                    do { try await model.deleteAccount() } catch { errorMessage = error.localizedDescription }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("プロフィールと友だち情報は元に戻せません。")
        }
        .alert("エラー", isPresented: Binding(present: $errorMessage), presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }
}

struct ChangeMyneIdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("@").foregroundStyle(.secondary)
                    TextField("myne.id", text: $id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    Text("a–z 0–9 . _ ・4〜20文字")
                }
            }
        }
        .navigationTitle("ID")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saving = true
                    Task {
                        do {
                            try await model.changeMyneId(id)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        saving = false
                    }
                } label: { Image(systemName: "checkmark") }
                    .disabled(saving || !AppModel.isValidMyneId(id.lowercased()))
            }
        }
        .onAppear { id = model.me?.myneId ?? "" }
    }
}

struct HiddenRoomsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.hiddenRooms) { room in
                HStack(spacing: 12) {
                    RoomAvatar(room: room, size: 48)
                    Text(model.displayName(room))
                        .font(.headline)
                        .lineLimit(1)
                    if room.isGroup { MemberCountBadge(count: room.members.count) }
                    Spacer()
                    if model.unread(room) > 0 { UnreadBadge(count: model.unread(room)) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.push(.room(room.id)) }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { model.unhide(room.id) } label: {
                        Label("再表示", systemImage: "eye")
                    }
                    .tint(.brand)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.hiddenRooms.isEmpty {
                ContentUnavailableView("非表示のトークはありません", systemImage: "eye.slash")
            }
        }
        .navigationTitle("非表示リスト")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if !model.birthdayFriends.isEmpty {
                Section {
                    ForEach(model.birthdayFriends) { user in
                        HStack(spacing: 12) {
                            AvatarView(userId: user.id, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).font(.headline)
                                Label("今日が誕生日", systemImage: "birthday.cake.fill")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                            }
                            Spacer()
                            Button {
                                Task {
                                    if let id = await model.ensureDirectRoom(with: user.id) { model.openRoom(id, composer: .card) }
                                }
                            } label: {
                                Image(systemName: "gift.fill")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.pink)
                        }
                    }
                }
            }

            Section {
                ForEach(model.notifications) { n in
                    let user = model.users[n.fromUid]
                    HStack(spacing: 12) {
                        AvatarView(userId: n.fromUid, size: 44)
                            .onTapGesture { model.presentMyScreen(n.fromUid) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(user?.name ?? "")さんが友だちに追加しました")
                                .font(.subheadline)
                                .fontWeight(n.read == true ? .regular : .semibold)
                            Text(Fmt.listTime(n.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !model.isFriend(n.fromUid) {
                            Button { model.addFriend(n.fromUid) } label: {
                                Image(systemName: "person.badge.plus")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
        .overlay {
            if model.notifications.isEmpty && model.birthdayFriends.isEmpty {
                ContentUnavailableView("お知らせはありません", systemImage: "bell")
            }
        }
        .navigationTitle("お知らせ")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.markNotificationsRead() }
    }
}
