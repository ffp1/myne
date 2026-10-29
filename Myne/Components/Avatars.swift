import SwiftUI

struct RemoteImage: View {
    let id: String?
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: id) {
                guard let id else { image = nil; return }
                if let cached = ImageStore.shared.cached(id) {
                    image = cached
                } else {
                    let loaded = await ImageStore.shared.image(for: id)
                    withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                }
            }
    }
}

struct DefaultAvatar: View {
    var symbol = "person.fill"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.brand.opacity(0.22)
                Image(systemName: symbol)
                    .font(.system(size: geo.size.width * 0.42, weight: .semibold))
                    .foregroundStyle(Color.brand)
            }
        }
    }
}

struct AvatarView: View {
    @Environment(AppModel.self) private var model
    let userId: String?
    var size: CGFloat

    var body: some View {
        let user = userId.flatMap { model.users[$0] }
        Group {
            if let icon = user?.iconId {
                RemoteImage(id: icon)
            } else {
                DefaultAvatar()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: userId) {
            if let userId { model.observeUser(userId) }
        }
    }
}

struct RoomAvatar: View {
    @Environment(AppModel.self) private var model
    let room: Room
    var size: CGFloat

    var body: some View {
        if room.isMine {
            Image(systemName: "bookmark.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.onBrand)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.brand))
        } else if room.isGroup {
            Group {
                if let icon = room.iconId {
                    RemoteImage(id: icon)
                } else {
                    DefaultAvatar(symbol: "person.2.fill")
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            AvatarView(userId: room.partner(of: model.uid), size: size)
        }
    }
}
