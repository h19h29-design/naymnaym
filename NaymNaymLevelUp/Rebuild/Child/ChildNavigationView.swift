import CoreData
import SwiftUI

enum RebuildChildTab: String, CaseIterable, Identifiable {
    case today
    case growth
    case collection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "오늘"
        case .growth: return "성장"
        case .collection: return "도감"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "leaf.fill"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .collection: return "books.vertical.fill"
        }
    }
}

struct ChildNavigationView: View {
    @StateObject private var todayViewModel: TodayForestViewModel
    @State private var selection: RebuildChildTab = .today
    private let growthPolicy: GrowthPolicy
    private let growthProvider: any GrowthSnapshotProviding

    init(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?
    ) {
        do {
            growthPolicy = try GrowthPolicy.bundled()
        } catch {
            fatalError("Validated growth policy is missing or invalid: \(error)")
        }
        if let container {
            growthProvider = CoreDataGrowthSnapshotProvider(
                container: container
            )
        } else {
            growthProvider = UnavailableGrowthSnapshotProvider()
        }
        _todayViewModel = StateObject(
            wrappedValue: Self.makeTodayViewModel(
                profile: profile,
                container: container
            )
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayForestView(
                viewModel: todayViewModel,
                growthPolicy: growthPolicy
            )
                .tabItem {
                    Label(
                        RebuildChildTab.today.title,
                        systemImage: RebuildChildTab.today.systemImage
                    )
                }
                .tag(RebuildChildTab.today)

            GrowthView(
                provider: growthProvider,
                policy: growthPolicy,
                isActive: selection == .growth
            )
                .tabItem {
                    Label(
                        RebuildChildTab.growth.title,
                        systemImage: RebuildChildTab.growth.systemImage
                    )
                }
                .tag(RebuildChildTab.growth)

            CollectionView(
                provider: growthProvider,
                policy: growthPolicy,
                isActive: selection == .collection
            )
                .tabItem {
                    Label(
                        RebuildChildTab.collection.title,
                        systemImage: RebuildChildTab.collection.systemImage
                    )
                }
                .tag(RebuildChildTab.collection)
        }
        .tint(RebuildDesignTokens.forest700)
        .accessibilityIdentifier("child_navigation")
    }

    @MainActor
    private static func makeTodayViewModel(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?
    ) -> TodayForestViewModel {
        guard let container,
              let recorder = try? RecordMealUseCase(container: container)
        else {
            return TodayForestViewModel(
                repository: UnavailableTodayMealRepository(),
                recorder: UnavailableTodayMealRecorder(),
                school: profile.school.map(Self.rebuildSchool),
                allergyCodes: profile.allergyCodes
            )
        }

        let repository = RebuildMealRepository(
            store: CoreDataRebuildMealDayStore(
                context: container.newBackgroundContext()
            ),
            client: RebuildMealClient()
        )
        return TodayForestViewModel(
            repository: repository,
            recorder: LiveTodayMealRecorder(useCase: recorder),
            photoMetadataStore: CoreDataTodayMealPhotoMetadataStore(
                container: container
            ),
            progressProvider: CoreDataTodayProgressProvider(
                container: container
            ),
            school: profile.school.map(Self.rebuildSchool),
            allergyCodes: profile.allergyCodes
        )
    }

    private static func rebuildSchool(
        _ school: RebuildOnboardingSchool
    ) -> RebuildSchool {
        RebuildSchool(
            name: school.name,
            officeCode: school.officeCode,
            schoolCode: school.schoolCode
        )
    }
}

private actor UnavailableTodayMealRepository: TodayMealRepository {
    func currentState(date: String) -> MealLoadState {
        .failed(message: "persistence unavailable", cached: nil)
    }

    func refresh(date: String, school: RebuildSchool) {}
}

private struct UnavailableTodayMealRecorder: TodayMealRecorder {
    func execute(_ command: RecordMealCommand) async throws -> RecordMealResult {
        throw RebuildOnboardingError.persistenceUnavailable
    }
}
