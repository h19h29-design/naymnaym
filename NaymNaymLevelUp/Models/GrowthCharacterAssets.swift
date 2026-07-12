import Foundation

extension GrowthCharacterAssets {
    static let atlasImageName = "Squirrel_Growth_Atlas"
    static let atlasColumns = 4
    static let atlasRows = 2

    static func atlasCoordinates(for level: Int) -> (column: Int, row: Int) {
        let cell = atlasCell(for: level)
        return (cell % atlasColumns, cell / atlasColumns)
    }
}

enum GrowthCharacterPose: Equatable {
    case idle
    case wave
    case celebrate
}
