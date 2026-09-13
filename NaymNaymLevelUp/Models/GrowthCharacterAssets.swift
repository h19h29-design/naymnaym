import Foundation

extension GrowthCharacterAssets {
    static func imageName(for level: Int) -> String {
        "Squirrel_Growth_Level_\(atlasCell(for: level) + 1)"
    }
}

enum GrowthCharacterPose: Equatable {
    case idle
    case wave
    case celebrate
    case eating
}
