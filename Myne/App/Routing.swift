import SwiftUI

enum AppTab: Hashable {
    case talk, profile
}

enum ProfileField: Hashable {
    case all, icon, background, name, bio, birthday
}

enum Route: Hashable {
    case room(String)
    case friends
    case notifications
    case settings
    case store
    case editProfile(ProfileField)
    case hiddenRooms
    case myneId
}

enum TalkSheet: String, Identifiable {
    case invite, qr, newChat, newGroup
    var id: String { rawValue }
}

enum Composer: String, Identifiable {
    case poll, amida, card
    var id: String { rawValue }
}

struct IdentifiedID: Identifiable, Hashable {
    let id: String
}

struct PendingComposer {
    let roomId: String
    let composer: Composer
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .room(let id): ChatRoomView(roomId: id)
        case .friends: FriendListView()
        case .notifications: NotificationsView()
        case .settings: SettingsView()
        case .store: StoreView()
        case .editProfile(let field): EditProfileView(focus: field)
        case .hiddenRooms: HiddenRoomsView()
        case .myneId: ChangeMyneIdView()
        }
    }
}
