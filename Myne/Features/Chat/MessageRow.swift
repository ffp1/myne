import SwiftUI

struct MessageActions {
    var reply: (Message) -> Void
    var forward: (Message) -> Void
    var delete: (Message) -> Void
    var unsend: (Message) -> Void
    var openImages: ([String], Int) -> Void
    var vote: (Message, Int) -> Void
    var openProfile: (String) -> Void
}

struct MessageRow: View {
    @Environment(AppModel.self) private var model
    let item: MessageItem
    let room: Room?
    let maxWidth: CGFloat
    var fontSize: ChatFontSize = .standard
    var search: String = ""
    var isCurrentMatch = false
    var actions: MessageActions?
    @State private var dragX: CGFloat = 0

    private var message: Message { item.message }
    private var mine: Bool { message.senderId == model.uid }
    private var avatarSize: CGFloat { 34 }

    var body: some View {
        VStack(spacing: 4) {
            if item.showsDate {
                DateChip(date: message.sentAt)
                    .padding(.vertical, 10)
            }
            if message.isUnsent {
                unsentLine
            } else {
                content
            }
        }
        .padding(.top, item.position.startsRun && !item.showsDate ? 8 : 0)
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine {
                Spacer(minLength: 0)
                meta
                bubbleStack
            } else {
                avatarSlot
                bubbleStack
                meta
                Spacer(minLength: 0)
            }
        }
        .offset(x: dragX)
        .background(alignment: .trailing) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .foregroundStyle(Color.brand)
                .opacity(min(1, Double(-dragX / 50)))
                .padding(.trailing, 6)
        }
        .gesture(HorizontalPanGesture(
            direction: .left,
            onChanged: { x in
                guard actions != nil else { return }
                dragX = max(min(x, 0), -80) * 0.8
            },
            onEnded: { x in
                if x < -55, let actions {
                    Haptics.tap()
                    actions.reply(message)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragX = 0 }
            }
        ))
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if item.position.showsTail {
            AvatarView(userId: message.senderId, size: avatarSize)
                .onTapGesture { actions?.openProfile(message.senderId) }
        } else {
            Color.clear.frame(width: avatarSize, height: 1)
        }
    }

    private var bubbleStack: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if !mine && room?.isGroup == true && item.position.startsRun {
                Text(model.users[message.senderId]?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            if !message.images.isEmpty {
                ImageGrid(ids: message.images) { actions?.openImages(message.images, $0) }
                    .frame(width: min(maxWidth, 250))
            }
            richContent
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            if let actions {
                Button("返信", systemImage: "arrowshape.turn.up.left") { actions.reply(message) }
                if let text = message.text, !text.isEmpty {
                    Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                }
                Button("転送", systemImage: "arrowshape.turn.up.right") { actions.forward(message) }
                Button("削除", systemImage: "trash", role: .destructive) { actions.delete(message) }
                if mine {
                    Button("送信取消", systemImage: "arrow.uturn.backward", role: .destructive) { actions.unsend(message) }
                }
            }
        }
    }

    @ViewBuilder
    private var richContent: some View {
        switch message.kind {
        case .text:
            if let text = message.text, !text.isEmpty { textBubble(text) }
        case .poll:
            if let poll = message.poll {
                PollCard(poll: poll, myUid: model.uid) { actions?.vote(message, $0) }
            }
        case .amida:
            if let amida = message.amida { AmidaCard(amida: amida) }
        case .card:
            if let card = message.card { BirthdayCardView(card: card) }
        }
    }

    private func textBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply = message.replyTo {
                ReplyQuote(reply: reply)
            }
            Text(Self.highlight(text, search))
                .font(fontSize.font)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .foregroundStyle(mine ? Color.onBrand : Color.primary)
        .background(BubbleShape(mine: mine, position: item.position).fill(mine ? Color.brand : Color.otherBubble))
        .overlay {
            if isCurrentMatch {
                BubbleShape(mine: mine, position: item.position).stroke(Color.yellow, lineWidth: 2.5)
            }
        }
        .frame(maxWidth: maxWidth, alignment: mine ? .trailing : .leading)
    }

    private var meta: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 1) {
            if let read = readLabel { Text(read) }
            Text(Fmt.hm.string(from: message.sentAt))
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }

    private var readLabel: String? {
        guard mine, let room else { return nil }
        let count = room.members
            .filter { $0 != model.uid && (room.readAt?[$0] ?? .distantPast) >= message.sentAt }
            .count
        guard count > 0 else { return nil }
        return room.isGroup ? "既読 \(count)" : "既読"
    }

    private var unsentLine: some View {
        let name = model.users[message.senderId]?.name ?? ""
        return Text(mine ? "送信を取り消しました" : "\(name)が送信を取り消しました")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    static func highlight(_ text: String, _ query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var searchRange = result.startIndex..<result.endIndex
        while let range = result[searchRange].range(of: query) {
            result[range].backgroundColor = Color.yellow.opacity(0.7)
            result[range].foregroundColor = Color.black
            searchRange = range.upperBound..<result.endIndex
        }
        return result
    }
}

struct ReplyQuote: View {
    @Environment(AppModel.self) private var model
    let reply: ReplyRef

    var body: some View {
        HStack(spacing: 8) {
            Capsule().frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.users[reply.senderId]?.name ?? "")
                    .font(.caption.bold())
                Text(reply.text)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .opacity(0.75)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ImageGrid: View {
    let ids: [String]
    var onTap: (Int) -> Void

    var body: some View {
        let columns = ids.count == 1 ? 1 : (ids.count == 2 || ids.count == 4 ? 2 : 3)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columns), spacing: 3) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                Color.clear
                    .aspectRatio(ids.count == 1 ? 0.8 : 1, contentMode: .fit)
                    .overlay { RemoteImage(id: id) }
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(index) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
