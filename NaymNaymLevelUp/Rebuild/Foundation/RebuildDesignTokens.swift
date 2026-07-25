import SwiftUI

enum RebuildDesignTokens {
    enum ColorToken: CaseIterable {
        case forest700
        case forest500
        case leaf300
        case cream50
        case cream100
        case ink900
        case muted600
        case danger700
    }

    static let spacing: [CGFloat] = [4, 8, 12, 16, 24, 32]
    static let radii: [CGFloat] = [12, 20, 28]
    static let minimumActionSize: CGFloat = 48

    static let bodyFont: Font = .body
    static let headlineFont: Font = .headline
    static let titleFont: Font = .title2

    static let forest700 = Color(.sRGB, red: 31.0 / 255.0, green: 94.0 / 255.0, blue: 67.0 / 255.0, opacity: 1)
    static let forest500 = Color(.sRGB, red: 47.0 / 255.0, green: 138.0 / 255.0, blue: 97.0 / 255.0, opacity: 1)
    static let leaf300 = Color(.sRGB, red: 203.0 / 255.0, green: 234.0 / 255.0, blue: 120.0 / 255.0, opacity: 1)
    static let cream50 = Color(.sRGB, red: 1, green: 249.0 / 255.0, blue: 236.0 / 255.0, opacity: 1)
    static let cream100 = Color(.sRGB, red: 245.0 / 255.0, green: 238.0 / 255.0, blue: 220.0 / 255.0, opacity: 1)
    static let ink900 = Color(.sRGB, red: 24.0 / 255.0, green: 49.0 / 255.0, blue: 39.0 / 255.0, opacity: 1)
    static let muted600 = Color(.sRGB, red: 98.0 / 255.0, green: 113.0 / 255.0, blue: 104.0 / 255.0, opacity: 1)
    static let danger700 = Color(.sRGB, red: 163.0 / 255.0, green: 58.0 / 255.0, blue: 53.0 / 255.0, opacity: 1)

    static func color(_ token: ColorToken) -> Color {
        switch token {
        case .forest700:
            return forest700
        case .forest500:
            return forest500
        case .leaf300:
            return leaf300
        case .cream50:
            return cream50
        case .cream100:
            return cream100
        case .ink900:
            return ink900
        case .muted600:
            return muted600
        case .danger700:
            return danger700
        }
    }

    static func hex(_ token: ColorToken) -> String {
        switch token {
        case .forest700: return "#1F5E43"
        case .forest500: return "#2F8A61"
        case .leaf300: return "#CBEA78"
        case .cream50: return "#FFF9EC"
        case .cream100: return "#F5EEDC"
        case .ink900: return "#183127"
        case .muted600: return "#627168"
        case .danger700: return "#A33A35"
        }
    }
}
