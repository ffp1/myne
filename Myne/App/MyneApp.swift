import SwiftUI
import FirebaseCore
import GoogleSignIn
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        BackgroundRefresh.register()
        return true
    }
}

@main
struct MyneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var model = AppModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    model.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresh.resetBaseline(model.rooms.filter { !model.pref($0.id).isMuted }.reduce(0) { $0 + model.unread($1) })
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}
