import Foundation

struct UserProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var nickname: String
    var schoolName: String
    var officeCode: String
    var schoolCode: String
    var regionName: String
    var selectedAllergyCodes: [Int]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        nickname: String,
        schoolName: String,
        officeCode: String,
        schoolCode: String,
        regionName: String,
        selectedAllergyCodes: [Int] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.nickname = nickname
        self.schoolName = schoolName
        self.officeCode = officeCode
        self.schoolCode = schoolCode
        self.regionName = regionName
        self.selectedAllergyCodes = selectedAllergyCodes
        self.createdAt = createdAt
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

    init(
        id: UUID = UUID(),
        date: String,
        menuName: String,
        action: Action,
        gainedExp: Int,
        badgeName: String?,
        nutrients: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.menuName = menuName
        self.action = action
        self.gainedExp = gainedExp
        self.badgeName = badgeName
        self.nutrients = nutrients
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

    static let all: [CharacterSkin] = [
        CharacterSkin(id: "skin-1", levelRequired: 1, name: "새싹 냠냠이", description: "작은 새싹 캐릭터", emoji: "🌱", primaryColorHex: "#7BC96F", accessory: "새싹", styleType: "sprout"),
        CharacterSkin(id: "skin-2", levelRequired: 2, name: "탐험 냠냠이", description: "모자 쓴 캐릭터", emoji: "🧢", primaryColorHex: "#6FA8FF", accessory: "모자", styleType: "cap"),
        CharacterSkin(id: "skin-3", levelRequired: 3, name: "용사 냠냠이", description: "망토 캐릭터", emoji: "🦸", primaryColorHex: "#FF9F43", accessory: "망토", styleType: "cape"),
        CharacterSkin(id: "skin-4", levelRequired: 4, name: "방패 냠냠이", description: "방패 든 캐릭터", emoji: "🛡", primaryColorHex: "#67B280", accessory: "방패", styleType: "shield"),
        CharacterSkin(id: "skin-5", levelRequired: 5, name: "히어로 냠냠이", description: "왕관 캐릭터", emoji: "👑", primaryColorHex: "#FFD966", accessory: "왕관", styleType: "crown"),
        CharacterSkin(id: "skin-6", levelRequired: 6, name: "마스터 냠냠이", description: "별 오라 캐릭터", emoji: "⭐", primaryColorHex: "#6FA8FF", accessory: "별 오라", styleType: "aura"),
        CharacterSkin(id: "skin-7", levelRequired: 7, name: "레전드 냠냠이", description: "레전드 황금 캐릭터", emoji: "🏆", primaryColorHex: "#FFCB45", accessory: "황금빛", styleType: "legend")
    ]

    static func skin(for level: Int) -> CharacterSkin {
        all.last(where: { level >= $0.levelRequired }) ?? all[0]
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
