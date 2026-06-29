import SwiftUI

enum AppColors {
    static let mint = Color(hex: "#7BC96F")
    static let lime = Color(hex: "#B7E66E")
    static let yellow = Color(hex: "#FFD966")
    static let coral = Color(hex: "#FF6B6B")
    static let pink = Color(hex: "#F78FB3")
    static let purple = Color(hex: "#7C5CFF")
    static let indigo = Color(hex: "#3F51B5")
    static let sky = Color(hex: "#65B7D4")
    static let blue = Color(hex: "#3F6AE6")
    static let navy = Color(hex: "#10172A")
    static let cream = Color(hex: "#FFF8E7")
    static let lavender = Color(hex: "#F3E8FF")
    static let cardWhite = Color(hex: "#FFFFFF")
    static let warningRed = Color(hex: "#E5484D")
    static let successGreen = Color(hex: "#2FB344")
    static let infoBlue = Color(hex: "#3F6AE6")
    static let primaryGreen = Color(hex: "#7BC96F")
    static let softYellow = Color(hex: "#FFD966")
    static let orange = Color(hex: "#FF9F43")
    static let creamBackground = Color(hex: "#FFF8E7")
    static let textDark = Color(hex: "#263126")
    static let graySecondary = Color(hex: "#6B7280")
    static let cardStroke = Color.black.opacity(0.07)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.cardWhite)
                    .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
            .frame(minHeight: 52)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .background {
                if isDisabled {
                    AppColors.graySecondary.opacity(0.35)
                } else {
                    LinearGradient(
                        colors: [AppColors.purple, AppColors.infoBlue, AppColors.sky],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: isDisabled ? Color.clear : AppColors.purple.opacity(0.22), radius: 10, x: 0, y: 6)
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
            .foregroundColor(AppColors.indigo)
            .padding(.horizontal, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.indigo.opacity(0.18), lineWidth: 1)
            )
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
                    .fill(isLocked ? Color.gray.opacity(0.18) : badgeColor.opacity(0.20))
                    .frame(width: 54, height: 54)
                Image(systemName: isLocked ? "lock.fill" : iconName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isLocked ? AppColors.graySecondary : badgeColor)
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

    private var badgeColor: Color {
        if name.contains("초록") { return AppColors.successGreen }
        if name.contains("단백질") { return AppColors.coral }
        if name.contains("칼슘") { return AppColors.infoBlue }
        if name.contains("비타민") { return AppColors.purple }
        if name.contains("헌터") { return AppColors.orange }
        return AppColors.indigo
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
            .background(isSelected ? AppColors.warningRed : AppColors.lavender.opacity(0.55))
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
                .fill(Color(hex: skin.primaryColorHex).opacity(skin.targetMode == .middle ? 0.35 : 0.22))
                .frame(width: size, height: size)
            if skin.targetMode == .middle {
                Circle()
                    .stroke(Color(hex: skin.primaryColorHex).opacity(0.8), lineWidth: 3)
                    .frame(width: size * 0.84, height: size * 0.84)
                    .shadow(color: Color(hex: skin.primaryColorHex).opacity(0.5), radius: 8)
            }
            Circle()
                .fill(avatarFill)
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay(Circle().stroke(Color(hex: skin.primaryColorHex), lineWidth: 3))
            VStack(spacing: 0) {
                Text(skin.emojiFallback)
                    .font(.system(size: max(22, size * 0.24)))
                Text(faceText)
                    .font(.system(size: max(24, size * 0.22), weight: .bold, design: .rounded))
                    .foregroundStyle(skin.targetMode == .middle ? Color.white : AppColors.textDark)
                Capsule()
                    .fill(Color(hex: skin.targetMode == .high ? "#DCE9FF" : "#FFF3B0"))
                    .frame(width: size * 0.34, height: size * 0.16)
            }
            if skin.rarity == "epic" || skin.rarity == "legend" {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: skin.primaryColorHex))
                    .offset(x: size * 0.28, y: -size * 0.28)
            }
        }
        .accessibilityLabel("\(skin.name), \(skin.description)")
    }

    private var avatarFill: Color {
        switch skin.targetMode {
        case .middle:
            return Color(hex: "#111735")
        case .high:
            return Color(hex: "#E9F1FF")
        case .elementary, .parent:
            return Color(hex: "#B8E986")
        }
    }

    private var faceText: String {
        switch skin.targetMode {
        case .middle:
            return "•_•"
        case .high:
            return "•‿•"
        case .elementary, .parent:
            return "•ᴗ•"
        }
    }
}

struct MealCard: View {
    var item: MealItem
    var isAllergyRisk: Bool = false
    var onSkip: () -> Void
    var onChallenge: () -> Void
    var onAlreadyEats: () -> Void
    var onRecord: () -> Void = {}

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
                        .foregroundStyle(isAllergyRisk ? AppColors.warningRed : iconColor)
                        .font(.title3)
                }

                if isAllergyRisk {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.warningRed)
                        Text("선택한 알레르기와 관련된 메뉴예요. 한 입 도전보다 안전 확인이 먼저예요.")
                            .font(AppTypography.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(AppColors.warningRed.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !item.allergyCodes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(item.allergyCodes, id: \.self) { code in
                                AllergyChip(code: code, isSelected: isAllergyRisk)
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    SecondaryButton("안내 보기", systemImage: "info.circle", action: onSkip)
                    PrimaryButton("한 입 도전", systemImage: "checkmark.seal.fill", isDisabled: isAllergyRisk, action: onChallenge)
                    SecondaryButton("먹은 정도", systemImage: "list.bullet.clipboard", action: onRecord)
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

    private var iconColor: Color {
        if item.nutrients.contains("식이섬유") { return AppColors.successGreen }
        if item.nutrients.contains("단백질") { return AppColors.coral }
        if item.nutrients.contains("칼슘") { return AppColors.infoBlue }
        return AppColors.orange
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
                .background(isToday ? AppColors.purple : Color.clear)
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
        .background(meal == nil ? Color.white.opacity(0.58) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? AppColors.purple : AppColors.cardStroke, lineWidth: isToday ? 2 : 1)
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
        background(
            LinearGradient(
                colors: [AppColors.creamBackground, AppColors.lavender.opacity(0.72), AppColors.sky.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    func pageBackground(theme: ThemeProfile) -> some View {
        background(ThemeBackdrop(theme: theme).ignoresSafeArea())
    }
}

struct ThemeBackdrop: View {
    var theme: ThemeProfile

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var colors: [Color] {
        switch theme.targetMode {
        case .elementary:
            return [AppColors.cream, AppColors.yellow.opacity(0.22), AppColors.sky.opacity(0.20)]
        case .middle:
            return [AppColors.navy, AppColors.purple.opacity(0.58), Color(hex: "#00E5FF").opacity(0.18)]
        case .high:
            return [Color(hex: "#F4F7FC"), AppColors.blue.opacity(0.14), AppColors.lavender.opacity(0.50)]
        case .parent:
            return [Color(hex: "#FFF6EE"), AppColors.coral.opacity(0.16), AppColors.indigo.opacity(0.12)]
        }
    }
}
