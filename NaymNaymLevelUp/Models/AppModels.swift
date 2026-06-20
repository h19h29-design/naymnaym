import Foundation

enum UserMode: String, Codable, CaseIterable, Identifiable {
    case elementary
    case middle
    case high
    case parent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elementary: return "초등학생"
        case .middle: return "중학생"
        case .high: return "고등학생"
        case .parent: return "부모"
        }
    }

    var tabTitle: String {
        switch self {
        case .elementary: return "초등"
        case .middle: return "중등"
        case .high: return "고등"
        case .parent: return "부모"
        }
    }

    var systemImage: String {
        switch self {
        case .elementary: return "leaf.fill"
        case .middle: return "gamecontroller.fill"
        case .high: return "chart.line.uptrend.xyaxis"
        case .parent: return "person.2.fill"
        }
    }

    var defaultThemeId: String {
        switch self {
        case .elementary: return "elementary-green"
        case .middle: return "middle-game-dark"
        case .high: return "high-clean-blue"
        case .parent: return "parent-soft-report"
        }
    }
}

struct ThemeProfile: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var targetMode: UserMode
    var primaryColorHex: String
    var accentColorHex: String
    var backgroundColorHex: String
    var cardStyle: String
    var buttonStyle: String
    var characterStyle: String
    var typographyStyle: String

    static let all: [ThemeProfile] = [
        ThemeProfile(
            id: "elementary-green",
            name: "ElementaryGreen",
            targetMode: .elementary,
            primaryColorHex: "#7BC96F",
            accentColorHex: "#FFD966",
            backgroundColorHex: "#FFF9EC",
            cardStyle: "soft",
            buttonStyle: "largeRounded",
            characterStyle: "cuteMascot",
            typographyStyle: "rounded"
        ),
        ThemeProfile(
            id: "middle-game-dark",
            name: "MiddleGameDark",
            targetMode: .middle,
            primaryColorHex: "#1A1F4A",
            accentColorHex: "#7C5CFF",
            backgroundColorHex: "#0B1024",
            cardStyle: "neon",
            buttonStyle: "mission",
            characterStyle: "gameAvatar",
            typographyStyle: "bold"
        ),
        ThemeProfile(
            id: "high-clean-blue",
            name: "HighCleanBlue",
            targetMode: .high,
            primaryColorHex: "#3F6AE6",
            accentColorHex: "#65B7D4",
            backgroundColorHex: "#F4F7FC",
            cardStyle: "clean",
            buttonStyle: "compact",
            characterStyle: "calmMentor",
            typographyStyle: "system"
        ),
        ThemeProfile(
            id: "parent-soft-report",
            name: "ParentSoftReport",
            targetMode: .parent,
            primaryColorHex: "#F06292",
            accentColorHex: "#9C7AC7",
            backgroundColorHex: "#FFF6FA",
            cardStyle: "report",
            buttonStyle: "soft",
            characterStyle: "familyReport",
            typographyStyle: "readable"
        )
    ]

    static func profile(id: String?, mode: UserMode) -> ThemeProfile {
        all.first(where: { $0.id == id }) ?? all.first(where: { $0.targetMode == mode }) ?? all[0]
    }
}

enum MealDataState: String, Codable, Equatable {
    case live
    case noMeal
    case error
    case demo
    case missingAPIKey
    case sampleSchool

    var usesSample: Bool {
        self == .demo
    }
}

enum EatingStatus: String, Codable, CaseIterable, Identifiable {
    case finished
    case half
    case oneBite
    case smelledOnly
    case difficultToday
    case allergyAvoided

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finished: return "다 먹었어요"
        case .half: return "반 정도 먹었어요"
        case .oneBite: return "한 입 먹었어요"
        case .smelledOnly: return "냄새만 맡아봤어요"
        case .difficultToday: return "오늘은 어려웠어요"
        case .allergyAvoided: return "알레르기/주의로 먹지 않았어요"
        }
    }

    var systemImage: String {
        switch self {
        case .finished: return "checkmark.circle.fill"
        case .half: return "circle.lefthalf.filled"
        case .oneBite: return "star.circle.fill"
        case .smelledOnly: return "wind"
        case .difficultToday: return "pause.circle.fill"
        case .allergyAvoided: return "exclamationmark.triangle.fill"
        }
    }
}

enum DifficultyReason: String, Codable, CaseIterable, Identifiable {
    case texture
    case smell
    case spicy
    case color
    case newFood
    case allergy
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .texture: return "식감이 어려워요"
        case .smell: return "냄새가 어려워요"
        case .spicy: return "매워요"
        case .color: return "색이 낯설어요"
        case .newFood: return "처음 보는 음식이에요"
        case .allergy: return "알레르기/주의가 있어요"
        case .other: return "기타"
        }
    }
}

struct UserProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var nickname: String
    var schoolName: String
    var officeCode: String
    var schoolCode: String
    var regionName: String
    var selectedAllergyCodes: [Int]
    var createdAt: Date
    var userMode: UserMode?
    var themeId: String?
    var isDemoMode: Bool?

    init(
        id: UUID = UUID(),
        nickname: String,
        schoolName: String,
        officeCode: String,
        schoolCode: String,
        regionName: String,
        selectedAllergyCodes: [Int] = [],
        createdAt: Date = Date(),
        userMode: UserMode = .elementary,
        themeId: String? = nil,
        isDemoMode: Bool = false
    ) {
        self.id = id
        self.nickname = nickname
        self.schoolName = schoolName
        self.officeCode = officeCode
        self.schoolCode = schoolCode
        self.regionName = regionName
        self.selectedAllergyCodes = selectedAllergyCodes
        self.createdAt = createdAt
        self.userMode = userMode
        self.themeId = themeId ?? userMode.defaultThemeId
        self.isDemoMode = isDemoMode
    }

    var school: School {
        School(
            name: schoolName,
            officeCode: officeCode,
            schoolCode: schoolCode,
            region: regionName,
            address: "",
            schoolType: ""
        )
    }

    var effectiveMode: UserMode {
        userMode ?? .elementary
    }

    var effectiveTheme: ThemeProfile {
        ThemeProfile.profile(id: themeId, mode: effectiveMode)
    }

    var isUsingDemoMode: Bool {
        isDemoMode ?? false
    }
}

struct School: Codable, Hashable, Identifiable {
    var id: String { "\(officeCode)-\(schoolCode)" }
    var name: String
    var officeCode: String
    var schoolCode: String
    var region: String
    var address: String
    var schoolType: String
}

struct MealDay: Codable, Hashable, Identifiable {
    var id: String { date }
    var date: String
    var menuItems: [MealItem]
    var calorie: String
    var nutrition: NutritionInfo
    var isSample: Bool
    var notice: String?

    var dateValue: Date? {
        DateUtils.apiDateFormatter.date(from: date)
    }

    var representativeMenu: String {
        menuItems.prefix(2).map(\.name).joined(separator: ", ")
    }
}

struct MealItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var allergyCodes: [Int]
    var nutrients: [String]
    var tags: [String]
    var sourceRawText: String

    init(
        id: UUID = UUID(),
        name: String,
        allergyCodes: [Int],
        nutrients: [String],
        tags: [String],
        sourceRawText: String
    ) {
        self.id = id
        self.name = name
        self.allergyCodes = allergyCodes
        self.nutrients = nutrients
        self.tags = tags
        self.sourceRawText = sourceRawText
    }
}

struct NutritionInfo: Codable, Hashable {
    var carbs: Double
    var protein: Double
    var fat: Double
    var calcium: Double
    var iron: Double
    var vitamin: Double

    static let empty = NutritionInfo(carbs: 0, protein: 0, fat: 0, calcium: 0, iron: 0, vitamin: 0)
    static let sample = NutritionInfo(carbs: 86.0, protein: 28.0, fat: 18.0, calcium: 220.0, iron: 3.2, vitamin: 42.0)

    var summaryRows: [(String, String)] {
        [
            ("탄수화물", "\(Int(carbs))g"),
            ("단백질", "\(Int(protein))g"),
            ("지방", "\(Int(fat))g"),
            ("칼슘", "\(Int(calcium))mg"),
            ("철분", String(format: "%.1fmg", iron)),
            ("비타민", "\(Int(vitamin))")
        ]
    }
}

struct ChallengeRecord: Codable, Hashable, Identifiable {
    enum Action: String, Codable {
        case skipped
        case oneBite
        case alreadyEats

        var title: String {
            switch self {
            case .skipped: return "안 먹어요"
            case .oneBite: return "한입 도전"
            case .alreadyEats: return "잘 먹어요"
            }
        }

        var iconName: String {
            switch self {
            case .skipped: return "xmark.circle"
            case .oneBite: return "checkmark.seal.fill"
            case .alreadyEats: return "hand.thumbsup.fill"
            }
        }
    }

    var id: UUID
    var date: String
    var menuName: String
    var action: Action
    var gainedExp: Int
    var badgeName: String?
    var nutrients: [String]
    var createdAt: Date
    var eatingStatus: EatingStatus?
    var difficultyReasons: [DifficultyReason]?
    var photoIds: [String]?
    var childLinkId: UUID?

    init(
        id: UUID = UUID(),
        date: String,
        menuName: String,
        action: Action,
        gainedExp: Int,
        badgeName: String?,
        nutrients: [String],
        createdAt: Date = Date(),
        eatingStatus: EatingStatus? = nil,
        difficultyReasons: [DifficultyReason] = [],
        photoIds: [String] = [],
        childLinkId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.menuName = menuName
        self.action = action
        self.gainedExp = gainedExp
        self.badgeName = badgeName
        self.nutrients = nutrients
        self.createdAt = createdAt
        self.eatingStatus = eatingStatus
        self.difficultyReasons = difficultyReasons
        self.photoIds = photoIds
        self.childLinkId = childLinkId
    }
}

struct MealRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var date: String
    var menuName: String
    var eatingStatus: EatingStatus
    var difficultyReasons: [DifficultyReason]
    var allergyCodes: [Int]
    var photoIds: [String]
    var parentShareEnabled: Bool
    var createdAt: Date
    var childLinkId: UUID?

    init(
        id: UUID = UUID(),
        date: String,
        menuName: String,
        eatingStatus: EatingStatus,
        difficultyReasons: [DifficultyReason] = [],
        allergyCodes: [Int] = [],
        photoIds: [String] = [],
        parentShareEnabled: Bool = false,
        createdAt: Date = Date(),
        childLinkId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.menuName = menuName
        self.eatingStatus = eatingStatus
        self.difficultyReasons = difficultyReasons
        self.allergyCodes = allergyCodes
        self.photoIds = photoIds
        self.parentShareEnabled = parentShareEnabled
        self.createdAt = createdAt
        self.childLinkId = childLinkId
    }
}

struct MealPhotoRecord: Codable, Hashable, Identifiable {
    var id: String
    var fileName: String
    var createdAt: Date
    var isSharedWithParent: Bool
    var childLinkId: UUID?

    init(
        id: String,
        fileName: String,
        createdAt: Date,
        isSharedWithParent: Bool,
        childLinkId: UUID? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.isSharedWithParent = isSharedWithParent
        self.childLinkId = childLinkId
    }
}

struct SharingPermission: Codable, Hashable {
    var shareEatingRecords: Bool
    var shareChallengeRecords: Bool
    var shareAllergyWarnings: Bool
    var sharePhotos: Bool

    static let defaultChildSafe = SharingPermission(
        shareEatingRecords: true,
        shareChallengeRecords: true,
        shareAllergyWarnings: true,
        sharePhotos: false
    )
}

struct ChildLink: Codable, Hashable, Identifiable {
    var id: UUID
    var childNickname: String
    var schoolName: String
    var mode: UserMode
    var inviteCode: String
    var permissions: SharingPermission
    var createdAt: Date

    init(
        id: UUID = UUID(),
        childNickname: String,
        schoolName: String,
        mode: UserMode,
        inviteCode: String = String(UUID().uuidString.prefix(6)),
        permissions: SharingPermission = .defaultChildSafe,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.childNickname = childNickname
        self.schoolName = schoolName
        self.mode = mode
        self.inviteCode = inviteCode
        self.permissions = permissions
        self.createdAt = createdAt
    }
}

struct ChildSummary: Codable, Hashable, Identifiable {
    var id: UUID
    var childNickname: String
    var schoolName: String
    var mode: UserMode
    var todayChallengeCount: Int
    var allergyWarningMenus: [String]
    var recentPhotoIds: [String]
    var weeklyRecords: [MealRecord]
}

struct ParentProfile: Codable, Hashable, Identifiable {
    var id: UUID
    var nickname: String
    var childLinks: [ChildLink]

    init(id: UUID = UUID(), nickname: String = "보호자", childLinks: [ChildLink] = []) {
        self.id = id
        self.nickname = nickname
        self.childLinks = childLinks
    }
}

struct PraiseCard: Codable, Hashable, Identifiable {
    var id: UUID
    var message: String
    var createdAt: Date

    static let templates = [
        "오늘 한 입 도전 멋졌어!",
        "어려운 음식도 시도해본 게 대단해.",
        "무리하지 않고 천천히 해보자.",
        "알레르기 확인을 잘했어.",
        "어제보다 한 단계 성장했어."
    ]

    init(id: UUID = UUID(), message: String, createdAt: Date = Date()) {
        self.id = id
        self.message = message
        self.createdAt = createdAt
    }
}

struct PlayerProgress: Codable, Hashable {
    var level: Int
    var exp: Int
    var totalChallenges: Int
    var badges: [String]
    var currentSkinId: String

    init(level: Int = 1, exp: Int = 0, totalChallenges: Int = 0, badges: [String] = [], currentSkinId: String = "skin-1") {
        self.level = level
        self.exp = exp
        self.totalChallenges = totalChallenges
        self.badges = badges
        self.currentSkinId = currentSkinId
    }

    static let levelThresholds = [0, 80, 180, 320, 500, 720, 1000]
    static let levelTitles = [
        "냠냠 새싹",
        "한입 탐험가",
        "냠냠 용사",
        "편식 몬스터 사냥꾼",
        "급식 히어로",
        "영양 마스터",
        "레전드 냠냠러"
    ]

    var title: String {
        Self.title(for: level)
    }

    var currentSkin: CharacterSkin {
        CharacterSkin.skin(for: level)
    }

    func currentSkin(for mode: UserMode) -> CharacterSkin {
        CharacterSkin.skin(for: level, mode: mode)
    }

    var expProgress: Double {
        let current = Self.levelThresholds[max(0, min(level - 1, Self.levelThresholds.count - 1))]
        let next = level < Self.levelThresholds.count ? Self.levelThresholds[level] : Self.levelThresholds.last! + 240
        return max(0, min(1, Double(exp - current) / Double(next - current)))
    }

    var nextLevelText: String {
        if level >= Self.levelThresholds.count {
            return "최고 레벨"
        }
        let next = Self.levelThresholds[level]
        return "\(exp) / \(next) EXP"
    }

    mutating func applyChallenge(for item: MealItem) -> ChallengeOutcome {
        let oldLevel = level
        let gained = NutritionEstimator.expReward(for: item)
        let badge = NutritionEstimator.recommendBadge(for: item)
        exp += gained
        totalChallenges += 1
        if !badges.contains(badge) {
            badges.append(badge)
        }
        level = Self.level(forExp: exp)
        currentSkinId = CharacterSkin.skin(for: level).id

        return ChallengeOutcome(
            menuName: item.name,
            gainedExp: gained,
            badgeName: badge,
            damage: 20 + gained / 2,
            oldLevel: oldLevel,
            newLevel: level,
            skin: currentSkin
        )
    }

    static func level(forExp exp: Int) -> Int {
        var resolved = 1
        for (index, threshold) in levelThresholds.enumerated() where exp >= threshold {
            resolved = index + 1
        }
        return min(resolved, levelThresholds.count)
    }

    static func title(for level: Int) -> String {
        levelTitles[max(0, min(level - 1, levelTitles.count - 1))]
    }
}

struct CharacterSkin: Codable, Hashable, Identifiable {
    var id: String
    var levelRequired: Int
    var name: String
    var description: String
    var emoji: String
    var primaryColorHex: String
    var accessory: String
    var styleType: String
    var targetMode: UserMode = .elementary
    var imageName: String? = nil
    var rarity: String = "common"

    var emojiFallback: String {
        emoji
    }

    static let all: [CharacterSkin] = [
        CharacterSkin(id: "skin-1", levelRequired: 1, name: "냠냠 새싹", description: "밝게 시작하는 공통 마스코트", emoji: "🌱", primaryColorHex: "#7BC96F", accessory: "새싹", styleType: "sprout"),
        CharacterSkin(id: "skin-2", levelRequired: 2, name: "한입 탐험가", description: "낯선 반찬을 살펴보는 탐험가", emoji: "🧢", primaryColorHex: "#6FA8FF", accessory: "모자", styleType: "cap", rarity: "bronze"),
        CharacterSkin(id: "skin-3", levelRequired: 3, name: "냠냠 용사", description: "한 입 도전을 이어가는 용사", emoji: "🦸", primaryColorHex: "#FF9F43", accessory: "망토", styleType: "cape", rarity: "silver"),
        CharacterSkin(id: "skin-4", levelRequired: 4, name: "편식 몬스터 사냥꾼", description: "어려운 메뉴를 차분히 마주하는 캐릭터", emoji: "🛡", primaryColorHex: "#67B280", accessory: "방패", styleType: "shield", rarity: "rare"),
        CharacterSkin(id: "skin-5", levelRequired: 5, name: "급식 히어로", description: "꾸준한 기록으로 성장한 히어로", emoji: "👑", primaryColorHex: "#FFD966", accessory: "왕관", styleType: "crown", rarity: "epic"),
        CharacterSkin(id: "skin-6", levelRequired: 6, name: "영양 마스터", description: "영양 균형을 이해하는 마스터", emoji: "⭐", primaryColorHex: "#6FA8FF", accessory: "별 오라", styleType: "aura", rarity: "legend"),
        CharacterSkin(id: "skin-7", levelRequired: 7, name: "레전드 냠냠러", description: "자기만의 속도로 성장한 레전드", emoji: "🏆", primaryColorHex: "#FFCB45", accessory: "황금빛", styleType: "legend", rarity: "legend")
    ]

    static let middle: [CharacterSkin] = [
        CharacterSkin(id: "middle-1", levelRequired: 1, name: "새내기", description: "게임형 미션을 시작한 새내기", emoji: "🎮", primaryColorHex: "#7C5CFF", accessory: "후드", styleType: "middleRookie", targetMode: .middle),
        CharacterSkin(id: "middle-2", levelRequired: 2, name: "도전자", description: "어려운 반찬을 기록하는 도전자", emoji: "⚡️", primaryColorHex: "#20D6F3", accessory: "이어셋", styleType: "middleChallenger", targetMode: .middle, rarity: "bronze"),
        CharacterSkin(id: "middle-3", levelRequired: 3, name: "집중 모드", description: "미션을 집중해서 이어가는 캐릭터", emoji: "🧭", primaryColorHex: "#2B2E83", accessory: "네온 배지", styleType: "middleFocus", targetMode: .middle, rarity: "rare"),
        CharacterSkin(id: "middle-4", levelRequired: 4, name: "마스터", description: "한 입 미션을 자기 페이스로 해내는 마스터", emoji: "💠", primaryColorHex: "#9B5CFF", accessory: "마스터 장비", styleType: "middleMaster", targetMode: .middle, rarity: "epic")
    ]

    static let high: [CharacterSkin] = [
        CharacterSkin(id: "high-1", levelRequired: 1, name: "시작", description: "자기관리 기록을 시작한 학생", emoji: "📘", primaryColorHex: "#3F6AE6", accessory: "노트", styleType: "highStart", targetMode: .high),
        CharacterSkin(id: "high-2", levelRequired: 2, name: "성장", description: "식사 패턴을 차분히 살피는 성장형 캐릭터", emoji: "📈", primaryColorHex: "#65B7D4", accessory: "백팩", styleType: "highGrowth", targetMode: .high, rarity: "bronze"),
        CharacterSkin(id: "high-3", levelRequired: 3, name: "심화", description: "영양 밸런스를 이해하는 학생", emoji: "🧪", primaryColorHex: "#4A6FA5", accessory: "태블릿", styleType: "highDeep", targetMode: .high, rarity: "rare"),
        CharacterSkin(id: "high-4", levelRequired: 4, name: "엑스퍼트", description: "기록을 자기관리로 연결하는 엑스퍼트", emoji: "🧑‍⚕️", primaryColorHex: "#1F4F8F", accessory: "코트", styleType: "highExpert", targetMode: .high, rarity: "epic")
    ]

    static func skin(for level: Int) -> CharacterSkin {
        all.last(where: { level >= $0.levelRequired }) ?? all[0]
    }

    static func skins(for mode: UserMode) -> [CharacterSkin] {
        switch mode {
        case .middle:
            return middle
        case .high:
            return high
        case .elementary, .parent:
            return all
        }
    }

    static func skin(for level: Int, mode: UserMode) -> CharacterSkin {
        let candidates = skins(for: mode)
        return candidates.last(where: { level >= $0.levelRequired }) ?? candidates[0]
    }
}

struct ChallengeOutcome: Hashable, Identifiable {
    var id = UUID()
    var menuName: String
    var gainedExp: Int
    var badgeName: String
    var damage: Int
    var oldLevel: Int
    var newLevel: Int
    var skin: CharacterSkin

    var didLevelUp: Bool {
        newLevel > oldLevel
    }
}

struct GameStat: Hashable, Identifiable {
    var id: String { name }
    var name: String
    var value: Int
    var icon: String
}
