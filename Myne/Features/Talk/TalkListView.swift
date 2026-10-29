import SwiftUI

enum RoomConfirmation: Identifiable {
    case hide([String])
    case delete([String])

    var id: String {
        switch self {
        case .hide(let ids): "hide" + ids.joined()
        case .delete(let ids): "delete" + ids.joined()
        }
    }

    var title: String {
        switch self {
        case .hide: "トークを非表示にしますか？"
        case .delete: "トークを削除しますか？"
        }
    }
}

struct TalkListView: View {
    @Environment(AppModel.self) private var model
    let scrollToTopToken: Int
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var pending: RoomConfirmation?

    private var rooms: [Room] {
        _ = model.searchIndexVersion
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.visibleRooms }
        return model.visibleRooms.filter { model.roomMatches($0, query: q) }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.talkPath) {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(rooms) { room in
                        row(room)
                            .id(room.id)
                            .tag(room.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(model.isSelectingRooms ? .active : .inactive))
                .contentMargins(.bottom, 100, for: .scrollContent)
                .onChange(of: scrollToTopToken) {
                    if !model.talkPath.isEmpty {
                        model.talkPath.removeAll()
                    } else if let first = rooms.first {
                        withAnimation(.snappy) { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: query.isEmpty) {
                if !query.isEmpty { await model.loadSearchIndex() }
            }
            .navigationTitle("トーク")
            .toolbar { toolbar }
            .toolbar(model.isSelectingRooms ? .hidden : .visible, for: .tabBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .alert(pending?.title ?? "", isPresented: Binding(present: $pending), presenting: pending) { confirmation in
                switch confirmation {
                case .hide(let ids):
                    Button("非表示") { model.hide(ids); endSelection() }
                case .delete(let ids):
                    Button("削除", role: .destructive) { model.deleteRooms(ids); endSelection() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: { confirmation in
                switch confirmation {
                case .hide: Text("友だちリストから再び開けます。")
                case .delete: Text("トーク履歴はこの端末のアカウントから削除されます。")
                }
            }
            .sheet(item: $model.talkSheet) { sheet in
                switch sheet {
                case .invite: InviteView()
                case .qr: QRSheet()
                case .newChat: NewChatView()
                case .newGroup: NewGroupView()
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ room: Room) -> some View {
        if model.isSelectingRooms {
            RoomRow(room: room)
        } else {
            let unread = model.unread(room)
            let prefs = model.pref(room.id)
            RoomRow(room: room)
                .contentShape(Rectangle())
                .onTapGesture { model.talkPath.append(.room(room.id)) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { pending = .delete([room.id]) } label: {
                        Label("削除", systemImage: "trash.fill")
                    }
                    .tint(.red)
                    Button { pending = .hide([room.id]) } label: {
                        Label("非表示", systemImage: "eye.slash")
                    }
                    .tint(.gray)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: unread > 0) {
                    if unread > 0 {
                        Button { model.markRead(room.id) } label: {
                            Label("既読", systemImage: "envelope.open.fill")
                        }
                        .tint(.brand)
                    }
                    Button { model.togglePin(room.id) } label: {
                        Label(prefs.isPinned ? "ピン留めを解除" : "ピン留め", systemImage: "pin.fill")
                    }
                    .tint(.orange)
                    Button { model.toggleMute(room.id) } label: {
                        Label(prefs.isMuted ? "通知オン" : "通知オフ", systemImage: prefs.isMuted ? "speaker.2.fill" : "speaker.slash.fill")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    if unread > 0 {
                        Button("既読にする", systemImage: "envelope.open.fill") { model.markRead(room.id) }
                    }
                    Button(prefs.isPinned ? "ピン留めを解除" : "ピン留め", systemImage: "pin.fill") { model.togglePin(room.id) }
                    Button(prefs.isMuted ? "通知オン" : "通知オフ", systemImage: prefs.isMuted ? "speaker.2.fill" : "speaker.slash.fill") {
                        model.toggleMute(room.id)
                    }
                    Button("非表示", systemImage: "eye.slash") { pending = .hide([room.id]) }
                    Button("削除", systemImage: "trash.fill", role: .destructive) { pending = .delete([room.id]) }
                } preview: {
                    RoomPreview(room: room, model: model)
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isSelectingRooms {
            ToolbarItem(placement: .topBarTrailing) {
                Button { endSelection() } label: { Image(systemName: "checkmark") }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { model.markRead(Array(selection)); endSelection() } label: {
                    Label("既読", systemImage: "envelope.open.fill")
                }
                Spacer()
                Button { pending = .hide(Array(selection)) } label: {
                    Label("非表示", systemImage: "eye.slash")
                }
                Button(role: .destructive) { pending = .delete(Array(selection)) } label: {
                    Label("削除", systemImage: "trash.fill")
                }
                .tint(.red)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("トークルームを選択", systemImage: "checkmark.circle") {
                        selection = []
                        withAnimation { model.isSelectingRooms = true }
                    }
                    Button("友だちを招待", systemImage: "person.badge.plus.fill") { model.talkSheet = .invite }
                    Button("QRコードで招待", systemImage: "qrcode.viewfinder") { model.talkSheet = .qr }
                } label: {
                    Image(systemName: "ellipsis")
                }
                Button { model.push(.notifications) } label: { Image(systemName: model.bellSymbol) }
                Button { model.push(.settings) } label: { Image(systemName: "gearshape") }
            }
        }
    }

    private func endSelection() {
        selection = []
        withAnimation { model.isSelectingRooms = false }
    }
}
