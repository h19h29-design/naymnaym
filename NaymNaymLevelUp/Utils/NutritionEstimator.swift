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
        let skipped = records.filter { $0.action == .skipped }
        let challenged = records.filter { $0.action == .oneBite }
        let source = skipped.isEmpty ? challenged : skipped
        let frequentNutrients = source
            .flatMap(\.nutrients)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        let menus = source
            .map(\.menuName)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        if source.isEmpty {
            return "이번 주에는 아직 안 먹는 반찬이나 한 입 도전 기록이 많지 않아요. 도전 기록이 쌓이면 참고할 수 있는 요약이 생겨요."
        }

        let menuText = menus.isEmpty ? "몇 가지 반찬" : menus.joined(separator: ", ")
        let nutrientText = frequentNutrients.isEmpty ? "여러 영양소" : frequentNutrients.joined(separator: "와 ")
        if skipped.isEmpty {
            return "이번 주에는 \(menuText)을 한 입 도전했어요.\n\(nutrientText)을 조금씩 경험해 보고 있어요.\n집에서는 같은 재료를 작은 양으로 반복해서 만나게 해 주면 도움이 될 수 있어요.\n영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다."
        }
        return "이번 주에는 \(menuText)을 자주 안 먹었어요.\n\(nutrientText)을 놓칠 수 있어요.\n집에서는 김밥 속 채소, 계란말이 속 채소, 과일 간식처럼 부담 없는 방법이 도움이 될 수 있어요.\n영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다."
    }

    static func recommendBadge(for item: MealItem) -> String {
        let nutrients = estimateNutrients(for: item)
        if nutrients.contains("식이섬유") || nutrients.contains("비타민") { return "초록 용사" }
        if nutrients.contains("단백질") || nutrients.contains("철분") { return "단백질 파워" }
        if nutrients.contains("칼슘") { return "칼슘 방패" }
        if nutrients.contains("비타민") { return "비타민 스타" }
        return "한입 도전자"
    }

    static func expReward(for item: MealItem) -> Int {
        max(20, min(45, 18 + estimateNutrients(for: item).count * 8))
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
