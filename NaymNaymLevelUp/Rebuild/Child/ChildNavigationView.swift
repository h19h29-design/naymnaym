import CoreData
import Foundation
import SwiftUI

enum RebuildChildTab: String, CaseIterable, Identifiable {
    case today
    case meals
    case growth
    case collection
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "오늘"
        case .meals: return "급식표"
        case .growth: return "성장"
        case .collection: return "도감"
        case .settings: return "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "leaf.fill"
        case .meals: return "calendar"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .collection: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

final class RebuildChildSessionStore: ObservableObject {
    let container: NSPersistentContainer?
    let nutrientImpactSidecar: any NutrientImpactSidecar
    let growthStageStateStore: (any GrowthStageStateStore)?
    let legacyRights: LegacyGrowthRights?
    let canUseNutrientImpactSidecar: Bool

    init(
        profile: RebuildUserProfile,
        persistentContainer: NSPersistentContainer?
    ) {
        if profile.isDemoMode {
            container = try? RebuildPersistentStore.makeInMemory()
            nutrientImpactSidecar = InMemoryNutrientImpactSidecar()
            growthStageStateStore = RebuildInMemoryGrowthStageStateStore()
            legacyRights = .empty
            canUseNutrientImpactSidecar = true
            return
        }

        container = persistentContainer
        growthStageStateStore = nil
        legacyRights = nil
        nutrientImpactSidecar = NoopNutrientImpactSidecar.shared
        canUseNutrientImpactSidecar = false
    }
}

struct ChildNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var childSession: RebuildChildSessionStore
    @StateObject private var todayViewModel: TodayForestViewModel
    @StateObject private var mealScheduleViewModel: MealScheduleViewModel
    @State private var selection: RebuildChildTab = .today
    private let growthPolicy: GrowthPolicy
    private let growthProvider: any GrowthSnapshotProviding
    private let collectionProvider: any CollectionSnapshotProviding

    init(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?
    ) {
        let session = RebuildChildSessionStore(
            profile: profile,
            persistentContainer: container
        )
        _childSession = StateObject(wrappedValue: session)
        do {
            growthPolicy = try GrowthPolicy.bundled()
        } catch {
            fatalError("Validated growth policy is missing or invalid: \(error)")
        }
        if let container = session.container {
            growthProvider = CoreDataGrowthSnapshotProvider(
                container: container
            )
            collectionProvider = CoreDataCollectionSnapshotProvider(
                container: container
            )
        } else {
            growthProvider = UnavailableGrowthSnapshotProvider()
            collectionProvider = UnavailableCollectionSnapshotProvider()
        }
        _todayViewModel = StateObject(
            wrappedValue: Self.makeTodayViewModel(
                profile: profile,
                container: session.container,
                session: session
            )
        )
        _mealScheduleViewModel = StateObject(
            wrappedValue: Self.makeMealScheduleViewModel(
                profile: profile,
                container: session.container
            )
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayForestView(
                viewModel: todayViewModel,
                growthPolicy: growthPolicy,
                isTabActive: selection == .today,
                isAppActive: scenePhase == .active
            )
                .tabItem {
                    Label(
                        RebuildChildTab.today.title,
                        systemImage: RebuildChildTab.today.systemImage
                    )
                }
                .tag(RebuildChildTab.today)

            MealScheduleView(
                viewModel: mealScheduleViewModel,
                recordingViewModelFactory: { route in
                    todayViewModel.recordingViewModel(for: route)
                }
            )
                .tabItem {
                    Label(
                        RebuildChildTab.meals.title,
                        systemImage: RebuildChildTab.meals.systemImage
                    )
                }
                .tag(RebuildChildTab.meals)

            GrowthView(
                provider: growthProvider,
                policy: growthPolicy,
                isActive: selection == .growth,
                stateStore: childSession.growthStageStateStore,
                legacyRights: childSession.legacyRights
            )
                .tabItem {
                    Label(
                        RebuildChildTab.growth.title,
                        systemImage: RebuildChildTab.growth.systemImage
                    )
                }
                .tag(RebuildChildTab.growth)

            CollectionView(
                provider: collectionProvider,
                policy: growthPolicy,
                isActive: selection == .collection,
                stateStore: childSession.growthStageStateStore,
                legacyRights: childSession.legacyRights
            )
                .tabItem {
                    Label(
                        RebuildChildTab.collection.title,
                        systemImage: RebuildChildTab.collection.systemImage
                    )
                }
                .tag(RebuildChildTab.collection)

            SettingsView()
                .tabItem {
                    Label(
                        RebuildChildTab.settings.title,
                        systemImage: RebuildChildTab.settings.systemImage
                    )
                }
                .tag(RebuildChildTab.settings)
        }
        .tint(RebuildDesignTokens.forest700)
        .accessibilityIdentifier("child_navigation")
    }

    @MainActor
    private static func makeTodayViewModel(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?,
        session: RebuildChildSessionStore
    ) -> TodayForestViewModel {
        guard let container else {
            return TodayForestViewModel(
                repository: UnavailableTodayMealRepository(),
                recorder: UnavailableTodayMealRecorder(),
                school: profile.school.map(Self.rebuildSchool),
                allergyCodes: profile.allergyCodes,
                isDemoMode: profile.isDemoMode
            )
        }

        let recorder: RecordMealUseCase?
        if profile.isDemoMode {
            recorder = session.canUseNutrientImpactSidecar
                ? try? RecordMealUseCase(
                    container: container,
                    nutrientImpactSidecar: session.nutrientImpactSidecar
                )
                : nil
        } else {
            guard let applicationSupportURL = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                return TodayForestViewModel(
                    repository: UnavailableTodayMealRepository(),
                    recorder: UnavailableTodayMealRecorder(),
                    school: profile.school.map(Self.rebuildSchool),
                    allergyCodes: profile.allergyCodes,
                    isDemoMode: profile.isDemoMode
                )
            }
            recorder = try? RecordMealUseCase(
                container: container,
                nutrientImpactSidecar: FileNutrientImpactSidecar(
                    directoryURL: applicationSupportURL.appendingPathComponent(
                        "NutrientImpactSidecar",
                        isDirectory: true
                    )
                )
            )
        }

        guard let recorder else {
            return TodayForestViewModel(
                repository: UnavailableTodayMealRepository(),
                recorder: UnavailableTodayMealRecorder(),
                school: profile.school.map(Self.rebuildSchool),
                allergyCodes: profile.allergyCodes,
                isDemoMode: profile.isDemoMode
            )
        }

        let repository = RebuildMealRepository(
            store: CoreDataRebuildMealDayStore(
                context: container.newBackgroundContext()
            ),
            client: RebuildMealClientFactory.make(
                isDemoMode: profile.isDemoMode
            )
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
            allergyCodes: profile.allergyCodes,
            isDemoMode: profile.isDemoMode
        )
    }

    @MainActor
    private static func makeMealScheduleViewModel(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?
    ) -> MealScheduleViewModel {
        let school = profile.school.map(Self.rebuildSchool)
        guard let container else {
            return MealScheduleViewModel(
                repository: UnavailableMealScheduleRepository(),
                school: school,
                isDemoMode: profile.isDemoMode
            )
        }
        let repository = RebuildMealRepository(
            store: CoreDataRebuildMealDayStore(
                context: container.newBackgroundContext()
            ),
            client: RebuildMealClientFactory.make(
                isDemoMode: profile.isDemoMode
            )
        )
        return MealScheduleViewModel(
            repository: LiveMealScheduleRepository(repository: repository),
            school: school,
            isDemoMode: profile.isDemoMode
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
