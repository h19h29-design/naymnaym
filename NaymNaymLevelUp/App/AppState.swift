import Foundation
import CloudKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile?
    @Published var progress: PlayerProgress
    @Published var records: [ChallengeRecord]
    @Published var mealRecords: [MealRecord]
    @Published var mealPhotos: [MealPhotoRecord]
    @Published var parentProfile: ParentProfile
    @Published var childShareLink: ChildLink?
    @Published var todayMeal: MealDay?
    @Published var monthlyMeals: [MealDay] = []
    @Published var isLoadingMeals = false
    @Published var mealMessage: String?
    @Published var mealStatus: MealDataState = .noMeal
    @Published var draftNickname = ""
    @Published var draftSchool: School?
    @Published var draftAllergyCodes: Set<Int> = []
    @Published var draftUserMode: UserMode = .elementary
    @Published var parentSyncMessage: String?
    @Published var parentSyncError: String?
    @Published var isParentSyncing = false

    private let profileStore: UserProfileStore
    private let progressStore: ProgressStore
    private let challengeStore: ChallengeStore
    private let mealRecordStore: MealRecordStore
    private let mealPhotoMetadataStore: MealPhotoMetadataStore
    private let parentProfileStore: ParentProfileStore
    private let childShareLinkStore: ChildShareLinkStore
    private let localPhotoStore: LocalPhotoStore
    private let mealService: MealService
    private let sampleProvider: SampleDataProvider
    private let parentLinkService: CloudKitParentLinkService
    private let automaticallyPublishesParentSharedData: Bool

    init(
        profileStore: UserProfileStore = UserProfileStore(),
        progressStore: ProgressStore = ProgressStore(),
        challengeStore: ChallengeStore = ChallengeStore(),
        mealRecordStore: MealRecordStore = MealRecordStore(),
        mealPhotoMetadataStore: MealPhotoMetadataStore = MealPhotoMetadataStore(),
        parentProfileStore: ParentProfileStore = ParentProfileStore(),
        childShareLinkStore: ChildShareLinkStore = ChildShareLinkStore(),
        localPhotoStore: LocalPhotoStore = LocalPhotoStore(),
        mealService: MealService = MealService(),
        sampleProvider: SampleDataProvider = SampleDataProvider(),
        parentLinkService: CloudKitParentLinkService = CloudKitParentLinkService(),
        automaticallyPublishesParentSharedData: Bool = true
    ) {
        self.profileStore = profileStore
        self.progressStore = progressStore
        self.challengeStore = challengeStore
        self.mealRecordStore = mealRecordStore
        self.mealPhotoMetadataStore = mealPhotoMetadataStore
        self.parentProfileStore = parentProfileStore
        self.childShareLinkStore = childShareLinkStore
        self.localPhotoStore = localPhotoStore
        self.mealService = mealService
        self.sampleProvider = sampleProvider
        self.parentLinkService = parentLinkService
        self.automaticallyPublishesParentSharedData = automaticallyPublishesParentSharedData
        profile = profileStore.load()
        progress = progressStore.load()
        records = challengeStore.load()
        mealRecords = mealRecordStore.load()
        mealPhotos = mealPhotoMetadataStore.load()
        parentProfile = parentProfileStore.load()
        childShareLink = childShareLinkStore.load()
    }

    var hasProfile: Bool {
        profile != nil
    }

    func startDraft() {
        draftNickname = profile?.nickname ?? ""
        draftSchool = profile?.school
        draftAllergyCodes = Set(profile?.selectedAllergyCodes ?? [])
        draftUserMode = profile?.effectiveMode ?? .elementary
    }

    func saveProfile(nickname: String, school: School, allergyCodes: Set<Int>) {
        let newProfile = UserProfile(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            schoolName: school.name,
            officeCode: school.officeCode,
            schoolCode: school.schoolCode,
            regionName: school.region,
            selectedAllergyCodes: allergyCodes.sorted(),
            userMode: draftUserMode,
            themeId: draftUserMode.defaultThemeId,
            isDemoMode: false
        )
        profile = newProfile
        profileStore.save(newProfile)
    }

    func saveParentProfile(nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProfile = UserProfile(
            nickname: trimmed.isEmpty ? "보호자" : trimmed,
            schoolName: "",
            officeCode: "",
            schoolCode: "",
            regionName: "",
            selectedAllergyCodes: [],
            userMode: .parent,
            themeId: UserMode.parent.defaultThemeId,
            isDemoMode: false
        )
        profile = newProfile
        profileStore.save(newProfile)
    }

    var currentMode: UserMode {
        profile?.effectiveMode ?? draftUserMode
    }

    var currentTheme: ThemeProfile {
        profile?.effectiveTheme ?? ThemeProfile.profile(id: draftUserMode.defaultThemeId, mode: draftUserMode)
    }

    var currentSkin: CharacterSkin {
        progress.currentSkin(for: currentMode)
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
        profile.isDemoMode = false
        self.profile = profile
        profileStore.save(profile)
    }

    func updateUserMode(_ mode: UserMode) {
        draftUserMode = mode
        guard var profile else { return }
        profile.userMode = mode
        profile.themeId = mode.defaultThemeId
        self.profile = profile
        profileStore.save(profile)
    }

    func updateTheme(_ theme: ThemeProfile) {
        guard var profile else { return }
        profile.themeId = theme.id
        self.profile = profile
        profileStore.save(profile)
    }

    func updateAllergies(_ codes: Set<Int>) {
        guard var profile else { return }
        profile.selectedAllergyCodes = codes.sorted()
        self.profile = profile
        profileStore.save(profile)
    }

    func startDemoMode(mode: UserMode? = nil) {
        let selectedMode = mode ?? currentMode
        let school = sampleProvider.sampleSchools[0]
        let demoProfile = UserProfile(
            nickname: profile?.nickname ?? "냠냠 도전자",
            schoolName: school.name,
            officeCode: school.officeCode,
            schoolCode: school.schoolCode,
            regionName: school.region,
            selectedAllergyCodes: profile?.selectedAllergyCodes ?? [],
            userMode: selectedMode,
            themeId: selectedMode.defaultThemeId,
            isDemoMode: true
        )
        profile = demoProfile
        profileStore.save(demoProfile)
    }

    func loadMeals(for date: Date = Date()) async {
        guard let profile else { return }
        if profile.effectiveMode == .parent {
            todayMeal = nil
            monthlyMeals = []
            mealStatus = .noMeal
            mealMessage = "부모 모드는 아이 초대 코드를 연결해 기록을 확인해요."
            return
        }

        isLoadingMeals = true
        defer { isLoadingMeals = false }

        let monthResult = await mealService.fetchMonthlyMeals(
            school: profile.school,
            year: Calendar.current.component(.year, from: date),
            month: Calendar.current.component(.month, from: date),
            allowsDemo: profile.isUsingDemoMode
        )
        monthlyMeals = monthResult.meals
        mealStatus = monthResult.status
        mealMessage = monthResult.message

        let todayKey = DateUtils.apiString(from: date)
        todayMeal = monthlyMeals.first(where: { $0.date == todayKey })

        if todayMeal == nil, monthResult.status == .live {
            mealStatus = .noMeal
            mealMessage = "오늘은 급식 정보가 없어요. 방학, 재량휴업일, 급식 미운영일일 수 있어요."
        }
    }

    func isAllergyRisk(_ item: MealItem) -> Bool {
        let selected = Set(profile?.selectedAllergyCodes ?? [])
        return !selected.isDisjoint(with: Set(item.allergyCodes))
    }

    func recordMealInteraction(
        item: MealItem,
        date: String,
        status: EatingStatus,
        reasons: [DifficultyReason] = [],
        photoIds: [String] = [],
        shareWithParent: Bool = false
    ) -> ChallengeOutcome? {
        let isRisk = isAllergyRisk(item)
        let finalStatus = isRisk && status == .oneBite ? EatingStatus.allergyAvoided : status
        let childLinkId = shareWithParent ? childShareLink?.id : nil
        let grant = LevelUpXPPolicy.grant(
            for: item,
            status: finalStatus,
            date: date,
            existingRecords: records,
            existingMealRecords: mealRecords,
            isAllergyRisk: isRisk
        )
        let record = MealRecord(
            date: date,
            menuName: item.name,
            eatingStatus: finalStatus,
            difficultyReasons: reasons,
            allergyCodes: item.allergyCodes,
            photoIds: photoIds,
            parentShareEnabled: shareWithParent,
            childLinkId: childLinkId
        )
        mealRecords.insert(record, at: 0)
        mealRecordStore.save(mealRecords)

        defer {
            if shareWithParent, automaticallyPublishesParentSharedData {
                Task { await publishChildSharedData() }
            }
        }

        return recordChallengeOnly(
            item,
            date: date,
            action: challengeAction(for: finalStatus),
            eatingStatus: finalStatus,
            difficultyReasons: reasons,
            photoIds: photoIds,
            childLinkId: childLinkId,
            parentShareEnabled: shareWithParent,
            grant: grant
        )
    }

    func saveMealPhotoData(_ data: Data, sharedWithParent: Bool = false) throws -> MealPhotoRecord {
        var record = try localPhotoStore.savePhotoData(data, sharedWithParent: sharedWithParent)
        if sharedWithParent {
            record.childLinkId = childShareLink?.id
        }
        mealPhotos.insert(record, at: 0)
        mealPhotoMetadataStore.save(mealPhotos)
        return record
    }

    func photoURL(for record: MealPhotoRecord) -> URL {
        localPhotoStore.url(for: record)
    }

    func deleteMealPhoto(_ record: MealPhotoRecord) {
        localPhotoStore.delete(record)
        mealPhotos.removeAll { $0.id == record.id }
        mealPhotoMetadataStore.save(mealPhotos)
    }

    func updateMealPhotoSharing(_ record: MealPhotoRecord, sharedWithParent: Bool) -> MealPhotoRecord? {
        guard let index = mealPhotos.firstIndex(where: { $0.id == record.id }) else { return nil }
        var updated = mealPhotos[index]
        updated.isSharedWithParent = sharedWithParent
        updated.childLinkId = sharedWithParent ? childShareLink?.id : nil
        mealPhotos[index] = updated
        mealPhotoMetadataStore.save(mealPhotos)
        return updated
    }

    func completeChallenge(
        for item: MealItem,
        date: String? = nil,
        eatingStatus: EatingStatus? = .oneBite,
        difficultyReasons: [DifficultyReason] = [],
        photoIds: [String] = [],
        childLinkId: UUID? = nil
    ) -> ChallengeOutcome {
        let date = date ?? DateUtils.apiString(from: Date())
        let requestedStatus = eatingStatus ?? .oneBite
        let isRisk = isAllergyRisk(item)
        let status = isRisk && requestedStatus == .oneBite ? EatingStatus.allergyAvoided : requestedStatus
        let grant = LevelUpXPPolicy.grant(
            for: item,
            status: status,
            date: date,
            existingRecords: records,
            existingMealRecords: mealRecords,
            isAllergyRisk: isRisk
        )
        return recordChallengeOnly(
            item,
            date: date,
            action: challengeAction(for: status),
            eatingStatus: status,
            difficultyReasons: difficultyReasons,
            photoIds: photoIds,
            childLinkId: childLinkId,
            grant: grant
        ) ?? ChallengeOutcome(
            menuName: item.name,
            gainedExp: 0,
            badgeName: NutritionEstimator.recommendBadge(for: item, status: status),
            damage: 0,
            oldLevel: progress.level,
            newLevel: progress.level,
            skin: progress.currentSkin
        )
    }

    @discardableResult
    func recordSkipped(_ item: MealItem, date: String? = nil) -> ChallengeOutcome? {
        let date = date ?? DateUtils.apiString(from: Date())
        return recordMealInteraction(item: item, date: date, status: isAllergyRisk(item) ? .allergyAvoided : .difficultToday)
    }

    @discardableResult
    func recordAlreadyEats(_ item: MealItem, date: String? = nil) -> ChallengeOutcome? {
        recordMealInteraction(item: item, date: date ?? DateUtils.apiString(from: Date()), status: .finished)
    }

    @discardableResult
    private func recordChallengeOnly(
        _ item: MealItem,
        date: String,
        action: ChallengeRecord.Action,
        eatingStatus: EatingStatus?,
        difficultyReasons: [DifficultyReason] = [],
        photoIds: [String] = [],
        childLinkId: UUID? = nil,
        parentShareEnabled: Bool = false,
        grant: XPGrant
    ) -> ChallengeOutcome? {
        var nextProgress = progress
        let status = eatingStatus ?? .difficultToday
        let outcome = nextProgress.applyGrant(grant, for: item, status: status)
        let record = ChallengeRecord(
            date: date,
            menuName: item.name,
            action: action,
            gainedExp: outcome.gainedExp,
            badgeName: outcome.gainedExp > 0 ? outcome.badgeName : nil,
            nutrients: item.nutrients.isEmpty ? NutritionEstimator.estimateNutrients(for: item) : item.nutrients,
            eatingStatus: eatingStatus,
            difficultyReasons: difficultyReasons,
            photoIds: photoIds,
            childLinkId: childLinkId,
            parentShareEnabled: parentShareEnabled,
            xpBreakdown: outcome.xpBreakdown,
            baseExp: outcome.baseExp,
            bonusExp: outcome.bonusExp,
            xpNotes: outcome.xpNotes
        )
        progress = nextProgress
        records.insert(record, at: 0)
        progressStore.save(progress)
        challengeStore.save(records)
        return outcome.gainedExp > 0 ? outcome : nil
    }

    private func challengeAction(for status: EatingStatus) -> ChallengeRecord.Action {
        switch status {
        case .oneBite:
            return .oneBite
        case .finished, .half:
            return .alreadyEats
        case .smelledOnly, .difficultToday, .allergyAvoided:
            return .skipped
        }
    }

    func resetChallengeRecords() {
        records = []
        mealRecords = []
        challengeStore.clear()
        mealRecordStore.clear()
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
        localPhotoStore.clearAll()
        resetChallengeRecords()
        resetProgress()
        resetProfile()
        todayMeal = nil
        monthlyMeals = []
        mealPhotos = []
        parentProfile = ParentProfile()
        childShareLink = nil
        mealMessage = nil
        mealStatus = .noMeal
        parentSyncMessage = nil
        parentSyncError = nil
        mealPhotoMetadataStore.clear()
        parentProfileStore.clear()
        childShareLinkStore.clear()
    }

    func addLocalChildLink() {
        let index = parentProfile.childLinks.count + 1
        let child = ChildLink(
            childNickname: "\(profile?.nickname ?? "아이") \(index)",
            schoolName: profile?.schoolName ?? "학교 미설정",
            mode: currentMode,
            inviteCode: "LOCAL-PREVIEW-\(index)"
        )
        parentProfile.childLinks.insert(child, at: 0)
        parentProfileStore.save(parentProfile)
    }

    func addChildLink(inviteCode: String, nickname: String, schoolName: String, mode: UserMode) {
        let normalizedCode = parentLinkService.normalizeInviteCode(inviteCode)
        if let validationMessage = parentLinkService.inviteCodeValidationMessage(inviteCode) {
            parentSyncMessage = validationMessage
            parentSyncError = validationMessage
            return
        }
        guard !normalizedCode.isEmpty else { return }

        let child = ChildLink(
            childNickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "아이" : nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            schoolName: schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "학교 미설정" : schoolName.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            inviteCode: normalizedCode
        )

        parentProfile.childLinks.removeAll { $0.inviteCode == normalizedCode }
        parentProfile.childLinks.insert(child, at: 0)
        parentProfileStore.save(parentProfile)
    }

    func activateParentSharing(permissions: SharingPermission) async {
        guard let profile else {
            parentSyncMessage = "먼저 학교와 별명을 등록해 주세요."
            return
        }

        isParentSyncing = true
        defer { isParentSyncing = false }

        var link = childShareLink ?? parentLinkService.makeChildLink(profile: profile, permissions: permissions)
        link.childNickname = profile.nickname
        link.schoolName = profile.schoolName
        link.mode = profile.effectiveMode
        link.permissions = permissions
        link.registeredAt = nil
        link.registrationErrorMessage = nil
        childShareLink = link
        childShareLinkStore.save(link)

        do {
            _ = try await parentLinkService.saveParentLink(link)
            link.registeredAt = Date()
            link.registrationErrorMessage = nil
            childShareLink = link
            childShareLinkStore.save(link)
            parentSyncMessage = "초대 코드가 등록됐어요. 이제 부모에게 보낼 수 있어요."
            parentSyncError = nil
            await publishChildSharedData()
            if parentSyncError == nil {
                parentSyncMessage = "초대 코드가 등록됐어요. 이제 부모에게 보낼 수 있어요."
            }
        } catch {
            let message = cloudKitMessage(
                for: error,
                fallback: "초대 코드를 서버에 등록하지 못했어요. iCloud 로그인과 네트워크를 확인한 뒤 다시 등록해 주세요."
            )
            link.registeredAt = nil
            link.registrationErrorMessage = message
            childShareLink = link
            childShareLinkStore.save(link)
            parentSyncMessage = message
            parentSyncError = message
        }
    }

    func verifyParentInviteRegistration() async {
        guard var link = childShareLink else {
            parentSyncMessage = "먼저 보호자 초대 코드를 만들어 주세요."
            parentSyncError = parentSyncMessage
            return
        }

        isParentSyncing = true
        defer { isParentSyncing = false }

        do {
            let registeredLink = try await parentLinkService.fetchParentLink(inviteCode: link.inviteCode)
            guard registeredLink.id == link.id else {
                let message = "같은 코드로 다른 연결 정보가 조회됐어요. 초대 코드를 다시 생성해 주세요."
                link.registeredAt = nil
                link.registrationErrorMessage = message
                childShareLink = link
                childShareLinkStore.save(link)
                parentSyncMessage = message
                parentSyncError = message
                return
            }

            link.registeredAt = Date()
            link.registrationErrorMessage = nil
            childShareLink = link
            childShareLinkStore.save(link)
            parentSyncMessage = "초대 코드가 서버에서 확인됐어요. 부모에게 보내도 됩니다."
            parentSyncError = nil
        } catch {
            let message = cloudKitMessage(
                for: error,
                fallback: "초대 코드 등록 상태를 확인하지 못했어요. 다시 등록한 뒤 확인해 주세요."
            )
            link.registeredAt = nil
            link.registrationErrorMessage = message
            childShareLink = link
            childShareLinkStore.save(link)
            parentSyncMessage = message
            parentSyncError = message
        }
    }

    func connectChild(inviteCode: String) async -> Bool {
        let normalizedCode = parentLinkService.normalizeInviteCode(inviteCode)
        if let validationMessage = parentLinkService.inviteCodeValidationMessage(inviteCode) {
            parentSyncMessage = validationMessage
            parentSyncError = validationMessage
            return false
        }
        guard !parentProfile.childLinks.contains(where: { $0.inviteCode == normalizedCode }) else {
            parentSyncMessage = "이미 연결된 아이예요. 새로고침으로 기록을 다시 불러올 수 있어요."
            parentSyncError = parentSyncMessage
            return false
        }

        isParentSyncing = true
        defer { isParentSyncing = false }

        do {
            let child = try await parentLinkService.fetchParentLink(inviteCode: normalizedCode)
            upsertChildLink(child)
            parentSyncMessage = "\(child.childNickname) 연결을 완료했어요."
            parentSyncError = nil
            await refreshParentSharedData()
            return true
        } catch CloudKitParentLinkError.inviteCodeNotFound {
            let message = "초대 코드를 찾지 못했어요. 아이 기기에서 코드를 다시 확인해 주세요."
            parentSyncMessage = message
            parentSyncError = message
            return false
        } catch {
            let message = cloudKitMessage(
                for: error,
                fallback: "아이 연결 실패: \(error.localizedDescription)"
            )
            parentSyncMessage = message
            parentSyncError = message
            return false
        }
    }

    func refreshParentSharedData() async {
        guard !parentProfile.childLinks.isEmpty else { return }

        isParentSyncing = true
        defer { isParentSyncing = false }

        var didFail = false
        for child in parentProfile.childLinks {
            do {
                let snapshot = try await parentLinkService.fetchSharedSnapshot(childLink: child)
                merge(snapshot: snapshot, for: child)
            } catch {
                didFail = true
                let message = cloudKitMessage(
                    for: error,
                    fallback: "\(child.childNickname) 기록 동기화 실패: \(error.localizedDescription)"
                )
                parentSyncMessage = message
                parentSyncError = message
            }
        }

        if !didFail {
            parentSyncMessage = "아이 기록을 최신 상태로 불러왔어요."
            parentSyncError = nil
        }
    }

    func publishChildSharedData() async {
        guard let childShareLink else {
            if mealRecords.contains(where: \.parentShareEnabled) {
                parentSyncMessage = "보호자 연결을 먼저 생성해야 공유 기록을 올릴 수 있어요."
            }
            return
        }
        guard childShareLink.isCloudRegistered else {
            if mealRecords.contains(where: \.parentShareEnabled) || records.contains(where: \.parentShareEnabled) || mealPhotos.contains(where: \.isSharedWithParent) {
                parentSyncMessage = "초대 코드가 등록 완료된 뒤 공유 기록을 올릴 수 있어요."
            }
            return
        }

        let sharedMeals = mealRecords.filter { $0.parentShareEnabled && ($0.childLinkId == nil || $0.childLinkId == childShareLink.id) }
        let sharedChallenges = records.filter { $0.parentShareEnabled && ($0.childLinkId == nil || $0.childLinkId == childShareLink.id) }
        let sharedPhotos = mealPhotos.filter { $0.isSharedWithParent && ($0.childLinkId == nil || $0.childLinkId == childShareLink.id) }

        let cloudRecords =
            sharedMeals.compactMap { parentLinkService.makeSharedMealRecord($0, childLink: childShareLink) } +
            sharedChallenges.compactMap { parentLinkService.makeSharedChallengeRecord($0, childLink: childShareLink) } +
            sharedPhotos.compactMap { photo in
                parentLinkService.makeSharedPhotoRecord(photo, childLink: childShareLink, photoURL: localPhotoStore.url(for: photo))
            }

        guard !cloudRecords.isEmpty else { return }

        do {
            try await parentLinkService.saveSharedRecords(cloudRecords)
            parentSyncMessage = "공유 기록을 iCloud에 저장했어요."
            parentSyncError = nil
        } catch {
            let message = cloudKitMessage(
                for: error,
                fallback: "공유 기록 저장 실패: \(error.localizedDescription)"
            )
            parentSyncMessage = message
            parentSyncError = message
        }
    }

    private func upsertChildLink(_ child: ChildLink) {
        parentProfile.childLinks.removeAll { $0.id == child.id || $0.inviteCode == child.inviteCode }
        parentProfile.childLinks.insert(child, at: 0)
        parentProfileStore.save(parentProfile)
    }

    private func merge(snapshot: CloudChildShareSnapshot, for child: ChildLink) {
        mealRecords.removeAll { $0.childLinkId == child.id }
        mealRecords.append(contentsOf: snapshot.mealRecords)
        mealRecords.sort { $0.createdAt > $1.createdAt }
        mealRecordStore.save(mealRecords)

        records.removeAll { $0.childLinkId == child.id }
        records.append(contentsOf: snapshot.challengeRecords)
        records.sort { $0.createdAt > $1.createdAt }
        challengeStore.save(records)

        let oldRemotePhotos = mealPhotos.filter { $0.childLinkId == child.id }
        localPhotoStore.clear(records: oldRemotePhotos)
        mealPhotos.removeAll { $0.childLinkId == child.id }
        for payload in snapshot.photoPayloads {
            if let data = payload.data,
               let imported = try? localPhotoStore.importSharedPhotoData(
                    data,
                    id: payload.record.id,
                    createdAt: payload.record.createdAt,
                    childLinkId: child.id
               ) {
                mealPhotos.append(imported)
            } else {
                mealPhotos.append(payload.record)
            }
        }
        mealPhotos.sort { $0.createdAt > $1.createdAt }
        mealPhotoMetadataStore.save(mealPhotos)
    }

    var parentConnectionDiagnostics: ParentConnectionDiagnostics {
        ParentConnectionDiagnostics(
            hasChildShareLink: childShareLink != nil,
            inviteCode: childShareLink?.inviteCode ?? "생성되지 않음",
            parentChildLinkCount: parentProfile.childLinks.count,
            iCloudCapabilityMessage: "iCloud.com.h19h29.naymnaymlevelup CloudKit public database 사용",
            lastSyncMessage: parentSyncMessage ?? "아직 동기화 기록이 없어요.",
            lastSyncError: parentSyncError ?? "최근 오류 없음",
            permissions: childShareLink?.permissions ?? .defaultChildSafe,
            sharedRecordCount: mealRecords.filter(\.parentShareEnabled).count + records.filter(\.parentShareEnabled).count,
            sharedPhotoCount: mealPhotos.filter(\.isSharedWithParent).count
        )
    }

    var childSummaries: [ChildSummary] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return parentProfile.childLinks.map { link in
            let sharedMealRecords = mealRecords
                .filter(\.parentShareEnabled)
                .filter { $0.childLinkId == link.id }
            let sharedPhotoIds = Set(
                mealPhotos
                    .filter(\.isSharedWithParent)
                    .filter { $0.childLinkId == link.id }
                    .map(\.id)
            )
            let challengeRecords = records
                .filter(\.parentShareEnabled)
                .filter { $0.childLinkId == link.id }
            let weeklyMealRecords = sharedMealRecords.filter { $0.createdAt >= weekAgo }
            let weeklyChallengeRecords = challengeRecords.filter { $0.createdAt >= weekAgo }

            return ChildSummary(
                id: link.id,
                childNickname: link.childNickname,
                schoolName: link.schoolName,
                mode: link.mode,
                todayChallengeCount: challengeRecords.filter { $0.action == .oneBite && $0.date == DateUtils.apiString(from: Date()) }.count,
                allergyWarningMenus: sharedMealRecords.filter { !$0.allergyCodes.isEmpty }.prefix(3).map(\.menuName),
                recentPhotoIds: sharedMealRecords
                    .flatMap(\.photoIds)
                    .filter { sharedPhotoIds.contains($0) }
                    .prefix(3)
                    .map { $0 },
                weeklyRecords: Array(weeklyMealRecords.prefix(12)),
                weeklyChallengeRecords: Array(weeklyChallengeRecords.prefix(12))
            )
        }
    }

    private func cloudKitMessage(for error: Error, fallback: String) -> String {
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated:
                return "iCloud에 로그인되어 있지 않아요. iCloud 계정과 Drive/CloudKit 사용 상태를 확인해 주세요."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud 연결이 원활하지 않아요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
            case .permissionFailure:
                return "iCloud 접근 권한이 부족해요. 앱의 iCloud 권한과 CloudKit 설정을 확인해 주세요."
            case .unknownItem:
                return "초대 코드를 찾지 못했어요. 아이 기기에서 코드를 다시 확인해 주세요."
            default:
                break
            }
        }
        return fallback
    }
}
