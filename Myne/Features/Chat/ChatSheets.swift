import SwiftUI

// MARK: - 転送

struct ForwardSheet: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()

    var body: some View {
        NavigationStack {
            List(model.visibleRooms) { room in
                Button {
                    if selection.contains(room.id) { selection.remove(room.id) } else { selection.insert(room.id) }
                } label: {
                    HStack(spacing: 12) {
                        RoomAvatar(room: room, size: 44)
                        Text(model.displayName(room))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: selection.contains(room.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selection.contains(room.id) ? Color.brand : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("転送")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let targets = Array(selection)
                        Task { await model.forward(message, to: targets) }
                        Haptics.success()
                        dismiss()
                    } label: { Image(systemName: "paperplane.fill") }
                        .disabled(selection.isEmpty)
                }
            }
        }
    }
}

// MARK: - グループメンバー

struct GroupMembersView: View {
    let room: Room
    var onSelect: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var inviting = Set<String>()
    @State private var showInvite = false
    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(room.members, id: \.self) { id in
                        Button { onSelect(id) } label: {
                            if let user = model.users[id] {
                                FriendRow(user: user, isClose: model.friend(id)?.close ?? false)
                            } else {
                                HStack { AvatarView(userId: id, size: 50); Spacer() }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Button { showInvite = true } label: {
                        Label("メンバーを招待", systemImage: "person.badge.plus.fill")
                    }
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Label("グループを退会", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(model.displayName(room))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .sheet(isPresented: $showInvite) {
                NavigationStack {
                    List { FriendPicker(selection: $inviting, excluding: Set(room.members)) }
                        .navigationTitle("メンバーを招待")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    model.addMembers(Array(inviting), to: room.id)
                                    inviting = []
                                    showInvite = false
                                } label: { Image(systemName: "checkmark") }
                                    .disabled(inviting.isEmpty)
                            }
                        }
                }
            }
            .alert("グループを退会しますか？", isPresented: $confirmLeave) {
                Button("退会", role: .destructive) {
                    dismiss()
                    model.leaveGroup(room.id)
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 画像ビューア

struct ImageViewerItem: Identifiable {
    let id = UUID()
    let ids: [String]
    let index: Int
}

struct ImageViewer: View {
    let item: ImageViewerItem
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(item.ids.enumerated()), id: \.offset) { index, id in
                    FullImage(id: id).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: item.ids.count > 1 ? .always : .never))
            .ignoresSafeArea()

            GlassCircleButton(symbol: "xmark") { dismiss() }
                .environment(\.colorScheme, .dark)
                .padding(16)
        }
        .onAppear { selection = item.index }
    }
}

private struct FullImage: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { image = await ImageStore.shared.image(for: id) }
    }
}
