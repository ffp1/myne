import SwiftUI
import PhotosUI
import FirebaseFirestore

struct EditProfileView: View {
    let focus: ProfileField
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
    @State private var iconItem: PhotosPickerItem?
    @State private var backgroundItem: PhotosPickerItem?
    @State private var showIconPicker = false
    @State private var showBackgroundPicker = false
    @State private var uploading = false
    @State private var loaded = false
    @FocusState private var focused: ProfileField?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    Button { showIconPicker = true } label: {
                        AvatarView(userId: model.uid, size: 104)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.onBrand)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.brand))
                                    .padding(2.5)
                                    .background(Circle().fill(Color(.systemBackground)))
                            }
                    }
                    .buttonStyle(.plain)

                    Button { showBackgroundPicker = true } label: {
                        ZStack {
                            if let id = model.me?.backgroundId {
                                RemoteImage(id: id)
                            } else {
                                LinearGradient(colors: [.myScreenFallbackTop, .myScreenFallbackBottom], startPoint: .top, endPoint: .bottom)
                            }
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular, in: .circle)
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if uploading { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("名前") {
                TextField("名前", text: $name)
                    .focused($focused, equals: .name)
            }

            Section("マイバイオ") {
                TextField("マイバイオ", text: $bio, axis: .vertical)
                    .lineLimit(2...8)
                    .focused($focused, equals: .bio)
            }

            Section("誕生日") {
                Toggle(isOn: $hasBirthday.animation()) {
                    Label("誕生日", systemImage: "birthday.cake.fill")
                }
                if hasBirthday {
                    DatePicker("", selection: $birthday, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                }
            }
        }
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Image(systemName: "checkmark") }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .photosPicker(isPresented: $showIconPicker, selection: $iconItem, matching: .images)
        .photosPicker(isPresented: $showBackgroundPicker, selection: $backgroundItem, matching: .images)
        .onChange(of: iconItem) { _, item in upload(item) { await model.setIcon($0) } }
        .onChange(of: backgroundItem) { _, item in upload(item) { await model.setBackground($0) } }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let me = model.me else { return }
        loaded = true
        name = me.name
        bio = me.bio ?? ""
        if let date = me.birthdayDate {
            hasBirthday = true
            birthday = date
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            switch focus {
            case .icon: showIconPicker = true
            case .background: showBackgroundPicker = true
            case .name: focused = .name
            case .bio: focused = .bio
            case .birthday: withAnimation { hasBirthday = true }
            case .all: break
            }
        }
    }

    private func upload(_ item: PhotosPickerItem?, _ action: @escaping (UIImage) async -> Void) {
        guard let item else { return }
        uploading = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                await action(image)
            }
            uploading = false
        }
    }

    private func save() {
        model.updateProfile([
            "name": name.trimmingCharacters(in: .whitespaces),
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "birthday": hasBirthday ? Fmt.storage.string(from: birthday) as Any : FieldValue.delete() as Any,
        ])
        Haptics.success()
        dismiss()
    }
}

struct StoreView: View {
    enum Segment: String, CaseIterable { case stamps = "スタンプ", wallpapers = "壁紙" }
    @State private var segment: Segment = .stamps

    var body: some View {
        VStack(spacing: 0) {
            GlassSegmentBar(selection: $segment)
            Spacer()
            ContentUnavailableView(
                "準備中",
                systemImage: segment == .stamps ? "face.smiling.inverse" : "photo.stack"
            )
            Spacer()
        }
        .navigationTitle("ストア")
        .navigationBarTitleDisplayMode(.inline)
    }
}
