import SwiftUI

enum FABAction: String, CaseIterable, Identifiable {
    case markAllRead, invite, newChat, newGroup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .markAllRead: "すべて既読にする"
        case .invite: "友だちを招待する"
        case .newChat: "トークルームを作る"
        case .newGroup: "グループを作る"
        }
    }

    var symbol: String {
        switch self {
        case .markAllRead: "envelope.open.fill"
        case .invite: "person.badge.plus.fill"
        case .newChat: "bubble.left.and.bubble.right.fill"
        case .newGroup: "person.2.fill"
        }
    }
}

/// 押した指を離さずに項目までスライドしても、タップで開いてから選んでも実行できる FAB
struct FABMenu: View {
    @Environment(AppModel.self) private var model
    @State private var isOpen = false
    @State private var hovered: FABAction?
    @State private var frames: [FABAction: CGRect] = [:]
    @State private var touchActive = false
    @State private var wasOpenAtTouch = false
    @Namespace private var glass

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.3))
                    .ignoresSafeArea()
                    .onTapGesture { setOpen(false) }
                    .transition(.opacity)
            }

            GlassEffectContainer(spacing: 14) {
                VStack(alignment: .trailing, spacing: 14) {
                    if isOpen {
                        ForEach(FABAction.allCases) { action in
                            item(action)
                        }
                    }
                    fab
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .coordinateSpace(.named("fab"))
        .ignoresSafeArea(.keyboard)
        .sensoryFeedback(.selection, trigger: hovered)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOpen)
    }

    private func item(_ action: FABAction) -> some View {
        let active = hovered == action
        return HStack(spacing: 12) {
            Text(action.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            Image(systemName: action.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Color.onBrand : Color.primary)
                .frame(width: 50, height: 50)
                .glassEffect(active ? Glass.regular.tint(Color.brand).interactive() : Glass.regular.interactive(), in: .circle)
                .glassEffectID(action.id, in: glass)
        }
        .scaleEffect(active ? 1.08 : 1, anchor: .trailing)
        .padding(.trailing, 5)
        .contentShape(Rectangle())
        .onTapGesture { perform(action) }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("fab"))
        } action: { frame in
            frames[action] = frame
        }
        .transition(.scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
        .animation(.snappy(duration: 0.18), value: active)
    }

    private var fab: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .rotationEffect(.degrees(isOpen ? 45 : 0))
            .foregroundStyle(Color.onBrand)
            .frame(width: 60, height: 60)
            .glassEffect(Glass.regular.tint(Color.brand).interactive(), in: .circle)
            .glassEffectID("fab", in: glass)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("fab"))
                    .onChanged { value in
                        if !touchActive {
                            touchActive = true
                            wasOpenAtTouch = isOpen
                            if !isOpen { setOpen(true) }
                        }
                        let hit = frames.first { $0.value.insetBy(dx: -6, dy: -7).contains(value.location) }?.key
                        if hit != hovered { hovered = hit }
                    }
                    .onEnded { value in
                        touchActive = false
                        if let action = hovered {
                            perform(action)
                            return
                        }
                        let moved = hypot(value.translation.width, value.translation.height) > 12
                        if wasOpenAtTouch && !moved { setOpen(false) }
                    }
            )
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen = open }
        if !open {
            frames = [:]
            hovered = nil
        }
    }

    private func perform(_ action: FABAction) {
        setOpen(false)
        switch action {
        case .markAllRead: model.markAllRead()
        case .invite: model.talkSheet = .invite
        case .newChat: model.talkSheet = .newChat
        case .newGroup: model.talkSheet = .newGroup
        }
    }
}
