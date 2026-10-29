import Foundation
import UserNotifications
import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore

/// APNs が使えない（SideStore の無料署名）ため、ローカル通知で代替する
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(thread: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// アプリ停止中は iOS が許す範囲（おおむね15分以上間隔）で未読を確認する
enum BackgroundRefresh {
    static let identifier = "com.myne.app.refresh"
    private static let lastUnreadKey = "bg.lastUnread"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task {
                await check()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func check() async {
        guard let uid = Auth.auth().currentUser?.uid,
              UserDefaults.standard.object(forKey: "notify.enabled") as? Bool ?? true else { return }
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("rooms").whereField("members", arrayContains: uid).getDocuments() else { return }
        let prefs = try? await db.collection("users").document(uid).collection("roomPrefs").getDocuments()
        let muted = Set(prefs?.documents.filter { ($0.get("muted") as? Bool) == true }.map(\.documentID) ?? [])
        let rooms = snap.documents.compactMap { try? $0.data(as: Room.self) }
        let all = rooms.reduce(0) { $0 + $1.unreadCount(for: uid) }
        let notifiable = rooms.filter { !muted.contains($0.id) }.reduce(0) { $0 + $1.unreadCount(for: uid) }
        let last = UserDefaults.standard.integer(forKey: lastUnreadKey)
        UserDefaults.standard.set(notifiable, forKey: lastUnreadKey)
        try? await UNUserNotificationCenter.current().setBadgeCount(all)
        if notifiable > last {
            post(notifiable)
        }
    }

    private static func post(_ count: Int) {
        NotificationPresenter.post(thread: "background", title: "Myne", body: "\(count)件の未読メッセージがあります")
    }

    static func resetBaseline(_ count: Int) {
        UserDefaults.standard.set(count, forKey: lastUnreadKey)
    }
}
