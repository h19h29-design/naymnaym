import CoreData
import Foundation

protocol TodayMealRepository: Sendable {
    func currentState(date: String) async -> MealLoadState
    func refresh(date: String, school: RebuildSchool) async
}

protocol TodayMealRecorder: Sendable {
    func execute(_ command: RecordMealCommand) async throws -> RecordMealResult
}

protocol TodayMealPhotoMetadataStore: Sendable {
    func photoIDs(
        date: String,
        normalizedMenuName: String
    ) async throws -> [String]
}

protocol TodayProgressProvider: Sendable {
    func totalXP() async throws -> Int
}

extension RebuildMealRepository: TodayMealRepository {}

struct TodayMealScheduleRepositoryAdapter: MealScheduleRepository {
    let repository: any TodayMealRepository

    func currentState(date: String) async -> MealLoadState {
        await repository.currentState(date: date)
    }

    func refresh(date: String, school: RebuildSchool) async {
        await repository.refresh(date: date, school: school)
    }
}

struct LiveTodayMealRecorder: TodayMealRecorder {
    let useCase: RecordMealUseCase

    func execute(_ command: RecordMealCommand) async throws -> RecordMealResult {
        try await Task.detached(priority: .userInitiated) {
            try useCase.execute(command)
        }.value
    }
}

struct EmptyTodayMealPhotoMetadataStore: TodayMealPhotoMetadataStore {
    func photoIDs(
        date: String,
        normalizedMenuName: String
    ) async throws -> [String] {
        []
    }
}

struct EmptyTodayProgressProvider: TodayProgressProvider {
    func totalXP() async throws -> Int {
        0
    }
}

actor CoreDataTodayProgressProvider: TodayProgressProvider {
    private let repository: RebuildProgressRepository

    init(container: NSPersistentContainer) {
        repository = RebuildProgressRepository(
            context: container.newBackgroundContext()
        )
    }

    func totalXP() async throws -> Int {
        let storedTotal = try repository.totalXP()
        guard let exactTotal = Int(exactly: storedTotal) else {
            throw RebuildRepositoryError.totalXPOverflow
        }
        return exactTotal
    }
}

struct CoreDataTodayMealPhotoMetadataStore: TodayMealPhotoMetadataStore {
    let container: NSPersistentContainer

    func photoIDs(
        date: String,
        normalizedMenuName: String
    ) async throws -> [String] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<RebuildMealRecordManagedObject>(
                entityName: RebuildEntityName.mealRecord
            )
            request.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    NSPredicate(format: "date == %@", date),
                    NSPredicate(
                        format: "normalizedMenuName == %@",
                        normalizedMenuName
                    ),
                ]
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true),
            ]

            var seen = Set<String>()
            var result: [String] = []
            for record in try context.fetch(request) {
                let values = try JSONDecoder().decode(
                    [String].self,
                    from: Data(record.photoIDsJSON.utf8)
                )
                for value in values where seen.insert(value).inserted {
                    result.append(value)
                }
            }
            return result
        }
    }
}

enum TodaySafetyAction: Equatable, Sendable {
    case allergyAvoided
    case guardianCheck
}

enum TodayForestError: Error, Equatable {
    case mealUnavailable
    case allergyOneBiteDisabled
}

@MainActor
final class TodayForestViewModel: ObservableObject {
    typealias Clock = @Sendable () -> Date

    static let activeStatuses: [RebuildEatingStatus] = [
        .finished,
        .oneBite,
        .smelledOnly,
        .difficultToday,
        .allergyAvoided,
    ]

    static let difficultyReasonOrder: [RebuildDifficultyReason] = [
        .smell,
        .texture,
        .taste,
        .appearance,
        .other,
    ]

    let title = "오늘 급식"
    let primaryActionTitle = "오늘 급식 기록하기"

    @Published private(set) var meal: RebuildMealDay?
    @Published private(set) var sourceLabel = "급식을 확인하고 있어요"
    @Published private(set) var isPrimaryActionEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var totalXP = 0
    @Published private(set) var lastGrantedXP = 0
    @Published private(set) var motion: RebuildMotionState = .idle
    @Published private(set) var motionRevision = 0
    @Published private(set) var message: String?

    let dateText: String
    let dateKey: String
    let allergyCodes: [Int]

    private let repository: any TodayMealRepository
    private let recorder: any TodayMealRecorder
    private let photoMetadataStore: any TodayMealPhotoMetadataStore
    private let progressProvider: any TodayProgressProvider
    private let school: RebuildSchool?
    private let now: Clock
    private var progressRevision = 0

    var mealScheduleRepository: any MealScheduleRepository {
        TodayMealScheduleRepositoryAdapter(repository: repository)
    }

    var detailSchool: RebuildSchool? {
        school
    }

    init(
        repository: any TodayMealRepository,
        recorder: any TodayMealRecorder,
        photoMetadataStore: any TodayMealPhotoMetadataStore =
            EmptyTodayMealPhotoMetadataStore(),
        progressProvider: any TodayProgressProvider =
            EmptyTodayProgressProvider(),
        school: RebuildSchool?,
        allergyCodes: [Int],
        date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: @escaping Clock = { Date() }
    ) {
        self.repository = repository
        self.recorder = recorder
        self.photoMetadataStore = photoMetadataStore
        self.progressProvider = progressProvider
        self.school = school
        self.allergyCodes = Array(Set(allergyCodes)).sorted()
        self.now = now

        var localizedCalendar = calendar
        if localizedCalendar.timeZone.identifier == "GMT" {
            localizedCalendar.timeZone =
                TimeZone(identifier: "Asia/Seoul") ?? .current
        }
        let keyFormatter = DateFormatter()
        keyFormatter.calendar = localizedCalendar
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.timeZone = localizedCalendar.timeZone
        keyFormatter.dateFormat = "yyyy-MM-dd"
        dateKey = keyFormatter.string(from: date)

        let displayFormatter = DateFormatter()
        displayFormatter.calendar = localizedCalendar
        displayFormatter.locale = Locale(identifier: "ko_KR")
        displayFormatter.timeZone = localizedCalendar.timeZone
        displayFormatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        dateText = displayFormatter.string(from: date)
    }

    func load() async {
        isLoading = true
        let progressRevisionAtStart = progressRevision
        async let persistedTotalXP = try? progressProvider.totalXP()
        apply(await repository.currentState(date: dateKey))
        if let school {
            await repository.refresh(date: dateKey, school: school)
            apply(await repository.currentState(date: dateKey))
        }
        if let persistedTotalXP = await persistedTotalXP,
           progressRevision == progressRevisionAtStart {
            totalXP = persistedTotalXP
        }
        isLoading = false
    }

    func isAllergyRisk(_ item: RebuildMealItem) -> Bool {
        !Set(item.allergyCodes).isDisjoint(with: allergyCodes)
    }

    func isStatusEnabled(
        _ status: RebuildEatingStatus,
        for item: RebuildMealItem
    ) -> Bool {
        !(isAllergyRisk(item) && status == .oneBite)
    }

    func prioritizedSafetyActions(
        for item: RebuildMealItem
    ) -> [TodaySafetyAction] {
        isAllergyRisk(item)
            ? [.allergyAvoided, .guardianCheck]
            : []
    }

    func record(
        item: RebuildMealItem,
        status: RebuildEatingStatus,
        difficultyReasons: [RebuildDifficultyReason] = [],
        parentShareEnabled: Bool = false
    ) async throws -> RecordMealResult {
        guard meal != nil else {
            throw TodayForestError.mealUnavailable
        }
        guard isStatusEnabled(status, for: item) else {
            throw TodayForestError.allergyOneBiteDisabled
        }

        let normalizedMenuName = item.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let photoIDs = try await photoMetadataStore.photoIDs(
            date: dateKey,
            normalizedMenuName: normalizedMenuName
        )
        let reasons = status == .difficultToday
            ? Self.orderedDifficultyReasons(difficultyReasons)
            : []
        let matchedAllergyCodes = status == .allergyAvoided
            ? Array(Set(item.allergyCodes).intersection(allergyCodes)).sorted()
            : []
        let command = RecordMealCommand(
            recordID: "\(dateKey)|\(normalizedMenuName)|\(status.rawValue)",
            date: dateKey,
            menuName: item.name,
            status: status,
            difficultyReasons: reasons,
            allergyCodes: matchedAllergyCodes,
            photoIDs: photoIDs,
            parentShareEnabled: parentShareEnabled,
            occurredAt: now()
        )
        let result = try await recorder.execute(command)
        progressRevision += 1
        totalXP = result.totalXP
        lastGrantedXP = result.xpGranted
        motion = result.motion
        motionRevision += 1
        message = result.xpGranted > 0
            ? "\(result.xpGranted) XP를 얻었어요!"
            : "오늘 기록을 저장했어요."
        return result
    }

    static func orderedDifficultyReasons(
        _ reasons: [RebuildDifficultyReason]
    ) -> [RebuildDifficultyReason] {
        let selected = Set(reasons)
        return difficultyReasonOrder.filter(selected.contains)
    }

    private func apply(_ state: MealLoadState) {
        switch state {
        case let .cached(cached, _):
            meal = cached
            sourceLabel = "저장된 급식"
            message = "인터넷이 없어도 저장된 급식을 기록할 수 있어요."
        case let .refreshing(cached):
            meal = cached
            sourceLabel = cached == nil ? "급식을 확인하고 있어요" : "저장된 급식"
        case let .live(live):
            meal = live
            sourceLabel = "학교 급식"
            message = nil
        case .empty:
            meal = nil
            sourceLabel = "급식 정보 없음"
            message = "오늘 등록된 급식이 없어요."
        case let .failed(_, cached):
            meal = cached
            sourceLabel = cached == nil
                ? "급식을 불러오지 못했어요"
                : "저장된 급식"
            message = cached == nil
                ? "인터넷 연결을 확인하고 다시 시도해 주세요."
                : "인터넷이 없어 저장된 급식을 보여드려요."
        }
        isPrimaryActionEnabled = meal?.menuItems.isEmpty == false
    }
}
