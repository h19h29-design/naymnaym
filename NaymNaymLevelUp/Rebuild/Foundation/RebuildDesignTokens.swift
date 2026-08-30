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

    enum SemanticRole: CaseIterable, Hashable {
        case growth
        case mission
        case appetite
        case nutrition
        case schedule
        case safety
        case background
    }

    struct SemanticPalette {
        let foreground: Color
        let surface: Color
        let foregroundHex: String
        let surfaceHex: String
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

    static func semanticPalette(_ role: SemanticRole) -> SemanticPalette {
        switch role {
        case .growth:
            return SemanticPalette(
                foreground: .white,
                surface: forest700,
                foregroundHex: "#FFFFFF",
                surfaceHex: "#1F5E43"
            )
        case .mission:
            return SemanticPalette(
                foreground: ink900,
                surface: Color(
                    .sRGB,
                    red: 1,
                    green: 240.0 / 255.0,
                    blue: 184.0 / 255.0,
                    opacity: 1
                ),
                foregroundHex: "#183127",
                surfaceHex: "#FFF0B8"
            )
        case .appetite:
            return SemanticPalette(
                foreground: ink900,
                surface: Color(
                    .sRGB,
                    red: 1,
                    green: 225.0 / 255.0,
                    blue: 214.0 / 255.0,
                    opacity: 1
                ),
                foregroundHex: "#183127",
                surfaceHex: "#FFE1D6"
            )
        case .nutrition:
            return SemanticPalette(
                foreground: .white,
                surface: Color(
                    .sRGB,
                    red: 85.0 / 255.0,
                    green: 48.0 / 255.0,
                    blue: 163.0 / 255.0,
                    opacity: 1
                ),
                foregroundHex: "#FFFFFF",
                surfaceHex: "#5530A3"
            )
        case .schedule:
            return SemanticPalette(
                foreground: .white,
                surface: Color(
                    .sRGB,
                    red: 20.0 / 255.0,
                    green: 100.0 / 255.0,
                    blue: 122.0 / 255.0,
                    opacity: 1
                ),
                foregroundHex: "#FFFFFF",
                surfaceHex: "#14647A"
            )
        case .safety:
            return SemanticPalette(
                foreground: danger700,
                surface: cream50,
                foregroundHex: "#A33A35",
                surfaceHex: "#FFF9EC"
            )
        case .background:
            return SemanticPalette(
                foreground: ink900,
                surface: cream50,
                foregroundHex: "#183127",
                surfaceHex: "#FFF9EC"
            )
        }
    }
}

struct MealMonthDateVisualStyle {
    enum Position: CaseIterable {
        case selected
        case currentMonth
        case adjacentMonth
    }

    let foreground: Color
    let surface: Color
    let foregroundHex: String
    let surfaceHex: String

    static func resolve(position: Position) -> MealMonthDateVisualStyle {
        switch position {
        case .selected:
            return MealMonthDateVisualStyle(
                foreground: RebuildDesignTokens.forest700,
                surface: RebuildDesignTokens.cream100,
                foregroundHex: "#1F5E43",
                surfaceHex: "#F5EEDC"
            )
        case .currentMonth:
            return MealMonthDateVisualStyle(
                foreground: RebuildDesignTokens.ink900,
                surface: .white,
                foregroundHex: "#183127",
                surfaceHex: "#FFFFFF"
            )
        case .adjacentMonth:
            return MealMonthDateVisualStyle(
                foreground: RebuildDesignTokens.muted600,
                surface: .white,
                foregroundHex: "#627168",
                surfaceHex: "#FFFFFF"
            )
        }
    }
}

enum MealAllergySignalChannel: Equatable {
    case text
    case icon
    case shape
}

struct MealAllergyVisualStyle: Equatable {
    let title: String
    let systemImage: String
    let borderWidth: CGFloat
    let cornerRadius: CGFloat
    let channels: [MealAllergySignalChannel]
    let isRisk: Bool

    static let clear = MealAllergyVisualStyle(
        title: "표시된 알레르기 정보 없음",
        systemImage: "checkmark.shield.fill",
        borderWidth: 1,
        cornerRadius: RebuildDesignTokens.radii[0],
        channels: [.text, .icon, .shape],
        isRisk: false
    )

    static func resolve(for item: RebuildMealItem) -> MealAllergyVisualStyle {
        let labels = item.allergyLabels
        guard !labels.isEmpty else { return .clear }

        return risk(labels: labels)
    }

    static func risk(labels: [String]) -> MealAllergyVisualStyle {
        return MealAllergyVisualStyle(
            title: "알레르기 정보 확인: \(labels.joined(separator: " · "))",
            systemImage: "exclamationmark.shield.fill",
            borderWidth: 2,
            cornerRadius: RebuildDesignTokens.radii[0],
            channels: [.text, .icon, .shape],
            isRisk: true
        )
    }
}
