import SwiftUI

struct GrowthCharacterView: View {
    let level: Int
    let size: CGFloat
    let pose: GrowthCharacterPose

    init(level: Int, size: CGFloat, pose: GrowthCharacterPose = .idle) {
        self.level = level
        self.size = size
        self.pose = pose
    }

    var body: some View {
        ZStack {
            Color.growthCharacterCream

            Image(GrowthCharacterAssets.imageName(for: level))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
        .frame(width: renderedSize, height: renderedSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(clampedLevel), \(GrowthCharacterAssets.stageTitle(for: level)) 다람쥐")
        .accessibilityValue(pose.accessibilityValue)
    }

    private var renderedSize: CGFloat {
        max(0, size)
    }

    private var clampedLevel: Int {
        GrowthCharacterAssets.atlasCell(for: level) + 1
    }

}

private extension GrowthCharacterPose {
    var accessibilityValue: String {
        switch self {
        case .idle:
            return "기본 자세"
        case .wave:
            return "손 흔드는 자세"
        case .celebrate:
            return "축하 자세"
        }
    }
}

private extension Color {
    static let growthCharacterCream = Color(
        red: 1,
        green: 249.0 / 255.0,
        blue: 238.0 / 255.0
    )
}
