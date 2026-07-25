import XCTest
@testable import NaymNaymLevelUp

final class RebuildFeatureGateTests: XCTestCase {
    func testDefaultsToDisabled() {
        let defaults = makeDefaults()

        XCTAssertFalse(RebuildFeatureGate.isEnabled(defaults: defaults, arguments: []))
    }

    func testReadsOnlyNativeRebuildEnabledDefaultsKey() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "native-rebuild-enabled-legacy")

        XCTAssertFalse(RebuildFeatureGate.isEnabled(defaults: defaults, arguments: []))

        defaults.set(true, forKey: "native-rebuild-enabled")

        XCTAssertTrue(RebuildFeatureGate.isEnabled(defaults: defaults, arguments: []))
    }

    func testValidYESLaunchArgumentEnablesRebuild() {
        let defaults = makeDefaults()

        XCTAssertTrue(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled", "YES"]
            )
        )
    }

    func testLowercaseYESLaunchArgumentEnablesRebuild() {
        let defaults = makeDefaults()

        XCTAssertTrue(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled", "yes"]
            )
        )
    }

    func testMissingLaunchArgumentValueFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "native-rebuild-enabled")

        XCTAssertTrue(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled"]
            )
        )
    }

    func testExplicitNonYESLaunchArgumentOverridesEnabledDefaults() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "native-rebuild-enabled")

        XCTAssertFalse(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled", "NO"]
            )
        )
    }

    func testNonYESLaunchArgumentDoesNotAccidentallyEnableRebuild() {
        let defaults = makeDefaults()

        XCTAssertFalse(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled", "true"]
            )
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RebuildFeatureGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
