import Foundation

enum MealCoachQuestion: String, Codable, CaseIterable, Identifiable {
    case overview, benefits, omission
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "이 식단 어때?"
        case .benefits: return "먹으면 어떤 도움이 돼?"
        case .omission: return "남기면 어떻게 보완해?"
        }
    }
}

struct MealCoachRequest: Encodable {
    let question: MealCoachQuestion
    let nutrients: [String]
    let wholeMeal: [String: Double]
    let sessionId: String

    init(question: MealCoachQuestion, nutrientIDs: [String], wholeMeal: [String: Double], sessionID: UUID) {
        self.question = question
        nutrients = MealNutrientCanonicalizer.orderedKnownIDs(from: nutrientIDs)
        self.wholeMeal = wholeMeal.filter { ["protein", "carbs", "fat"].contains($0.key) && $0.value.isFinite && $0.value > 0 && $0.value <= 1000 }
        sessionId = sessionID.uuidString
    }

    static func nutrientIDs(meal: RebuildMealDay, selectedIndex: Int) -> [String] {
        let engine = try? NutritionRuleEngine()
        let items = meal.menuItems.indices.contains(selectedIndex) ? [meal.menuItems[selectedIndex]] : meal.menuItems
        return MealNutrientCanonicalizer.orderedKnownIDs(from: items.flatMap { item in
            let explicit = MealNutrientCanonicalizer.orderedKnownIDs(from: item.nutrients)
            return explicit.isEmpty ? (engine?.insight(menuName: item.normalizedPresentationName).nutrients.map(\.id) ?? []) : explicit
        })
    }

    static func wholeMealValues(_ meal: RebuildMealDay, selectedIndex: Int = -1) -> [String: Double] {
        // Never associate a selected dish's nutrient IDs with whole-meal grams.
        guard selectedIndex == -1 else { return [:] }
        let info = meal.nutrition
        let candidates: [(RebuildNutritionInfo.SourceField, Double)] = [(.protein, info.protein), (.carbs, info.carbs), (.fat, info.fat)]
        return Dictionary(uniqueKeysWithValues: candidates.compactMap { field, value in
            guard info.sourceFields.contains(field), info.sourceUnits[field] == "g", value.isFinite, value > 0, value <= 1000 else { return nil }
            return (field.rawValue, value)
        })
    }
}

enum MealCoachError: Error { case invalidResponse, unavailable }

struct MealCoachAnswer: Decodable, Equatable {
    let source: String
    let summary: String
    let benefit: String
    let caution: String
    let tip: String

    static func decode(_ data: Data) throws -> Self {
        let keys: Set<String> = ["source", "summary", "benefit", "caution", "tip"]
        guard data.count <= 16384,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == keys,
              let result = try? JSONDecoder().decode(Self.self, from: data), result.source == "ai",
              [result.summary, result.benefit, result.caution, result.tip].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 240 }) else { throw MealCoachError.invalidResponse }
        return result
    }

    static func basic(question: MealCoachQuestion, nutrientIDs: [String]) -> Self {
        let names = ["fiber": "식이섬유", "vitamin": "비타민", "protein": "단백질", "iron": "철분", "calcium": "칼슘", "carbohydrate": "탄수화물"]
        let roles = ["fiber": "식이섬유는 원활한 배변에 도움을 주는 영양소야.", "vitamin": "비타민은 우리 몸의 여러 기능에 필요해.", "protein": "단백질은 우리 몸을 구성하고 유지하는 데 필요해.", "iron": "철분은 몸에서 산소를 운반하는 데 필요해.", "calcium": "칼슘은 뼈와 치아를 구성하는 데 필요해.", "carbohydrate": "탄수화물은 활동에 필요한 에너지원이야."]
        let ids = MealNutrientCanonicalizer.orderedKnownIDs(from: nutrientIDs)
        let list = ids.compactMap { names[$0] }.joined(separator: " · ")
        let summary: String
        switch question {
        case .overview: summary = list.isEmpty ? "이 메뉴의 대표 영양소 정보는 아직 충분하지 않아." : "대표 영양소로 \(list)를 살펴볼 수 있어. 메뉴 이름을 바탕으로 한 참고 안내야."
        case .benefits: summary = "선택한 음식을 먹으면 어떤 영양소를 만날 수 있는지 알아보자. 실제 섭취량은 먹은 양에 따라 달라."
        case .omission: summary = "남기면 해당 음식에서 얻을 수 있는 영양소를 덜 만날 수 있어. 다른 식사에서 다양한 음식으로 보완할 수도 있어."
        }
        return Self(source: "basic", summary: summary,
                    benefit: ids.compactMap { roles[$0] }.prefix(2).joined(separator: " ").isEmpty ? "영양소 정보를 확인한 뒤 더 자세히 이야기할 수 있어." : ids.compactMap { roles[$0] }.prefix(2).joined(separator: " "),
                    caution: "한 끼만으로 영양 부족을 판단하지 않아. 전체 급식의 영양량을 반찬별 섭취량으로 나눠 계산할 수는 없어.",
                    tip: "억지로 먹지 않아도 괜찮아. 알레르기나 몸이 불편한 음식은 보호자·선생님에게 먼저 확인해 줘.")
    }
}

struct MealCoachConfiguration {
    let endpoint: URL
    let accessToken: String
    private init(trustedEndpoint: URL, accessToken: String) {
        endpoint=trustedEndpoint;self.accessToken=accessToken
    }
    init?(endpoint: String, accessToken: String) {
        guard endpoint == "http://127.0.0.1:64918/v1/meal-coach", let url = URL(string: endpoint),
              accessToken.count >= 32, accessToken.count <= 256,
              accessToken.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { return nil }
        self.endpoint = url; self.accessToken = accessToken
    }
    static func productionDaily() -> Self {
        Self(
            trustedEndpoint: URL(string:"https://rytfbovyyzjlrtzdzldo.supabase.co/functions/v1/meal-coach")!,
            accessToken:""
        )
    }
    static func development() -> Self? {
        #if DEBUG
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = directory.appendingPathComponent("meal-coach-development.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size <= 4096,
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              let endpoint = values["endpoint"], let token = values["accessToken"] else { return nil }
        return Self(endpoint: endpoint, accessToken: token)
        #else
        return nil
        #endif
    }
}

final class MealCoachNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct MealCoachClient {
    var answer: (MealCoachRequest) async throws -> MealCoachAnswer
    static func live(configuration: MealCoachConfiguration) -> Self {
        Self { payload in
            let settings = URLSessionConfiguration.ephemeral
            settings.timeoutIntervalForRequest = 15; settings.timeoutIntervalForResource = 15
            settings.urlCache = nil; settings.httpCookieStorage = nil
            let session = URLSession(configuration: settings, delegate: MealCoachNoRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: configuration.endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MealCoachError.unavailable }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 16384 else { throw MealCoachError.invalidResponse }
                data.append(byte)
            }
            return try MealCoachAnswer.decode(data)
        }
    }
}
