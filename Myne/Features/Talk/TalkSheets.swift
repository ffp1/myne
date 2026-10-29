import SwiftUI
import PhotosUI
import VisionKit

// MARK: - 友だちを招待 / ID検索

struct InviteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var result: AppUser?
    @State private var notFound = false
    @State private var searching = false

    private var inviteURL: URL { URL(string: "myne://add/\(model.uid ?? "")")! }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "at")
                            .foregroundStyle(.secondary)
                        TextField("ユーザーID", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit(search)
                        if searching { ProgressView() }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    if let result {
                        Button { model.presentMyScreen(result.id, afterDismissing: true) } label: {
                            FriendRow(user: result)
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    } else if notFound {
                        Label("見つかりませんでした", systemImage: "person.fill.questionmark")
                            .foregroundStyle(.secondary)
                    }

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            ShareLink(item: inviteURL, message: Text("Myneで友だちになろう！ ID: @\(model.me?.myneId ?? "")")) {
                                Label("招待リンク", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                            }
                            .buttonStyle(.glassProminent)

                            Button { model.talkSheet = .qr } label: {
                                Label("QRコード", systemImage: "qrcode.viewfinder")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                            }
                            .buttonStyle(.glass)
                        }
                    }

                    if let id = model.me?.myneId {
                        Button { UIPasteboard.general.string = id; Haptics.success() } label: {
                            Label("@\(id)", systemImage: "doc.on.doc")
                                .font(.subheadline.monospaced())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("友だちを招待")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func search() {
        guard !query.isEmpty else { return }
        searching = true
        Task {
            result = await model.findUser(myneId: query)
            notFound = result == nil
            searching = false
        }
    }
}

// MARK: - QRコード

struct QRSheet: View {
    enum Mode: String, CaseIterable { case mine = "マイQR", scan = "読み取り" }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .mine

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlassSegmentBar(selection: $mode)
                Spacer()
                switch mode {
                case .mine: myCode
                case .scan: scanner
                }
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private var myCode: some View {
        VStack(spacing: 16) {
            AvatarView(userId: model.uid, size: 72)
            Text(model.me?.name ?? "")
                .font(.title3.bold())
            if let image = QRCode.image(for: "myne://add/\(model.uid ?? "")") {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if DataScannerViewController.isSupported {
            QRScannerView { payload in
                guard let url = URL(string: payload), url.scheme == "myne", url.host == "add" else { return }
                Haptics.success()
                model.presentMyScreen(url.lastPathComponent, afterDismissing: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(16)
        } else {
            ContentUnavailableView("カメラを使用できません", systemImage: "camera.fill")
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        DispatchQueue.main.async { try? controller.startScanning() }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue {
                    done = true
                    onFound(payload)
                    return
                }
            }
        }
    }
}

// MARK: - トークルームを作る（1対1）

struct NewChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.friendUsers.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { user in
                    Button {
                        Task {
                            if let id = await model.ensureDirectRoom(with: user.id) { model.openRoom(id) }
                        }
                    } label: {
                        FriendRow(user: user)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.friends.isEmpty {
                    ContentUnavailableView("友だちがいません", systemImage: "person.2.slash")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("トークルームを作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

// MARK: - グループを作る

struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection = Set<String>()
    @State private var iconItem: PhotosPickerItem?
    @State private var icon: UIImage?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PhotosPicker(selection: $iconItem, matching: .images) {
                            Group {
                                if let icon {
                                    Image(uiImage: icon).resizable().scaledToFill()
                                } else {
                                    DefaultAvatar(symbol: "camera.fill")
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                        }
                        TextField("グループ名", text: $name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    FriendPicker(selection: $selection)
                } header: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("\(selection.count)")
                    }
                }
            }
            .navigationTitle("グループを作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { create() } label: { Image(systemName: "checkmark") }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selection.isEmpty || creating)
                }
            }
            .onChange(of: iconItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { icon = UIImage(data: data) }
                }
            }
        }
    }

    private func create() {
        creating = true
        Task {
            let id = await model.createGroup(name: name.trimmingCharacters(in: .whitespaces), members: Array(selection), icon: icon)
            creating = false
            if let id { model.openRoom(id) }
        }
    }
}
