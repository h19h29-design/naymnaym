import SwiftUI

enum AppColors {
    static let primaryGreen = Color(hex: "#7BC96F")
    static let softYellow = Color(hex: "#FFD966")
    static let orange = Color(hex: "#FF9F43")
    static let creamBackground = Color(hex: "#FFF9EC")
    static let textDark = Color(hex: "#263126")
    static let graySecondary = Color(hex: "#6B7280")
    static let cardStroke = Color.black.opacity(0.08)
}

struct AppTheme {
    var name: String
    var primary: Color
    var secondary: Color
    var accent: Color
    var background: Color
    var text: Color

    static let defaultGreen = AppTheme(
        name: "냠냠 그린",
        primary: AppColors.primaryGreen,
        secondary: AppColors.softYellow,
        accent: AppColors.orange,
        background: AppColors.creamBackground,
        text: AppColors.textDark
    )
}

enum AppTypography {
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
}

struct RoundedCard<Content: View>: View {
    var padding: CGFloat
    var content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.cardStroke, lineWidth: 1)
            )
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var isDisabled: Bool
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .background(isDisabled ? AppColors.graySecondary.opacity(0.35) : AppColors.primaryGreen)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(isDisabled)
        .accessibilityAddTraits(.isButton)
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .foregroundColor(AppColors.primaryGreen)
            .padding(.horizontal, 12)
            .background(AppColors.primaryGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityAddTraits(.isButton)
    }
}

struct StatBar: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(AppTypography.caption.weight(.semibold))
                Spacer()
                Text("\(value)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(1, max(0, CGFloat(value) / 30)))
                }
            }
            .frame(height: 8)
        }
    }
}

struct BadgeView: View {
    var name: String
    var isLocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isLocked ? Color.gray.opacity(0.18) : AppColors.softYellow.opacity(0.45))
                    .frame(width: 54, height: 54)
                Image(systemName: isLocked ? "lock.fill" : iconName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isLocked ? AppColors.graySecondary : AppColors.orange)
            }
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isLocked ? AppColors.graySecondary : AppColors.textDark)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(minHeight: 28)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(isLocked ? "\(name) 잠김" : "\(name) 획득")
    }

    private var iconName: String {
        if name.contains("초록") { return "leaf.fill" }
        if name.contains("단백질") { return "bolt.heart.fill" }
        if name.contains("칼슘") { return "shield.fill" }
        if name.contains("비타민") { return "star.fill" }
        if name.contains("헌터") { return "target" }
        return "fork.knife.circle.fill"
    }
}

struct AllergyChip: View {
    var code: Int
    var isSelected: Bool

    var body: some View {
        Text(AllergyMap.label(for: code))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : AppColors.textDark)
            .background(isSelected ? AppColors.orange : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppColors.cardStroke, lineWidth: 1))
    }
}

struct CharacterAvatar: View {
    var skin: CharacterSkin
    var size: CGFloat = 116

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: skin.primaryColorHex).opacity(0.22))
                .frame(width: size, height: size)
            Circle()
                .fill(Color(hex: "#B8E986"))
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay(Circle().stroke(Color(hex: skin.primaryColorHex), lineWidth: 3))
            VStack(spacing: 0) {
                Text(skin.emoji)
                    .font(.system(size: max(22, size * 0.24)))
                Text("•ᴗ•")
                    .font(.system(size: max(24, size * 0.22), weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textDark)
                Capsule()
                    .fill(Color(hex: "#FFF3B0"))
                    .frame(width: size * 0.34, height: size * 0.16)
            }
        }
        .accessibilityLabel("\(skin.name), \(skin.description)")
    }
}

struct MealCard: View {
    var item: MealItem
    var onSkip: () -> Void
    var onChallenge: () -> Void
    var onAlreadyEats: () -> Void

    var body: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textDark)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.tags.isEmpty {
                            Text(item.tags.joined(separator: " · "))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Image(systemName: iconName)
                        .foregroundStyle(AppColors.primaryGreen)
                        .font(.title3)
                }

                if !item.allergyCodes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(item.allergyCodes, id: \.self) { code in
                                AllergyChip(code: code, isSelected: false)
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    SecondaryButton("안 먹어요", systemImage: "xmark.circle", action: onSkip)
                    PrimaryButton("한입 도전", systemImage: "checkmark.seal.fill", action: onChallenge)
                    SecondaryButton("잘 먹어요", systemImage: "hand.thumbsup", action: onAlreadyEats)
                }
            }
        }
    }

    private var iconName: String {
        if item.nutrients.contains("식이섬유") { return "leaf.fill" }
        if item.nutrients.contains("단백질") { return "bolt.heart.fill" }
        if item.nutrients.contains("칼슘") { return "shield.fill" }
        return "fork.knife"
    }
}

struct CalendarDayCell: View {
    var date: Date
    var meal: MealDay?
    var isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? Color.white : AppColors.textDark)
                .frame(width: 24, height: 24)
                .background(isToday ? AppColors.primaryGreen : Color.clear)
                .clipShape(Circle())
            Text(meal?.representativeMenu ?? "정보 없음")
                .font(.caption2)
                .foregroundStyle(meal == nil ? AppColors.graySecondary : AppColors.textDark)
                .lineLimit(3)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(meal == nil ? Color.white.opacity(0.55) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isToday ? AppColors.primaryGreen : AppColors.cardStroke, lineWidth: isToday ? 2 : 1)
        )
    }
}

extension Color {
    init(hex: String) {
        var hexValue = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hexValue.count == 3 {
            hexValue = hexValue.map { "\($0)\($0)" }.joined()
        }
        var int: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8) & 0xFF) / 255.0
        let blue = Double(int & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func pageBackground() -> some View {
        background(AppColors.creamBackground.ignoresSafeArea())
    }
}
