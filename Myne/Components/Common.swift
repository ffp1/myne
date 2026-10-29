import SwiftUI
import CoreImage.CIFilterBuiltins

struct MemberCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color(.systemGray2)))
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.brand))
    }
}

struct PinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(45))
            .foregroundStyle(Color.onBrand)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.brand))
            .padding(2.5)
            .background(Circle().fill(Color(.systemBackground)))
    }
}

struct DateChip: View {
    let date: Date

    var body: some View {
        Text(Fmt.day(date))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Liquid Glass のセグメント切り替え
struct GlassSegmentBar<Value: Hashable & CaseIterable & RawRepresentable>: View
where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Value.allCases), id: \.self) { value in
                Button {
                    withAnimation(.snappy) { selection = value }
                } label: {
                    Text(value.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == value ? Color.brand : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == value {
                                Capsule()
                                    .fill(Color.brand.opacity(0.18))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

struct GlassCircleButton: View {
    let symbol: String
    var size: CGFloat = 44
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint == nil ? Color.primary : Color.onBrand)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: .circle)
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ConfettiView: View {
    private struct Particle {
        var x: Double
        var delay: Double
        var speed: Double
        var drift: Double
        var spin: Double
        var size: CGSize
        var color: Color
    }

    @State private var start = Date()
    @State private var particles: [Particle] = (0..<90).map { _ in
        Particle(
            x: .random(in: 0...1),
            delay: .random(in: 0...1.2),
            speed: .random(in: 180...360),
            drift: .random(in: -40...40),
            spin: .random(in: 2...8),
            size: CGSize(width: .random(in: 6...10), height: .random(in: 3...6)),
            color: [Color.brand, .pink, .yellow, .mint, .orange, .cyan].randomElement()!
        )
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in particles {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = -20 + local * p.speed
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(local * 2) * p.drift
                    var c = context
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(local * p.spin))
                    c.fill(Path(CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct FriendRow: View {
    let user: AppUser
    var isClose = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(userId: user.id, size: 50)
                .overlay(alignment: .bottomTrailing) {
                    if user.isBirthdayToday {
                        Image(systemName: "birthday.cake.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.pink))
                            .padding(2.5)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(user.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isClose {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// 友だちを複数選ぶリスト
struct FriendPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<String>
    var excluding: Set<String> = []

    var body: some View {
        ForEach(model.friendUsers.filter { !excluding.contains($0.id) }) { user in
            Button {
                if selection.contains(user.id) { selection.remove(user.id) } else { selection.insert(user.id) }
            } label: {
                HStack {
                    FriendRow(user: user)
                    Image(systemName: selection.contains(user.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(user.id) ? Color.brand : Color.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
