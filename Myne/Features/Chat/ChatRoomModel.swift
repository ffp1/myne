import SwiftUI
import FirebaseFirestore

@MainActor
@Observable
final class ChatRoomModel {
    let roomId: String
    var messages: [Message] = []
    private var limit = 80
    @ObservationIgnored private var listener: ListenerRegistration?

    init(roomId: String) {
        self.roomId = roomId
    }

    func start() {
        guard listener == nil else { return }
        listener = Firestore.firestore().collection("rooms").document(roomId).collection("messages")
            .order(by: "sentAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    guard let self, let snap else { return }
                    self.messages = snap.documents.compactMap { try? $0.data(as: Message.self) }.reversed()
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func loadMore() {
        guard messages.count >= limit else { return }
        limit += 80
        stop()
        start()
    }
}

enum BubblePosition {
    case single, first, middle, last

    var showsTail: Bool { self == .single || self == .last }
    var startsRun: Bool { self == .single || self == .first }
}

struct MessageItem: Identifiable {
    let message: Message
    let position: BubblePosition
    let showsDate: Bool
    var id: String { message.id }

    static func build(_ messages: [Message]) -> [MessageItem] {
        let cal = Calendar.current
        func joins(_ a: Message, _ b: Message) -> Bool {
            a.senderId == b.senderId && !a.isUnsent && !b.isUnsent && cal.isDate(a.sentAt, inSameDayAs: b.sentAt)
        }
        return messages.indices.map { i in
            let m = messages[i]
            let prev = i > 0 ? messages[i - 1] : nil
            let next = i + 1 < messages.count ? messages[i + 1] : nil
            let joinPrev = prev.map { joins($0, m) } ?? false
            let joinNext = next.map { joins(m, $0) } ?? false
            let position: BubblePosition = switch (joinPrev, joinNext) {
            case (false, false): .single
            case (false, true): .first
            case (true, true): .middle
            case (true, false): .last
            }
            let showsDate = prev.map { !cal.isDate($0.sentAt, inSameDayAs: m.sentAt) } ?? true
            return MessageItem(message: m, position: position, showsDate: showsDate)
        }
    }
}

/// 連続メッセージで角丸が繋がり、最後の吹き出しにだけチョボが付く
struct BubbleShape: Shape {
    var mine: Bool
    var position: BubblePosition

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 18
        let small: CGFloat = 6
        let joinsAbove = position == .middle || position == .last
        let joinsBelow = position == .first || position == .middle
        var radii = RectangleCornerRadii(topLeading: big, bottomLeading: big, bottomTrailing: big, topTrailing: big)
        if mine {
            if joinsAbove { radii.topTrailing = small }
            if joinsBelow { radii.bottomTrailing = small }
            if position.showsTail { radii.bottomTrailing = 4 }
        } else {
            if joinsAbove { radii.topLeading = small }
            if joinsBelow { radii.bottomLeading = small }
            if position.showsTail { radii.bottomLeading = 4 }
        }
        let body = Path(roundedRect: rect, cornerRadii: radii, style: .continuous)
        guard position.showsTail else { return body }

        var tail = Path()
        if mine {
            tail.move(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 15))
            tail.addQuadCurve(to: CGPoint(x: rect.maxX + 6, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY - 3))
            tail.addQuadCurve(to: CGPoint(x: rect.maxX - 13, y: rect.maxY - 0.5), control: CGPoint(x: rect.maxX - 4, y: rect.maxY + 1))
            tail.addLine(to: CGPoint(x: rect.maxX - 13, y: rect.maxY - 15))
        } else {
            tail.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 15))
            tail.addQuadCurve(to: CGPoint(x: rect.minX - 6, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY - 3))
            tail.addQuadCurve(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 0.5), control: CGPoint(x: rect.minX + 4, y: rect.maxY + 1))
            tail.addLine(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 15))
        }
        tail.closeSubpath()
        return body.union(tail)
    }
}
