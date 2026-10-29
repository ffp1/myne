import SwiftUI
import PhotosUI

struct MyScreenView: View {
    enum Mode { case normal, icon, bio, clear }

    let userId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .normal
    @State private var iconItem: PhotosPickerItem?
    @State private var celebrate = false

    private var user: AppUser? { model.users[userId] }
    private var isMe: Bool { userId == model.uid }
    private var isFriend: Bool { model.isFriend(userId) }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if mode == .normal { withAnimation(.easeInOut(duration: 0.35)) { mode = .clear } }
                }

            if mode != .clear {
                profile
                    .transition(.opacity)
            }

            if mode == .icon { iconOverlay.transition(.opacity) }
            if mode == .bio { bioOverlay.transition(.opacity) }
            if celebrate { ConfettiView() }
        }
        .overlay(alignment: .top) { topBar }
        .statusBarHidden(mode == .clear)
        .task {
            model.observeUser(userId)
            if user?.isBirthdayToday == true {
                celebrate = true
                try? await Task.sleep(for: .seconds(4.5))
                withAnimation { celebrate = false }
            }
        }
        .onChange(of: iconItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await model.setIcon(image)
                }
            }
        }
    }

    // MARK: - Layers

    private var background: some View {
        ZStack {
            if let id = user?.backgroundId {
                RemoteImage(id: id)
                    .blur(radius: mode == .clear ? 0 : 1.5)
            } else {
                LinearGradient(colors: [.myScreenFallbackTop, .myScreenFallbackBottom], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(mode == .clear ? 0 : 0.42)
        }
        .animation(.easeInOut(duration: 0.35), value: mode)
    }

    private var profile: some View {
        VStack(spacing: 10) {
            AvatarView(userId: userId, size: 128)
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .icon } }
                .padding(.bottom, 6)

            Text(user?.name ?? "")
                .font(.title2.bold())

            if let birthday = user?.birthdayText(isSelf: isMe) {
                Label(birthday, systemImage: "birthday.cake.fill")
                    .font(.subheadline.monospacedDigit())
                    .opacity(0.9)
            }

            if let bio = user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(0.85)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { mode = .bio } }
            }

            if !isMe && !isFriend {
                Button { model.addFriend(userId) } label: {
                    Label("友だちになる", systemImage: "person.badge.plus")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 14)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
        .offset(y: 56)
    }

    private var iconOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 28) {
                AvatarView(userId: userId, size: 290)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                    .onTapGesture { close() }
                if isMe {
                    PhotosPicker(selection: $iconItem, matching: .images) {
                        Label("アイコンを変更", systemImage: "camera.fill")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var bioOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.5))
                .ignoresSafeArea()
            ScrollView {
                Text(user?.bio ?? "")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 76)
                    .padding(.bottom, 40)
                    .textSelection(.enabled)
            }
            .onTapGesture { close() }
        }
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack {
            GlassCircleButton(symbol: "xmark") {
                if mode == .normal { dismiss() } else { close() }
            }
            Spacer()
            if mode == .normal && !isMe {
                if isFriend {
                    GlassCircleButton(symbol: "message") { openChat() }
                } else {
                    GlassCircleButton(symbol: "person.badge.plus", tint: .brand) { model.addFriend(userId) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .environment(\.colorScheme, .dark)
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.3)) { mode = .normal }
    }

    private func openChat() {
        Task {
            if let id = await model.ensureDirectRoom(with: userId) {
                model.openRoom(id)
            }
        }
    }
}
