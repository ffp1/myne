import SwiftUI

struct FriendListView: View {
    enum Segment: String, CaseIterable { case friends = "友だち", groups = "グループ" }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var segment: Segment = .friends
    @State private var query = ""
    @State private var removing: AppUser?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var friends: [AppUser] {
        _ = model.searchIndexVersion
        guard !trimmed.isEmpty else { return model.friendUsers }
        return model.friendUsers.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.myneId.localizedCaseInsensitiveContains(trimmed)
                || model.messagesMatch(roomId: model.directRoomId(with: $0.id), query: trimmed)
        }
    }

    private var groups: [Room] {
        _ = model.searchIndexVersion
        guard !trimmed.isEmpty else { return model.groupRooms }
        return model.groupRooms.filter { model.roomMatches($0, query: trimmed) }
    }

    var body: some View {
        List {
            switch segment {
            case .friends:
                ForEach(friends) { user in
                    FriendRow(user: user, isClose: model.friend(user.id)?.close ?? false)
                        .onTapGesture { model.presentMyScreen(user.id) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { removing = user } label: {
                                Label("削除", systemImage: "person.crop.circle.badge.minus")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { model.toggleClose(user.id) } label: {
                                Label("親しい友だち", systemImage: "star.fill")
                            }
                            .tint(.yellow)
                        }
                }
            case .groups:
                ForEach(groups) { room in
                    HStack(spacing: 12) {
                        RoomAvatar(room: room, size: 50)
                        Text(model.displayName(room))
                            .font(.headline)
                            .lineLimit(1)
                        MemberCountBadge(count: room.members.count)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { model.profilePath.append(.room(room.id)) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if segment == .friends && friends.isEmpty && trimmed.isEmpty {
                ContentUnavailableView {
                    Label("友だちがいません", systemImage: "person.2.slash")
                } actions: {
                    Button("友だちを招待") { model.selectedTab = .talk; model.talkSheet = .invite }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassSegmentBar(selection: $segment)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .task(id: trimmed.isEmpty) {
            if !trimmed.isEmpty { await model.loadSearchIndex() }
        }
        .navigationTitle(segment.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
        }
        .background(SwipeBackEnabler())
        .alert("友だちから削除しますか？", isPresented: Binding(present: $removing), presenting: removing) { user in
            Button("削除", role: .destructive) { model.removeFriend(user.id) }
            Button("キャンセル", role: .cancel) {}
        } message: { user in
            Text(user.name)
        }
    }
}
