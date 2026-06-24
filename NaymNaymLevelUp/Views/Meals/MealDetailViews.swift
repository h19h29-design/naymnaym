import SwiftUI
import UIKit

struct MealLossDetailView: View {
    var item: MealItem
    var isChallengeLocked: Bool = false
    var onChallenge: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.name)
                                .font(AppTypography.title)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(NutritionEstimator.makeStudentExplanation(for: item))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textDark)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("게임 스탯 변화")
                                .font(AppTypography.headline)
                            ForEach(NutritionEstimator.makeGameStats(for: item)) { stat in
                                StatBar(title: stat.name, value: stat.value, color: AppColors.primaryGreen)
                            }
                        }
                    }

                    if isChallengeLocked {
                        RoundedCard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Color.red)
                                Text("알레르기/주의 메뉴는 한 입 도전보다 안전 확인이 먼저예요. 먹지 않아도 안전 XP로 기록돼요.")
                                    .font(AppTypography.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    PrimaryButton("한 입 도전하기", systemImage: "checkmark.seal.fill", isDisabled: isChallengeLocked) {
                        onChallenge()
                        dismiss()
                    }
                    SecondaryButton("오늘은 안 먹어요", systemImage: "moon") {
                        dismiss()
                    }
                }
                .padding(20)
            }
            .navigationTitle("영양소 안내")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
    }
}

struct LevelUpResultView: View {
    var outcome: ChallengeOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var sharingItem: ShareCardActivityItem?
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CharacterAvatar(skin: outcome.skin, size: 150)
                    RoundedCard {
                        VStack(spacing: 14) {
                            Text(outcomeTitle)
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(AppColors.primaryGreen)
                                .multilineTextAlignment(.center)
                            Text("총 XP +\(outcome.gainedExp)")
                                .font(AppTypography.headline)
                            if !outcome.xpBreakdown.summaryText.isEmpty {
                                Text(outcome.xpBreakdown.summaryText)
                                    .font(AppTypography.body.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if outcome.bonusExp > 0 {
                                Text("다시 시도 보너스 +\(outcome.bonusExp)")
                                    .font(AppTypography.caption.weight(.bold))
                                    .foregroundStyle(AppColors.orange)
                            }
                            Text("\(outcome.badgeName) 뱃지 획득!")
                                .font(AppTypography.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if !outcome.xpNotes.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(outcome.xpNotes.prefix(3), id: \.self) { note in
                                        Label(note, systemImage: "sparkle")
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.graySecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            if outcome.didLevelUp {
                                Text("Lv.\(outcome.newLevel) \(PlayerProgress.title(for: outcome.newLevel))로 레벨업!")
                                    .font(AppTypography.headline)
                                    .foregroundStyle(AppColors.primaryGreen)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    shareCardSection

                    PrimaryButton("좋아요", systemImage: "hand.thumbsup.fill") {
                        dismiss()
                    }
                }
                .padding(20)
            }
            .navigationTitle("레벨업")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .sheet(item: $sharingItem) { item in
                ActivityView(activityItems: [item.image])
            }
        }
    }

    private var outcomeTitle: String {
        if outcome.xpBreakdown.safety > 0, outcome.xpBreakdown.challenge == 0 {
            return "안전 기록 완료!"
        }
        if outcome.xpBreakdown.balance > 0, outcome.xpBreakdown.challenge == 0 {
            return "균형 기록 완료!"
        }
        return "한 입 도전 성공!"
    }

    private var shareCardSection: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("공유 카드")
                    .font(AppTypography.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Label("친구 얼굴, 이름표, 반/번호가 보이면 공유하지 마세요.", systemImage: "exclamationmark.triangle.fill")
                    Label("알레르기 정보나 개인 기록은 공유 카드에 넣지 않아요.", systemImage: "lock.shield.fill")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.graySecondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(ShareCardKind.available(for: outcome)) { kind in
                    HStack(spacing: 8) {
                        Label(kind.title, systemImage: kind.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textDark)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            sharingItem = ShareCardActivityItem(image: ShareCardRenderer.render(kind: kind, outcome: outcome))
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .frame(width: 40, height: 36)
                        }
                        .accessibilityLabel("\(kind.title) 공유")
                        Button {
                            let image = ShareCardRenderer.render(kind: kind, outcome: outcome)
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saveMessage = "\(kind.title)을 사진 앱에 저장했어요."
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.headline)
                                .frame(width: 40, height: 36)
                        }
                        .accessibilityLabel("\(kind.title) 저장")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(AppColors.primaryGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.primaryGreen)
                }
            }
        }
    }
}

enum ShareCardKind: String, CaseIterable, Identifiable {
    case oneBiteSuccess
    case levelUp
    case badgeEarned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneBiteSuccess: return "한 입 도전 성공 카드"
        case .levelUp: return "레벨업 카드"
        case .badgeEarned: return "뱃지 획득 카드"
        }
    }

    var systemImage: String {
        switch self {
        case .oneBiteSuccess: return "fork.knife.circle.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .badgeEarned: return "seal.fill"
        }
    }

    static func available(for outcome: ChallengeOutcome) -> [ShareCardKind] {
        var kinds: [ShareCardKind] = [.oneBiteSuccess]
        if outcome.didLevelUp {
            kinds.append(.levelUp)
        }
        if !outcome.badgeName.isEmpty {
            kinds.append(.badgeEarned)
        }
        return kinds
    }
}

struct ShareCardActivityItem: Identifiable {
    let id = UUID()
    var image: UIImage
}

struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ShareCardRenderer {
    static func render(kind: ShareCardKind, outcome: ChallengeOutcome) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            drawBackground(in: cg, size: size)
            drawParticles(in: cg)
            drawMascot(in: CGRect(x: 330, y: 230, width: 420, height: 420))
            drawText(kind: kind, outcome: outcome, in: CGRect(x: 96, y: 705, width: 888, height: 440))
            drawFooter(in: CGRect(x: 96, y: 1190, width: 888, height: 88))
        }
    }

    static func textLines(kind: ShareCardKind, outcome: ChallengeOutcome) -> [String] {
        switch kind {
        case .oneBiteSuccess:
            return [
                "오늘의 한 입 도전",
                "\(outcome.menuName) 한 입 도전 성공!",
                "총 XP +\(outcome.gainedExp)"
            ]
        case .levelUp:
            return [
                "레벨업!",
                "Lv.\(outcome.newLevel) \(PlayerProgress.title(for: outcome.newLevel))",
                "오늘도 한 단계 성장했어요."
            ]
        case .badgeEarned:
            return [
                "뱃지 획득!",
                "\(outcome.badgeName) 뱃지를 모았어요.",
                "작은 도전이 쌓이고 있어요."
            ]
        }
    }

    private static func drawBackground(in cg: CGContext, size: CGSize) {
        let colors = [
            UIColor(red: 0.88, green: 0.97, blue: 0.94, alpha: 1).cgColor,
            UIColor(red: 1.00, green: 0.98, blue: 0.91, alpha: 1).cgColor,
            UIColor(red: 0.85, green: 0.97, blue: 0.74, alpha: 1).cgColor
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.58, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: 0), end: CGPoint(x: size.width / 2, y: size.height), options: [])

        cg.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        cg.fillEllipse(in: CGRect(x: -160, y: 1020, width: 1400, height: 360))
    }

    private static func drawParticles(in cg: CGContext) {
        let symbols: [(String, CGPoint, UIColor, CGFloat)] = [
            ("★", CGPoint(x: 170, y: 420), UIColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1), 64),
            ("♥", CGPoint(x: 880, y: 470), UIColor(red: 1.00, green: 0.48, blue: 0.40, alpha: 1), 54),
            ("✦", CGPoint(x: 780, y: 260), UIColor.white, 46),
            ("•", CGPoint(x: 210, y: 300), UIColor(red: 0.33, green: 0.73, blue: 0.33, alpha: 1), 58),
            ("•", CGPoint(x: 890, y: 300), UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1), 46)
        ]
        for (text, point, color, size) in symbols {
            draw(text, in: CGRect(x: point.x - 35, y: point.y - 35, width: 70, height: 70), font: .systemFont(ofSize: size, weight: .heavy), color: color, alignment: .center)
        }
    }

    private static func drawMascot(in rect: CGRect) {
        if let mascot = UIImage(named: "mascot_jump") ?? UIImage(named: "mascot_onboarding") {
            mascot.draw(in: rect)
        }
    }

    private static func drawText(kind: ShareCardKind, outcome: ChallengeOutcome, in rect: CGRect) {
        let cardPath = UIBezierPath(roundedRect: rect, cornerRadius: 44)
        UIColor.white.withAlphaComponent(0.94).setFill()
        cardPath.fill()
        UIColor.black.withAlphaComponent(0.06).setStroke()
        cardPath.lineWidth = 2
        cardPath.stroke()

        let lines = textLines(kind: kind, outcome: outcome)
        draw(lines[0], in: CGRect(x: rect.minX + 56, y: rect.minY + 58, width: rect.width - 112, height: 58), font: .systemFont(ofSize: 42, weight: .heavy), color: UIColor(red: 1.00, green: 0.55, blue: 0.12, alpha: 1), alignment: .center)
        draw(lines[1], in: CGRect(x: rect.minX + 56, y: rect.minY + 136, width: rect.width - 112, height: 150), font: .systemFont(ofSize: 54, weight: .heavy), color: UIColor(red: 0.08, green: 0.13, blue: 0.20, alpha: 1), alignment: .center)
        draw(lines[2], in: CGRect(x: rect.minX + 56, y: rect.minY + 306, width: rect.width - 112, height: 66), font: .systemFont(ofSize: 34, weight: .bold), color: UIColor(red: 0.25, green: 0.62, blue: 0.28, alpha: 1), alignment: .center)
    }

    private static func drawFooter(in rect: CGRect) {
        if let logo = UIImage(named: "logo_naym_levelup") {
            logo.draw(in: CGRect(x: rect.midX - 210, y: rect.minY, width: 420, height: 100))
        } else {
            draw("냠냠레벨업", in: rect, font: .systemFont(ofSize: 46, weight: .heavy), color: UIColor(red: 0.25, green: 0.62, blue: 0.28, alpha: 1), alignment: .center)
        }
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
}
