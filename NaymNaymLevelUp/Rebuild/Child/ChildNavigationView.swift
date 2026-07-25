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

    init(
        profile: RebuildUserProfile,
        container: NSPersistentContainer?
    ) {
        _todayViewModel = StateObject(
            wrappedValue: Self.makeTodayViewModel(
                profile: profile,
                container: container
            )
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayForestView(viewModel: todayViewModel)
                .tabItem {
                    Label(
                        RebuildChildTab.today.title,
                        systemImage: RebuildChildTab.today.systemImage
                    )
                }
                .tag(RebuildChildTab.today)

            ProgressAndBadgesView()
                .tabItem {
                    Label(
                        RebuildChildTab.growth.title,
                        systemImage: RebuildChildTab.growth.systemImage
                    )
                }
                .tag(RebuildChildTab.growth)

            RebuildCollectionView()
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

private struct RebuildCollectionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                    GrowthCharacterView(
                        level: 1,
                        size: 144,
                        pose: .wave,
                        blendsCreamBackground: true
                    )
                    .frame(maxWidth: .infinity)

                    Text("먹어 본 음식과 만난 영양소가 이곳에 차곡차곡 모여요.")
                        .font(RebuildDesignTokens.bodyFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("오늘 급식을 기록하면 첫 도감 이야기가 열려요.")
                        .font(RebuildDesignTokens.headlineFont)
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(RebuildDesignTokens.spacing[4])
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle("도감")
        }
    }
}
