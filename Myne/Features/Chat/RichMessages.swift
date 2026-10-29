import SwiftUI

// MARK: - 投票

struct PollCard: View {
    let poll: Poll
    let myUid: String?
    var onVote: (Int) -> Void

    var body: some View {
        let votes = poll.votes ?? [:]
        let total = max(votes.count, 1)
        let mine = myUid.flatMap { votes[$0] }

        VStack(alignment: .leading, spacing: 10) {
            Label(poll.question, systemImage: "chart.bar.xaxis")
                .font(.subheadline.bold())
            ForEach(poll.options.indices, id: \.self) { index in
                let count = votes.values.filter { $0 == index }.count
                Button { onVote(index) } label: {
                    HStack {
                        Text(poll.options[index])
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if mine == index {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                        }
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.brand.opacity(0.22))
                                .frame(width: geo.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(mine == index ? Color.brand : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: count)
            }
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                Text("\(votes.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - あみだくじ

enum AmidaLadder {
    static func makeRungs(columns: Int) -> [Int] {
        guard columns > 1 else { return [] }
        return (0..<(columns * 4 + 4)).map { _ in Int.random(in: 0..<(columns - 1)) }
    }

    static func result(for start: Int, rungs: [Int]) -> Int {
        var col = start
        for rung in rungs {
            if rung == col { col += 1 } else if rung == col - 1 { col -= 1 }
        }
        return col
    }

    static func tracePoints(start: Int, columns: Int, rungs: [Int], size: CGSize) -> [CGPoint] {
        let x = { (c: Int) in (CGFloat(c) + 0.5) * size.width / CGFloat(columns) }
        let levelY = { (k: Int) in CGFloat(k + 1) * size.height / CGFloat(rungs.count + 1) }
        var col = start
        var points = [CGPoint(x: x(col), y: 0)]
        for (k, rung) in rungs.enumerated() {
            if rung == col {
                points.append(CGPoint(x: x(col), y: levelY(k)))
                col += 1
                points.append(CGPoint(x: x(col), y: levelY(k)))
            } else if rung == col - 1 {
                points.append(CGPoint(x: x(col), y: levelY(k)))
                col -= 1
                points.append(CGPoint(x: x(col), y: levelY(k)))
            }
        }
        points.append(CGPoint(x: x(col), y: size.height))
        return points
    }
}

struct PolylineShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }
}

struct AmidaCard: View {
    let amida: Amida
    @State private var traced: Int?
    @State private var progress: CGFloat = 0

    var body: some View {
        let n = amida.entries.count
        let landed = traced.map { AmidaLadder.result(for: $0, rungs: amida.rungs) }

        VStack(alignment: .leading, spacing: 8) {
            Label(amida.title.isEmpty ? "あみだくじ" : amida.title, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.bold())

            HStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { i in
                    Button { trace(i) } label: {
                        Text(amida.entries[i])
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(traced == i ? Color.brand : Color(.tertiarySystemFill)))
                            .foregroundStyle(traced == i ? Color.onBrand : Color.primary)
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            GeometryReader { geo in
                ZStack {
                    Canvas { context, size in
                        var ladder = Path()
                        for c in 0..<n {
                            let x = (CGFloat(c) + 0.5) * size.width / CGFloat(n)
                            ladder.move(to: CGPoint(x: x, y: 0))
                            ladder.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        for (k, rung) in amida.rungs.enumerated() {
                            let y = CGFloat(k + 1) * size.height / CGFloat(amida.rungs.count + 1)
                            ladder.move(to: CGPoint(x: (CGFloat(rung) + 0.5) * size.width / CGFloat(n), y: y))
                            ladder.addLine(to: CGPoint(x: (CGFloat(rung) + 1.5) * size.width / CGFloat(n), y: y))
                        }
                        context.stroke(ladder, with: .color(.secondary.opacity(0.5)), lineWidth: 2)
                    }
                    if let traced {
                        PolylineShape(points: AmidaLadder.tracePoints(start: traced, columns: n, rungs: amida.rungs, size: geo.size))
                            .trim(from: 0, to: progress)
                            .stroke(Color.brand, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 170)

            HStack(spacing: 0) {
                ForEach(0..<min(n, amida.results.count), id: \.self) { i in
                    Text(amida.results[i])
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(landed == i && progress >= 1 ? Color.pink.opacity(0.85) : Color(.tertiarySystemFill)))
                        .foregroundStyle(landed == i && progress >= 1 ? Color.white : Color.primary)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func trace(_ start: Int) {
        progress = 0
        traced = start
        withAnimation(.easeInOut(duration: 1.6)) { progress = 1 }
    }
}

// MARK: - バースデーカード

enum CardTemplate: String, CaseIterable, Identifiable {
    case cake, gift, party, balloon
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cake: "birthday.cake.fill"
        case .gift: "gift.fill"
        case .party: "party.popper.fill"
        case .balloon: "balloon.2.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .cake: [Color(uiColor: UIColor(hex: 0xF29AB8)), Color(uiColor: UIColor(hex: 0x7153C2))]
        case .gift: [Color(uiColor: UIColor(hex: 0x4FC3C7)), Color(uiColor: UIColor(hex: 0x3B5BDB))]
        case .party: [Color(uiColor: UIColor(hex: 0xFFC94D)), Color(uiColor: UIColor(hex: 0xF0645A))]
        case .balloon: [Color(uiColor: UIColor(hex: 0xB3A7D9)), Color(uiColor: UIColor(hex: 0xF7A1C4))]
        }
    }
}

struct BirthdayCardView: View {
    let card: BirthdayCard
    var width: CGFloat = 230

    var body: some View {
        let template = CardTemplate(rawValue: card.template) ?? .cake
        VStack(spacing: 14) {
            Image(systemName: template.symbol)
                .font(.system(size: width * 0.24))
                .symbolRenderingMode(.hierarchical)
            Text("Happy Birthday")
                .font(.system(.title2, design: .rounded).bold())
            if !card.message.isEmpty {
                Text(card.message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: width, height: width * 1.3)
        .background(LinearGradient(colors: template.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
