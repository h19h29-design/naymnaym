import XCTest
@testable import NaymNaymLevelUp

final class RebuildDesignTokensTests: XCTestCase {
    func testApprovedTokensAreExact() {
        XCTAssertEqual(RebuildDesignTokens.minimumActionSize, 48)
        XCTAssertEqual(RebuildDesignTokens.spacing, [4, 8, 12, 16, 24, 32])
        XCTAssertEqual(RebuildDesignTokens.hex(.forest700), "#1F5E43")
        XCTAssertEqual(RebuildDesignTokens.hex(.cream50), "#FFF9EC")
    }

    func testLockedGrowthCopyMeetsNormalTextContrast() {
        XCTAssertGreaterThanOrEqual(
            AppReadabilityPolicy.contrastRatio(
                foregroundHex: GrowthLockedPalette.textHex,
                backgroundHex: GrowthLockedPalette.surfaceHex
            ),
            4.5
        )
        XCTAssertEqual(GrowthLockedPalette.silhouetteHex, "#B87548")
        XCTAssertNotEqual(
            GrowthLockedPalette.textHex,
            GrowthLockedPalette.silhouetteHex
        )
    }

    func testSemanticTokensKeepMinimumContrast() {
        XCTAssertEqual(
            Set(RebuildDesignTokens.SemanticRole.allCases),
            Set([
            .growth,
            .mission,
            .appetite,
            .nutrition,
            .schedule,
            .safety,
                .background,
            ])
        )

        for role in RebuildDesignTokens.SemanticRole.allCases {
            let palette = RebuildDesignTokens.semanticPalette(role)
            XCTAssertGreaterThanOrEqual(
                AppReadabilityPolicy.contrastRatio(
                    foregroundHex: palette.foregroundHex,
                    backgroundHex: palette.surfaceHex
                ),
                4.5,
                "Expected \(role) foreground and surface to remain readable"
            )
        }
    }

    func testMonthDateStylesKeepNormalTextContrast() {
        for position in MealMonthDateVisualStyle.Position.allCases {
            let style = MealMonthDateVisualStyle.resolve(position: position)
            XCTAssertGreaterThanOrEqual(
                AppReadabilityPolicy.contrastRatio(
                    foregroundHex: style.foregroundHex,
                    backgroundHex: style.surfaceHex
                ),
                4.5,
                "Expected \(position) month date text to remain readable"
            )
        }
    }
}
