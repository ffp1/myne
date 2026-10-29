import SwiftUI

struct ProfileTabView: View {
    @Environment(AppModel.self) private var model
    let scrollToTopToken: Int

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.profilePath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        ProfileCard()
                            .id("top")
                        if !model.birthdayFriends.isEmpty {
                            BirthdayStrip(users: model.birthdayFriends)
                        }
                        FriendsPreview()
                        StoreEntry()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .onChange(of: scrollToTopToken) {
                    if !model.profilePath.isEmpty {
                        model.profilePath.removeAll()
                    } else {
                        withAnimation(.snappy) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { model.push(.notifications) } label: { Image(systemName: model.bellSymbol) }
                    Button { model.push(.settings) } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me
        let bio = me?.bio ?? ""

        VStack(alignment: .leading, spacing: 6) {
            AvatarView(userId: me?.id, size: 96)
                .onTapGesture { edit(.icon) }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

            Text(me?.name ?? "")
                .font(.title2.bold())
                .lineLimit(1)
                .onTapGesture { edit(.name) }

            HStack(spacing: 12) {
                Text(bio.isEmpty ? "マイバイオ" : bio)
                    .font(.subheadline)
                    .foregroundStyle(bio.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .onTapGesture { edit(.bio) }
                if let birthday = me?.birthdayText(isSelf: true) {
                    Label(birthday, systemImage: "birthday.cake")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .onTapGesture { edit(.birthday) }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if let background = me?.backgroundId {
                    RemoteImage(id: background)
                        .scaleEffect(1.4)
                        .blur(radius: 18)
                } else {
                    LinearGradient(colors: [Color.brand.opacity(0.55), Color.brand.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Color(.systemBackground).opacity(0.55)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {
            if let id = me?.id { model.presentMyScreen(id) }
        }
        .overlay(alignment: .topTrailing) {
            GlassCircleButton(symbol: "pencil.and.outline", size: 40) { edit(.all) }
                .padding(12)
        }
        .padding(.horizontal, 16)
    }

    private func edit(_ field: ProfileField) {
        model.profilePath.append(.editProfile(field))
    }
}

struct BirthdayStrip: View {
    @Environment(AppModel.self) private var model
    let users: [AppUser]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(users) { user in
                    Button {
                        Task {
                            if let id = await model.ensureDirectRoom(with: user.id) { model.openRoom(id, composer: .card) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(userId: user.id, size: 40)
                            Text(user.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "gift.fill")
                                .foregroundStyle(.pink)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 14)
                        .padding(.vertical, 6)
                        .glassEffect(Glass.regular.tint(Color.pink.opacity(0.25)).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "birthday.cake.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.pink))
                .offset(x: 10, y: -8)
                .allowsHitTesting(false)
        }
    }
}

struct FriendsPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.featuredFriends) { user in
                Button { model.presentMyScreen(user.id) } label: {
                    FriendRow(user: user, isClose: model.friend(user.id)?.close ?? false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Button { model.profilePath.append(.friends) } label: {
                Label("もっと見る", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

struct StoreEntry: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.profilePath.append(.store) } label: {
            HStack(spacing: 14) {
                Image(systemName: "bag.fill")
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.brand.opacity(0.15)))
                Text("スタンプ・壁紙ストア")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .padding(.horizontal, 16)
    }
}
