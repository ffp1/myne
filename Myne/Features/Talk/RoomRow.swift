import SwiftUI
import FirebaseFirestore

struct RoomRow: View {
    @Environment(AppModel.self) private var model
    let room: Room

    var body: some View {
        let prefs = model.pref(room.id)
        let unread = model.unread(room)
        let cleared = prefs.clearedAt ?? .distantPast
        let last = room.lastMessage.flatMap { $0.sentAt > cleared ? $0 : nil }

        HStack(spacing: 12) {
            RoomAvatar(room: room, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if prefs.isPinned {
                        PinBadge().offset(x: 4, y: 4)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName(room))
                        .font(.headline)
                        .lineLimit(1)
                    if room.isGroup {
                        MemberCountBadge(count: room.members.count)
                    }
                    if prefs.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let last {
                    HStack(spacing: 5) {
                        AvatarView(userId: last.senderId, size: 16)
                        Text(last.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(Fmt.listTime(last?.sentAt ?? room.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                UnreadBadge(count: unread)
                    .opacity(unread > 0 ? 1 : 0)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 長押し時に出すトークのプレビュー
struct RoomPreview: View {
    let room: Room
    let model: AppModel
    @State private var messages: [Message] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoomAvatar(room: room, size: 32)
                Text(model.displayName(room))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(MessageItem.build(messages)) { item in
                        MessageRow(item: item, room: room, maxWidth: 250)
                    }
                }
                .padding(10)
            }
            .defaultScrollAnchor(.bottom)
        }
        .frame(width: 330, height: 460)
        .background(Color(.systemBackground))
        .environment(model)
        .task {
            let cleared = model.pref(room.id).clearedAt ?? .distantPast
            let uid = model.uid ?? ""
            let snap = try? await model.db.collection("rooms").document(room.id).collection("messages")
                .order(by: "sentAt", descending: true).limit(to: 30).getDocuments()
            messages = (snap?.documents.compactMap { try? $0.data(as: Message.self) } ?? [])
                .filter { $0.sentAt > cleared && !($0.deletedFor ?? []).contains(uid) }
                .reversed()
        }
    }
}
