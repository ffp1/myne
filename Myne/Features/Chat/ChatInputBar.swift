import SwiftUI
import PhotosUI

enum InputBarMetrics {
    /// 入力欄1行時のコントロール高さ。下部セーフエリア込みでバー全体が約96ptになる
    static let controlHeight: CGFloat = 44
    static let maxImages = 10
}

struct ChatInputBar: View {
    @Binding var draft: String
    @Binding var attachments: [UIImage]
    @Binding var replyTo: Message?
    let replyName: String
    let searching: Bool
    @Binding var searchText: String
    let matchLabel: String?
    var onOlder: () -> Void
    var onNewer: () -> Void
    var focus: FocusState<Bool>.Binding
    @Binding var fieldFrame: CGRect
    var onSend: () -> Void
    var onCompose: (Composer) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var searchFocused: Bool
    @Namespace private var glass

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
                if !searching && (replyTo != nil || !attachments.isEmpty) {
                    tray
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if searching {
                        searchField
                    } else {
                        toolsPill
                        messageField
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(.snappy, value: searching)
        .animation(.snappy, value: attachments.count)
        .animation(.snappy, value: replyTo?.id)
        .onChange(of: pickerItems) { _, items in load(items) }
        .onChange(of: searching) { _, value in searchFocused = value }
    }

    private var toolsPill: some View {
        HStack(spacing: 0) {
            Menu {
                Button("投票", systemImage: "chart.bar.xaxis") { onCompose(.poll) }
                Button("あみだくじ", systemImage: "point.3.connected.trianglepath.dotted") { onCompose(.amida) }
                Button("バースデーカード", systemImage: "gift.fill") { onCompose(.card) }
            } label: {
                Image(systemName: "plus")
                    .frame(width: InputBarMetrics.controlHeight, height: InputBarMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, InputBarMetrics.maxImages - attachments.count),
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Image(systemName: "photo")
                    .frame(width: InputBarMetrics.controlHeight, height: InputBarMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .disabled(attachments.count >= InputBarMetrics.maxImages)
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("tools", in: glass)
    }

    private var messageField: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("Aa", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused(focus)
                .padding(.leading, 16)
                .padding(.vertical, 11)
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.onBrand)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.brand))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .padding(4)
        }
        .frame(minHeight: InputBarMetrics.controlHeight)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .glassEffectID("field", in: glass)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            fieldFrame = frame
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("トーク内を検索", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let matchLabel {
                Text(matchLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(action: onOlder) { Image(systemName: "chevron.up") }
                .disabled(matchLabel == nil)
            Button(action: onNewer) { Image(systemName: "chevron.down") }
                .disabled(matchLabel == nil)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .frame(height: InputBarMetrics.controlHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("field", in: glass)
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let replyTo {
                HStack(spacing: 10) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .foregroundStyle(Color.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(replyName).font(.caption.bold())
                        Text(replyTo.previewText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { self.replyTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        if attachments.indices.contains(index) { attachments.remove(at: index) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                }
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .glassEffectID("tray", in: glass)
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items where attachments.count < InputBarMetrics.maxImages {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    attachments.append(image)
                }
            }
            pickerItems = []
        }
    }
}

/// 送信時に入力欄の文字がそのまま吹き出しになってトークへ滑り込む
struct FlyingText: Identifiable {
    let id = UUID()
    let text: String
    let from: CGRect
}

struct FlyingBubble: View {
    let flying: FlyingText
    let container: CGRect
    let maxWidth: CGFloat
    let font: Font
    var onFinish: () -> Void
    @State private var landed = false

    var body: some View {
        Text(flying.text)
            .font(font)
            .lineLimit(8)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(landed ? Color.onBrand : Color.primary)
            .background(BubbleShape(mine: true, position: .single).fill(Color.brand).opacity(landed ? 1 : 0))
            .frame(maxWidth: landed ? maxWidth : max(40, flying.from.width - 56), alignment: landed ? .trailing : .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: landed ? .bottomTrailing : .bottomLeading)
            .padding(.leading, max(0, flying.from.minX - container.minX + 3))
            .padding(.trailing, 16)
            .padding(.bottom, landed ? container.maxY - flying.from.minY + 22 : max(0, container.maxY - flying.from.maxY + 2))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    landed = true
                } completion: {
                    onFinish()
                }
            }
    }
}
