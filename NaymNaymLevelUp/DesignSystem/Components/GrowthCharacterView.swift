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

            Image(GrowthCharacterAssets.atlasImageName)
                .resizable()
                .interpolation(.high)
                .frame(width: renderedSize * 4, height: renderedSize * 4)
                .offset(x: atlasOffset.width, y: atlasOffset.height)
        }
        .frame(width: renderedSize, height: renderedSize)
        .clipped()
        .rotationEffect(poseRotation)
        .scaleEffect(poseScale)
        .frame(width: renderedSize, height: renderedSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(clampedLevel), \(GrowthCharacterAssets.stageTitle(for: level)) 다람쥐")
    }

    private var renderedSize: CGFloat {
        max(0, size)
    }

    private var clampedLevel: Int {
        GrowthCharacterAssets.atlasCell(for: level) + 1
    }

    private var atlasOffset: CGSize {
        let coordinates = GrowthCharacterAssets.atlasCoordinates(for: level)
        return CGSize(
            width: (1.5 - CGFloat(coordinates.column)) * renderedSize,
            height: (coordinates.row == 0 ? 1 : -1) * renderedSize
        )
    }

    private var poseRotation: Angle {
        pose == .wave ? .degrees(-1.5) : .zero
    }

    private var poseScale: CGFloat {
        pose == .celebrate ? 1.04 : 1
    }
}

private extension Color {
    static let growthCharacterCream = Color(
        red: 1,
        green: 249.0 / 255.0,
        blue: 238.0 / 255.0
    )
}
