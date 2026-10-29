import SwiftUI

struct ChatRoomView: View {
    let roomId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chat.fontSize") private var fontSize = ChatFontSize.standard

    @State private var chat: ChatRoomModel
    @State private var draft = ""
    @State private var attachments: [UIImage] = []
    @State private var replyTo: Message?
    @State private var searching = false
    @State private var searchText = ""
    @State private var matchCursor = 0
    @State private var fieldFrame: CGRect = .zero
    @State private var width: CGFloat = 390
    @State private var flying: FlyingText?
    @State private var composer: Composer?
    @State private var forwarding: Message?
    @State private var confirmDelete: Message?
    @State private var confirmUnsend: Message?
    @State private var viewer: ImageViewerItem?
    @State private var showMembers = false
    @State private var celebrate = false
    @FocusState private var inputFocused: Bool

    init(roomId: String) {
        self.roomId = roomId
        _chat = State(initialValue: ChatRoomModel(roomId: roomId))
    }

    private var room: Room? { model.rooms.first { $0.id == roomId } }

    private var visibleMessages: [Message] {
        let cleared = model.pref(roomId).clearedAt ?? .distantPast
        let uid = model.uid ?? ""
        return chat.messages.filter { $0.sentAt > cleared && !($0.deletedFor ?? []).contains(uid) }
    }

    /// 古い順に並んだ一致メッセージ。cursor 0 が最新
    private var matches: [String] {
        guard searching, !searchText.isEmpty else { return [] }
        return visibleMessages.filter { !$0.isUnsent && ($0.text ?? "").contains(searchText) }.map(\.id)
    }

    private var currentMatch: String? {
        let m = matches
        guard !m.isEmpty else { return nil }
        let cursor = min(max(matchCursor, 0), m.count - 1)
        return m[m.count - 1 - cursor]
    }

    var body: some View {
        let messages = visibleMessages
        let items = MessageItem.build(messages)
        let hiddenId = flying.flatMap { f in messages.last(where: { $0.senderId == model.uid && $0.text == f.text })?.id }
        let current = currentMatch

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        MessageRow(
                            item: item,
                            room: room,
                            maxWidth: width * 0.8,
                            fontSize: fontSize,
                            search: searching ? searchText : "",
                            isCurrentMatch: item.id == current,
                            actions: actions
                        )
                        .opacity(item.id == hiddenId ? 0 : 1)
                        .id(item.id)
                        .onAppear {
                            if item.id == items.first?.id { chat.loadMore() }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                model.markRead(roomId)
                if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: current) { _, id in
                if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .gesture(HorizontalPanGesture(direction: .right, edgeExclusion: 28, onEnded: { x in
            if x > 90 { dismiss() }
        }))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar(
                draft: $draft,
                attachments: $attachments,
                replyTo: $replyTo,
                replyName: replyTo.flatMap { model.users[$0.senderId]?.name } ?? "",
                searching: searching,
                searchText: $searchText,
                matchLabel: matches.isEmpty ? nil : "\(min(matchCursor, matches.count - 1) + 1)/\(matches.count)",
                onOlder: { if matchCursor < matches.count - 1 { matchCursor += 1 } },
                onNewer: { if matchCursor > 0 { matchCursor -= 1 } },
                focus: $inputFocused,
                fieldFrame: $fieldFrame,
                onSend: send,
                onCompose: { composer = $0 }
            )
        }
        .overlay {
            if let flying {
                GeometryReader { geo in
                    FlyingBubble(flying: flying, container: geo.frame(in: .global), maxWidth: width * 0.8, font: fontSize.font) {
                        self.flying = nil
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if celebrate { ConfettiView().transition(.opacity) }
        }
        .onChange(of: searchText) { matchCursor = 0 }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { header }
        .background(SwipeBackEnabler())
        .onAppear(perform: appear)
        .onDisappear {
            chat.stop()
            if model.activeRoomId == roomId { model.activeRoomId = nil }
        }
        .sheet(item: $composer) { composer in
            NavigationStack { composerView(composer) }
        }
        .sheet(item: $forwarding) { ForwardSheet(message: $0) }
        .sheet(isPresented: $showMembers) {
            if let room {
                GroupMembersView(room: room) { id in
                    showMembers = false
                    model.presentMyScreen(id, afterDismissing: true)
                }
            }
        }
        .fullScreenCover(item: $viewer) { ImageViewer(item: $0) }
        .alert("メッセージを削除しますか？", isPresented: Binding(present: $confirmDelete), presenting: confirmDelete) { message in
            Button("削除", role: .destructive) { model.deleteForMe(message, in: roomId) }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("自分の画面からのみ削除されます。")
        }
        .alert("送信を取り消しますか？", isPresented: Binding(present: $confirmUnsend), presenting: confirmUnsend) { message in
            Button("送信取消", role: .destructive) { model.unsend(message, in: roomId) }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("相手の画面からも削除されます。")
        }
    }

    @ToolbarContentBuilder
    private var header: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button(action: tapTitle) {
                HStack(spacing: 6) {
                    Text(room.map { model.displayName($0) } ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    if let room, room.isGroup {
                        MemberCountBadge(count: room.members.count)
                    }
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.snappy) { searching.toggle() }
                if !searching { searchText = "" }
                inputFocused = false
            } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass")
            }
        }
    }

    private var actions: MessageActions {
        MessageActions(
            reply: { message in
                replyTo = message
                inputFocused = true
            },
            forward: { forwarding = $0 },
            delete: { confirmDelete = $0 },
            unsend: { confirmUnsend = $0 },
            openImages: { ids, index in viewer = ImageViewerItem(ids: ids, index: index) },
            vote: { message, option in model.vote(message, option: option, in: roomId) },
            openProfile: { model.presentMyScreen($0) }
        )
    }

    @ViewBuilder
    private func composerView(_ composer: Composer) -> some View {
        switch composer {
        case .poll:
            PollComposer { poll in
                Task { await model.send(roomId: roomId, kind: .poll, text: nil, poll: poll) }
            }
        case .amida:
            AmidaComposer(defaultEntries: (room?.members ?? []).compactMap { model.users[$0]?.name }) { amida in
                Task { await model.send(roomId: roomId, kind: .amida, text: nil, amida: amida) }
            }
        case .card:
            CardComposer { card in
                Task { await model.send(roomId: roomId, kind: .card, text: nil, card: card) }
            }
        }
    }

    private func tapTitle() {
        guard let room else { return }
        if room.isMine {
            if let uid = model.uid { model.presentMyScreen(uid) }
        } else if room.isGroup {
            showMembers = true
        } else if let partner = room.partner(of: model.uid) {
            model.presentMyScreen(partner)
        }
    }

    private func appear() {
        chat.start()
        model.activeRoomId = roomId
        model.markRead(roomId)
        if let pending = model.pendingComposer, pending.roomId == roomId {
            model.pendingComposer = nil
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                composer = pending.composer
            }
        }
        if let room, !room.isGroup, let partner = room.partner(of: model.uid),
           partner != model.uid, model.users[partner]?.isBirthdayToday == true, !celebrate {
            withAnimation { celebrate = true }
            Task {
                try? await Task.sleep(for: .seconds(4.5))
                withAnimation { celebrate = false }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachments
        guard !text.isEmpty || !images.isEmpty else { return }
        let reply = replyTo.map { ReplyRef(id: $0.id, senderId: $0.senderId, text: $0.previewText) }
        if !text.isEmpty && fieldFrame != .zero {
            flying = FlyingText(text: text, from: fieldFrame)
        }
        draft = ""
        attachments = []
        replyTo = nil
        Task { await model.send(roomId: roomId, text: text.isEmpty ? nil : text, images: images, replyTo: reply) }
    }
}
