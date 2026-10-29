import SwiftUI
import PhotosUI

enum AuthErrorText {
    static func message(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case 17004, 17009: return "メールアドレスまたはパスワードが違います"
        case 17007: return "このメールアドレスは既に登録されています"
        case 17008: return "メールアドレスの形式が正しくありません"
        case 17011: return "アカウントが見つかりません"
        case 17020: return "ネットワークに接続できません"
        case 17026: return "パスワードは6文字以上にしてください"
        case -5: return ""
        default: return error.localizedDescription
        }
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var resetSent = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.brand.opacity(0.45), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.brand)
                    .symbolEffect(.bounce, value: isSignUp)
                Text("Myne")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Spacer()

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        TextField("メールアドレス", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        SecureField("パスワード", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Group {
                        if busy { ProgressView() } else { Text(isSignUp ? "新規登録" : "ログイン") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy || email.isEmpty || password.count < 6)

                Button(action: google) {
                    Label("Googleで続ける", systemImage: "g.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.glass)
                .disabled(busy)

                HStack {
                    Button(isSignUp ? "ログイン" : "新規登録") {
                        withAnimation(.snappy) { isSignUp.toggle(); errorMessage = nil }
                    }
                    if !isSignUp {
                        Spacer()
                        Button(resetSent ? "送信しました" : "パスワードを忘れた") { reset() }
                            .disabled(email.isEmpty || resetSent)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private func submit() {
        busy = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await model.signUp(email: email, password: password)
                } else {
                    try await model.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = AuthErrorText.message(error)
            }
            busy = false
        }
    }

    private func google() {
        busy = true
        errorMessage = nil
        Task {
            do { try await model.signInWithGoogle() } catch { errorMessage = AuthErrorText.message(error) }
            busy = false
        }
    }

    private func reset() {
        Task {
            do {
                try await model.resetPassword(email: email)
                resetSent = true
            } catch {
                errorMessage = AuthErrorText.message(error)
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var myneId = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
    @State private var iconItem: PhotosPickerItem?
    @State private var icon: UIImage?
    @State private var busy = false
    @State private var errorMessage: String?

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && AppModel.isValidMyneId(myneId.lowercased())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $iconItem, matching: .images) {
                        Group {
                            if let icon {
                                Image(uiImage: icon).resizable().scaledToFill()
                            } else {
                                DefaultAvatar(symbol: "camera.fill")
                            }
                        }
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("名前", text: $name)
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("ユーザーID", text: $myneId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    Text("IDは a–z 0–9 . _ の4〜20文字。友だち検索に使われます。")
                }
                Section {
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
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("プロフィール")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.signOut() } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) {
                        if busy { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .disabled(!valid || busy)
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
        busy = true
        errorMessage = nil
        Task {
            do {
                try await model.createProfile(
                    name: name.trimmingCharacters(in: .whitespaces),
                    myneId: myneId,
                    birthday: hasBirthday ? birthday : nil,
                    icon: icon
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}
