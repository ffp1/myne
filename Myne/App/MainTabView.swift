import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var talkTopToken = 0
    @State private var profileTopToken = 0

    var body: some View {
        @Bindable var model = model
        let selection = Binding<AppTab>(
            get: { model.selectedTab },
            set: { tab in
                if tab == model.selectedTab {
                    switch tab {
                    case .talk: talkTopToken += 1
                    case .profile: profileTopToken += 1
                    }
                }
                model.selectedTab = tab
            }
        )

        TabView(selection: selection) {
            Tab(value: AppTab.talk) {
                TalkListView(scrollToTopToken: talkTopToken)
            } label: {
                Label("トーク", systemImage: model.selectedTab == .talk ? "message.fill" : "message")
                    .environment(\.symbolVariants, .none)
            }
            .badge(model.totalUnread)

            Tab(value: AppTab.profile) {
                ProfileTabView(scrollToTopToken: profileTopToken)
            } label: {
                Label("プロフィール", systemImage: model.selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                    .environment(\.symbolVariants, .none)
            }
        }
        .overlay {
            if model.selectedTab == .talk && model.talkPath.isEmpty && !model.isSelectingRooms {
                FABMenu()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.talkPath.isEmpty)
        .fullScreenCover(item: $model.myScreen) { item in
            MyScreenView(userId: item.id)
                .environment(model)
        }
    }
}
