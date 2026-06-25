import Foundation

enum NutritionEstimator {
    static func estimateNutrients(for item: MealItem) -> [String] {
        estimateNutrients(forName: item.name)
    }

    static func estimateNutrients(forName name: String) -> [String] {
        let lowered = name.lowercased()
        var nutrients: [String] = []

        if containsAny(lowered, ["나물", "시금치", "콩나물", "채소", "샐러드", "오이", "상추", "깻잎", "브로콜리"]) {
            nutrients.append(contentsOf: ["식이섬유", "비타민"])
        }
        if containsAny(lowered, ["닭", "돼지", "소", "고기", "생선", "계란", "달걀", "두부", "고등어", "멸치"]) {
            nutrients.append(contentsOf: ["단백질", "철분"])
        }
        if containsAny(lowered, ["우유", "멸치", "치즈", "요구르트", "요거트"]) {
            nutrients.append("칼슘")
        }
        if containsAny(lowered, ["밥", "면", "빵", "떡", "잡채", "국수"]) {
            nutrients.append("탄수화물")
        }
        if containsAny(lowered, ["김치", "과일", "토마토", "귤", "사과", "배추"]) {
            nutrients.append("비타민")
        }

        return Array(NSOrderedSet(array: nutrients)) as? [String] ?? nutrients
    }

    static func tags(forName name: String) -> [String] {
        estimateNutrients(forName: name).map { nutrient in
            switch nutrient {
            case "식이섬유": return "장 건강"
            case "비타민": return "면역력"
            case "단백질": return "튼튼 파워"
            case "철분": return "성장 에너지"
            case "칼슘": return "뼈 건강"
            case "탄수화물": return "활동 에너지"
            default: return nutrient
            }
        }
    }

    static func makeStudentExplanation(for item: MealItem) -> String {
        let nutrients = estimateNutrients(for: item)
        let nutrientText = nutrients.isEmpty ? "여러 영양소" : nutrients.joined(separator: "와 ")
        let help = nutrients.map(helpText(for:)).joined(separator: "\n")
        return "\(item.name)을 안 먹으면 \(nutrientText)을 조금 놓칠 수 있어요.\n\(help)\n이 설명은 의학 진단이 아니라 교육용 참고 안내예요."
    }

    static func makeGameStats(for item: MealItem) -> [GameStat] {
        let nutrients = estimateNutrients(for: item)
        return [
            GameStat(name: "성장 에너지", value: nutrients.contains("철분") || nutrients.contains("탄수화물") ? 18 : 8, icon: "bolt.fill"),
            GameStat(name: "집중력", value: nutrients.contains("단백질") ? 16 : 7, icon: "brain.head.profile"),
            GameStat(name: "장 건강", value: nutrients.contains("식이섬유") ? 20 : 6, icon: "leaf.fill"),
            GameStat(name: "면역력", value: nutrients.contains("비타민") ? 18 : 7, icon: "shield.lefthalf.filled"),
            GameStat(name: "튼튼 파워", value: nutrients.contains("단백질") || nutrients.contains("칼슘") ? 20 : 8, icon: "figure.strengthtraining.traditional")
        ]
    }

    static func makeParentSummary(records: [ChallengeRecord]) -> String {
        let sortedRecords = records.sorted { $0.createdAt < $1.createdAt }
        let recordsByMenu = Dictionary(grouping: sortedRecords, by: \.menuName)
        for (menuName, menuRecords) in recordsByMenu {
            guard let firstDifficult = menuRecords.first(where: { isDifficult($0) }),
                  let laterProgress = menuRecords.last(where: { $0.createdAt > firstDifficult.createdAt && isProgress($0) }) else {
                continue
            }
            return changeSummary(menuName: menuName, latest: laterProgress)
        }

        if let safetyRecord = sortedRecords.last(where: { $0.eatingStatus == .allergyAvoided }) {
            return "이번 주에는 \(safetyRecord.menuName)을 알레르기/주의 메뉴로 확인하고 안전하게 피했어요.\n먹지 않은 선택도 안전 기록으로 인정돼요.\n보호자와 학교 안내를 우선 확인해 주세요."
        }

        let challenged = records.filter { $0.action == .oneBite }
        let frequentNutrients = challenged
            .flatMap(\.nutrients)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        let menus = challenged
            .map(\.menuName)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        if challenged.isEmpty {
            return "이번 주에는 아직 변화 흐름을 볼 만큼 기록이 많지 않아요. 먹은 정도와 어려웠던 이유가 쌓이면 아이의 작은 변화를 중심으로 요약해요."
        }

        let menuText = menus.isEmpty ? "몇 가지 반찬" : menus.joined(separator: ", ")
        let nutrientText = frequentNutrients.isEmpty ? "여러 영양소" : frequentNutrients.joined(separator: "와 ")
        return "이번 주에는 \(menuText)을 한 입 도전했어요.\n\(nutrientText)을 조금씩 경험해 보는 변화가 있었어요.\n점수보다 어떤 음식에서 시도가 생겼는지 중심으로 봐 주세요.\n영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다."
    }

    static func recommendBadge(for item: MealItem) -> String {
        recommendBadge(for: item, status: .oneBite)
    }

    static func recommendBadge(for item: MealItem, status: EatingStatus) -> String {
        if status == .allergyAvoided {
            return "안전 확인"
        }
        if status == .finished || status == .half {
            return "균형 기록"
        }
        let nutrients = estimateNutrients(for: item)
        if nutrients.contains("식이섬유") || nutrients.contains("비타민") { return "초록 용사" }
        if nutrients.contains("단백질") || nutrients.contains("철분") { return "단백질 파워" }
        if nutrients.contains("칼슘") { return "칼슘 방패" }
        if nutrients.contains("비타민") { return "비타민 스타" }
        return "한 입 도전자"
    }

    static func expReward(for item: MealItem) -> Int {
        LevelUpXPPolicy.baseBreakdown(for: .oneBite).total
    }

    private static func isDifficult(_ record: ChallengeRecord) -> Bool {
        if let status = record.eatingStatus {
            return status == .difficultToday || status == .smelledOnly
        }
        return record.action == .skipped
    }

    private static func isProgress(_ record: ChallengeRecord) -> Bool {
        guard let status = record.eatingStatus else {
            return record.action == .oneBite
        }
        return status == .smelledOnly || status == .oneBite || status == .half || status == .finished
    }

    private static func changeSummary(menuName: String, latest: ChallengeRecord) -> String {
        switch latest.eatingStatus {
        case .smelledOnly:
            return "이번 주에는 \(menuName)을 어려워했지만, 오늘은 냄새만 맡아보는 단계까지 해냈어요.\n작은 시도도 변화로 기록해 주세요."
        case .oneBite:
            return "이번 주에는 \(menuName)을 어려워했지만, 오늘은 한 입 도전까지 성공했어요.\n집에서는 같은 재료를 작은 양으로 반복해서 만나게 해 주면 도움이 될 수 있어요."
        case .half:
            return "이번 주에는 \(menuName)을 어려워했지만, 오늘은 반 정도 먹기까지 해냈어요.\n양보다 아이가 다시 시도했다는 변화에 집중해 주세요."
        case .finished:
            return "이번 주에는 \(menuName)을 어려워했지만, 오늘은 끝까지 먹어보는 변화가 있었어요.\n잘 먹은 날도 꾸준한 기록으로 인정해 주세요."
        default:
            return "이번 주에는 \(menuName)을 어려워했지만, 다시 살펴보는 기록이 생겼어요.\n점수보다 변화 흐름을 중심으로 봐 주세요."
        }
    }

    private static func helpText(for nutrient: String) -> String {
        switch nutrient {
        case "식이섬유": return "식이섬유는 장 건강에 도움을 줄 수 있어요."
        case "비타민": return "비타민은 몸을 지키는 힘에 도움을 줄 수 있어요."
        case "단백질": return "단백질은 성장과 튼튼 파워에 도움을 줄 수 있어요."
        case "철분": return "철분은 활기와 성장 에너지에 도움을 줄 수 있어요."
        case "칼슘": return "칼슘은 뼈 건강에 도움을 줄 수 있어요."
        case "탄수화물": return "탄수화물은 하루 활동 에너지에 도움을 줄 수 있어요."
        default: return "\(nutrient)은 몸을 고르게 쓰는 데 도움을 줄 수 있어요."
        }
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }
}
