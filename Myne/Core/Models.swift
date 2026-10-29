import Foundation

enum RoomType: String, Codable {
    case direct, group
}

struct LastMessage: Codable, Hashable {
    var text: String
    var senderId: String
    var sentAt: Date
}

struct Room: Codable, Identifiable, Hashable {
    var id: String
    var type: RoomType
    var members: [String]
    var name: String?
    var iconId: String?
    var lastMessage: LastMessage?
    var updatedAt: Date
    var unread: [String: Int]?
    var readAt: [String: Date]?
    var createdBy: String

    var isGroup: Bool { type == .group }

    func unreadCount(for uid: String?) -> Int {
        guard let uid else { return 0 }
        return unread?[uid] ?? 0
    }

    func partner(of uid: String?) -> String? {
        guard type == .direct else { return nil }
        return members.first { $0 != uid } ?? uid
    }
}

struct RoomPrefs: Codable, Hashable {
    var pinned: Bool?
    var pinnedAt: Date?
    var muted: Bool?
    var hidden: Bool?
    var clearedAt: Date?

    var isPinned: Bool { pinned ?? false }
    var isMuted: Bool { muted ?? false }
    var isHidden: Bool { hidden ?? false }
}

enum MessageKind: String, Codable {
    case text, poll, amida, card
}

struct ReplyRef: Codable, Hashable {
    var id: String
    var senderId: String
    var text: String
}

struct Poll: Codable, Hashable {
    var question: String
    var options: [String]
    var votes: [String: Int]?
}

struct Amida: Codable, Hashable {
    var title: String
    var entries: [String]
    var results: [String]
    var rungs: [Int]
}

struct BirthdayCard: Codable, Hashable {
    var template: String
    var message: String
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var senderId: String
    var kind: MessageKind
    var text: String?
    var imageIds: [String]?
    var replyTo: ReplyRef?
    var poll: Poll?
    var amida: Amida?
    var card: BirthdayCard?
    var sentAt: Date
    var deletedFor: [String]?
    var unsent: Bool?
    var forwarded: Bool?

    var isUnsent: Bool { unsent ?? false }
    var images: [String] { imageIds ?? [] }

    var previewText: String {
        if isUnsent { return "送信取消" }
        switch kind {
        case .text:
            if let text, !text.isEmpty { return text }
            return images.count > 1 ? "写真 \(images.count)枚" : "写真"
        case .poll: return "投票: \(poll?.question ?? "")"
        case .amida: return "あみだくじ: \(amida?.title ?? "")"
        case .card: return "バースデーカード"
        }
    }
}

struct AppUser: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var myneId: String
    var bio: String?
    var birthday: String?
    var iconId: String?
    var backgroundId: String?
    var allowIdSearch: Bool?
    var showBirthday: Bool?
    var createdAt: Date

    private var birthdayParts: (year: Int, month: Int, day: Int)? {
        guard let birthday else { return nil }
        let parts = birthday.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    var birthdayDate: Date? {
        guard let p = birthdayParts else { return nil }
        return Calendar.current.date(from: DateComponents(year: p.year, month: p.month, day: p.day))
    }

    var isBirthdayToday: Bool {
        guard showBirthday != false, let p = birthdayParts else { return false }
        let today = Calendar.current.dateComponents([.month, .day], from: Date())
        return today.month == p.month && today.day == p.day
    }

    func birthdayText(isSelf: Bool) -> String? {
        guard let birthday, isSelf || showBirthday != false else { return nil }
        return birthday.replacingOccurrences(of: "-", with: ".")
    }
}

struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var addedAt: Date
    var isClose: Bool?

    var close: Bool { isClose ?? false }
}

struct AppNotification: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var fromUid: String
    var createdAt: Date
    var read: Bool?
}
