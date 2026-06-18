import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile?
    @Published var progress: PlayerProgress
    @Published var records: [ChallengeRecord]
    @Published var todayMeal: MealDay?
    @Published var monthlyMeals: [MealDay] = []
    @Published var isLoadingMeals = false
    @Published var mealMessage: String?
    @Published var draftNickname = ""
    @Published var draftSchool: School?
    @Published var draftAllergyCodes: Set<Int> = []

    private let profileStore: UserProfileStore
    private let progressStore: ProgressStore
    private let challengeStore: ChallengeStore
    private let mealService: MealService

    init(
        profileStore: UserProfileStore = UserProfileStore(),
        progressStore: ProgressStore = ProgressStore(),
        challengeStore: ChallengeStore = ChallengeStore(),
        mealService: MealService = MealService()
    ) {
        self.profileStore = profileStore
        self.progressStore = progressStore
        self.challengeStore = challengeStore
        self.mealService = mealService
        profile = profileStore.load()
        progress = progressStore.load()
        records = challengeStore.load()
    }

    var hasProfile: Bool {
        profile != nil
    }

    func startDraft() {
        draftNickname = profile?.nickname ?? ""
        draftSchool = profile?.school
        draftAllergyCodes = Set(profile?.selectedAllergyCodes ?? [])
    }

    func saveProfile(nickname: String, school: School, allergyCodes: Set<Int>) {
        let newProfile = UserProfile(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            schoolName: school.name,
            officeCode: school.officeCode,
            schoolCode: school.schoolCode,
            regionName: school.region,
            selectedAllergyCodes: allergyCodes.sorted()
        )
        profile = newProfile
        profileStore.save(newProfile)
    }

    func updateNickname(_ nickname: String) {
        guard var profile else { return }
        profile.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profile = profile
        profileStore.save(profile)
    }

    func updateSchool(_ school: School) {
        guard var profile else { return }
        profile.schoolName = school.name
        profile.officeCode = school.officeCode
        profile.schoolCode = school.schoolCode
        profile.regionName = school.region
        self.profile = profile
        profileStore.save(profile)
    }

    func updateAllergies(_ codes: Set<Int>) {
        guard var profile else { return }
        profile.selectedAllergyCodes = codes.sorted()
        self.profile = profile
        profileStore.save(profile)
    }

    func loadMeals(for date: Date = Date()) async {
        guard let profile else { return }
        isLoadingMeals = true
        defer { isLoadingMeals = false }

        let monthResult = await mealService.fetchMonthlyMeals(
            school: profile.school,
            year: Calendar.current.component(.year, from: date),
            month: Calendar.current.component(.month, from: date)
        )
        monthlyMeals = monthResult.meals
        mealMessage = monthResult.message

        let todayKey = DateUtils.apiString(from: date)
        todayMeal = monthlyMeals.first(where: { $0.date == todayKey }) ?? monthResult.meals.first
    }

    func completeChallenge(for item: MealItem, date: String? = nil) -> ChallengeOutcome {
        var nextProgress = progress
        let outcome = nextProgress.applyChallenge(for: item)
        let record = ChallengeRecord(
            date: date ?? DateUtils.apiString(from: Date()),
            menuName: item.name,
            action: .oneBite,
            gainedExp: outcome.gainedExp,
            badgeName: outcome.badgeName,
            nutrients: item.nutrients
        )
        progress = nextProgress
        records.insert(record, at: 0)
        progressStore.save(progress)
        challengeStore.save(records)
        return outcome
    }

    func recordSkipped(_ item: MealItem, date: String? = nil) {
        let record = ChallengeRecord(
            date: date ?? DateUtils.apiString(from: Date()),
            menuName: item.name,
            action: .skipped,
            gainedExp: 0,
            badgeName: nil,
            nutrients: item.nutrients
        )
        records.insert(record, at: 0)
        challengeStore.save(records)
    }

    func recordAlreadyEats(_ item: MealItem, date: String? = nil) {
        let record = ChallengeRecord(
            date: date ?? DateUtils.apiString(from: Date()),
            menuName: item.name,
            action: .alreadyEats,
            gainedExp: 0,
            badgeName: nil,
            nutrients: item.nutrients
        )
        records.insert(record, at: 0)
        challengeStore.save(records)
    }

    func resetChallengeRecords() {
        records = []
        challengeStore.clear()
    }

    func resetProgress() {
        progress = PlayerProgress()
        progressStore.clear()
    }

    func resetProfile() {
        profile = nil
        profileStore.clear()
        draftNickname = ""
        draftSchool = nil
        draftAllergyCodes = []
    }

    func resetAllData() {
        resetChallengeRecords()
        resetProgress()
        resetProfile()
        todayMeal = nil
        monthlyMeals = []
        mealMessage = nil
    }
}
