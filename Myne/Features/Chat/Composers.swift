import SwiftUI

private struct ComposerToolbar: ToolbarContent {
    let canSend: Bool
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onCancel) { Image(systemName: "xmark") }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: onSend) { Image(systemName: "paperplane.fill") }
                .disabled(!canSend)
        }
    }
}

struct PollComposer: View {
    var onSend: (Poll) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]

    private var cleaned: [String] {
        options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section {
                TextField("質問", text: $question, axis: .vertical)
                    .font(.headline)
            }
            Section {
                ForEach(options.indices, id: \.self) { index in
                    TextField("選択肢 \(index + 1)", text: $options[index])
                }
                .onDelete { offsets in
                    if options.count - offsets.count >= 2 { options.remove(atOffsets: offsets) }
                }
                if options.count < 10 {
                    Button { options.append("") } label: {
                        Label("選択肢を追加", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .navigationTitle("投票")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ComposerToolbar(
                canSend: !question.trimmingCharacters(in: .whitespaces).isEmpty && cleaned.count >= 2,
                onCancel: { dismiss() },
                onSend: {
                    onSend(Poll(question: question.trimmingCharacters(in: .whitespaces), options: cleaned, votes: nil))
                    dismiss()
                }
            )
        }
    }
}

struct AmidaComposer: View {
    let defaultEntries: [String]
    var onSend: (Amida) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var entries: [String] = []
    @State private var results: [String] = []

    var body: some View {
        Form {
            Section {
                TextField("タイトル", text: $title)
                    .font(.headline)
                Stepper(value: Binding(get: { entries.count }, set: resize), in: 2...8) {
                    Label("\(entries.count)", systemImage: "person.3.fill")
                }
            }
            Section {
                ForEach(entries.indices, id: \.self) { i in
                    HStack {
                        TextField("参加者 \(i + 1)", text: $entries[i])
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                        TextField("結果 \(i + 1)", text: $results[i])
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle("あみだくじ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ComposerToolbar(
                canSend: entries.count >= 2,
                onCancel: { dismiss() },
                onSend: {
                    let names = entries.enumerated().map { i, s in s.isEmpty ? "\(i + 1)" : s }
                    let outcomes = results.enumerated().map { i, s in s.isEmpty ? "\(i + 1)" : s }
                    onSend(Amida(title: title, entries: names, results: outcomes, rungs: AmidaLadder.makeRungs(columns: names.count)))
                    dismiss()
                }
            )
        }
        .onAppear {
            guard entries.isEmpty else { return }
            entries = Array(defaultEntries.prefix(8))
            if entries.count < 2 { entries += Array(repeating: "", count: 2 - entries.count) }
            results = entries.indices.map { $0 == 0 ? "当たり" : "" }
        }
    }

    private func resize(_ count: Int) {
        while entries.count < count { entries.append(""); results.append("") }
        while entries.count > count { entries.removeLast(); results.removeLast() }
    }
}

struct CardComposer: View {
    var onSend: (BirthdayCard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var template: CardTemplate = .cake
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(CardTemplate.allCases) { t in
                            BirthdayCardView(card: BirthdayCard(template: t.rawValue, message: ""), width: 120)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(template == t ? Color.brand : .clear, lineWidth: 3)
                                }
                                .onTapGesture { withAnimation(.snappy) { template = t } }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                BirthdayCardView(card: BirthdayCard(template: template.rawValue, message: message), width: 240)
                TextField("メッセージ", text: $message, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(16)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("バースデーカード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ComposerToolbar(
                canSend: true,
                onCancel: { dismiss() },
                onSend: {
                    onSend(BirthdayCard(template: template.rawValue, message: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                    dismiss()
                }
            )
        }
    }
}
