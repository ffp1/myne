import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    static let brand = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xB3A7D9) : UIColor(hex: 0x7153C2) })
    static let onBrand = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1E1535) : .white })
    static let otherBubble = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2C2B33) : UIColor(hex: 0xEFEDF5) })
    static let myScreenFallbackTop = Color(uiColor: UIColor(hex: 0x2A1F4D))
    static let myScreenFallbackBottom = Color(uiColor: UIColor(hex: 0x7153C2))
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ChatFontSize: String, CaseIterable, Identifiable {
    case standard, large, xlarge
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "標準"
        case .large: "大"
        case .xlarge: "特大"
        }
    }

    var font: Font {
        switch self {
        case .standard: .body
        case .large: .title3
        case .xlarge: .title2
        }
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension Binding where Value == Bool {
    init<T>(present value: Binding<T?>) {
        self.init(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
