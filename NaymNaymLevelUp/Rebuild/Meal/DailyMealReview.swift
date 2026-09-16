import Foundation
import CryptoKit

enum DailyMealReviewAvailability {
    static let isEnabled = true
}

enum DailyMealReviewInstallationID {
    static let storageKey = "dailyMealReview.installationID.v1"
    static func current(defaults: UserDefaults = .standard) -> UUID {
        if let value=defaults.string(forKey:storageKey),let identifier=UUID(uuidString:value) {return identifier}
        let identifier=UUID()
        defaults.set(identifier.uuidString.lowercased(),forKey:storageKey)
        return identifier
    }
}

struct DailyMealReviewItem: Codable, Equatable { let id: String; let name: String?; let nutrients: [String] }
struct DailyMealReviewRequest: Codable, Equatable {
    let requestId: String
    let sessionId: String
    let items: [DailyMealReviewItem]
    let wholeMeal: [String: Double]
    func validate() throws {
        let known:Set<String>=["fiber","vitamin","protein","iron","calcium","carbohydrate"]
        guard UUID(uuidString:requestId) != nil, UUID(uuidString:sessionId) != nil,
              (1...30).contains(items.count),Set(items.map(\.id)).count==items.count,
              items.allSatisfy({item in
                  item.id.range(of:#"^m(?:[0-9]|[12][0-9])$"#,options:.regularExpression) != nil &&
                  (item.name.map(DailyMealReviewRequest.validMenuName) ?? true) &&
                  (1...6).contains(item.nutrients.count) && Set(item.nutrients).count==item.nutrients.count &&
                  Set(item.nutrients).isSubset(of:known)
              }),Set(wholeMeal.keys).isSubset(of:["protein","carbs","fat"]),
              wholeMeal.values.allSatisfy({$0.isFinite && $0>0 && $0<=1000}) else{throw MealCoachError.invalidResponse}
    }
    static func validMenuName(_ name: String) -> Bool {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count<=30 &&
            trimmed.range(of:#"\p{L}"#,options:.regularExpression) != nil &&
            trimmed.range(of:#"[<>{}\[\]\p{Cc}]|https?:"#,options:[.regularExpression,.caseInsensitive]) == nil
    }
}
struct DailyMealReviewHighlight: Codable, Equatable { let itemId: String; let nutrient: String; let reason: String }
struct DailyMealReviewMenu: Codable, Equatable { let itemId: String; let nutrient: String; let taste: String; let role: String; let point: String }
struct DailyMealReviewResponse: Codable, Equatable {
    let source: String
    let reviewId: String
    let day: String
    let generatedAt: String
    let model: String
    let policyVersion: String
    let summary: String
    let benefit: String?
    let highlights: [DailyMealReviewHighlight]?
    let menus: [DailyMealReviewMenu]?
    let caution: String
    let tip: String
    static func decode(_ data: Data, request: DailyMealReviewRequest) throws -> Self {
        try request.validate()
        guard data.count <= 16384, let json=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw MealCoachError.invalidResponse }
        let named=request.items.allSatisfy {$0.name != nil}
        let expectedKeys: Set<String>
        let version=json["policyVersion"] as? String
        if named && version=="daily-v2" { expectedKeys=["source","reviewId","day","generatedAt","model","policyVersion","summary","menus","caution","tip"] }
        else if request.items.allSatisfy({$0.name==nil}) && version=="daily-v1" { expectedKeys=["source","reviewId","day","generatedAt","model","policyVersion","summary","benefit","highlights","caution","tip"] }
        else { throw MealCoachError.invalidResponse }
        guard Set(json.keys)==expectedKeys,
              let result=try? JSONDecoder().decode(Self.self,from:data), result.source=="ai",
              UUID(uuidString:result.reviewId)==UUID(uuidString:request.requestId), UUID(uuidString:result.reviewId) != nil,
              result.model=="deepseek-v4.1-flash", result.policyVersion==version,
              result.day.range(of:#"^\d{4}-\d{2}-\d{2}$"#,options:.regularExpression) != nil,
              !result.generatedAt.isEmpty,
              [result.summary,result.caution,result.tip].allSatisfy({ validText($0, maximum:240, hasAmounts: !request.wholeMeal.isEmpty) }) else { throw MealCoachError.invalidResponse }
        let timestamp=ISO8601DateFormatter(); timestamp.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        guard timestamp.date(from:result.generatedAt) != nil else { throw MealCoachError.invalidResponse }
        if version=="daily-v1" {
            guard let benefit=result.benefit, let highlights=result.highlights, result.menus==nil,
                  highlights.count<=2, Set(highlights.map(\.itemId)).count==highlights.count,
                  validText(benefit,maximum:240,hasAmounts:!request.wholeMeal.isEmpty),
                  let rawHighlights=json["highlights"] as? [[String:Any]],
                  rawHighlights.allSatisfy({Set($0.keys)==Set(["itemId","nutrient","reason"])}) else { throw MealCoachError.invalidResponse }
            for h in highlights {
                guard let item=request.items.first(where:{$0.id==h.itemId}), item.nutrients.contains(h.nutrient),
                      validText(h.reason,maximum:240,hasAmounts:!request.wholeMeal.isEmpty) else { throw MealCoachError.invalidResponse }
            }
        } else {
            guard let menus=result.menus, result.benefit==nil, result.highlights==nil,
                  menus.count==request.items.count, Set(menus.map(\.itemId)).count==menus.count,
                  let rawMenus=json["menus"] as? [[String:Any]],
                  rawMenus.allSatisfy({Set($0.keys)==Set(["itemId","nutrient","taste","role","point"])}) else { throw MealCoachError.invalidResponse }
            for entry in menus {
                guard let item=request.items.first(where:{$0.id==entry.itemId}), item.nutrients.contains(entry.nutrient),
                      validText(entry.taste,maximum:60,hasAmounts:!request.wholeMeal.isEmpty),
                      validText(entry.role,maximum:120,hasAmounts:!request.wholeMeal.isEmpty),
                      validText(entry.point,maximum:120,hasAmounts:!request.wholeMeal.isEmpty) else { throw MealCoachError.invalidResponse }
            }
        }
        return result
    }
    private static func validText(_ text: String, maximum: Int, hasAmounts: Bool) -> Bool {
        let forbidden=#"\p{N}|그램|칼로리|\b(?:mg|g|kcal)\b|안전|익혀|조리|신선|혈압|혈당|빈혈|https?:|www\.|<|>|키가\s*안\s*커|먹어도\s*괜찮|알레르기.{0,12}(?:무시|극복)|치료|완치|질병|비만|다이어트|살이\s*찌|키가\s*커|결핍입니다|부족합니다|반드시\s*먹|꼭\s*먹|ignore|instructions|system\s*prompt"#
        return !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && text.count<=maximum &&
            text.range(of:"[가-힣]",options:.regularExpression) != nil && text.range(of:forbidden,options:[.regularExpression,.caseInsensitive]) == nil &&
            (hasAmounts || text.range(of:#"(?:이|그|해당|위|주어진|제공된)\s*(?:수치|함량|숫자|수량)"#,options:.regularExpression)==nil)
    }
}
struct DailyMealReviewRecord: Codable, Equatable {
    let contextKey: String
    let day: String
    let meal: RebuildMealDay
    let request: DailyMealReviewRequest
    let response: DailyMealReviewResponse
}
enum DailyMealReviewFactory {
    static func request(meal: RebuildMealDay, allergies: [Int], requestId: UUID = UUID(), sessionId: UUID = UUID()) -> DailyMealReviewRequest {
        let items=meal.menuItems.prefix(15).enumerated().compactMap { index,item -> DailyMealReviewItem? in
            let name=item.normalizedPresentationName
            guard !item.sourceRawText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  DailyMealReviewRequest.validMenuName(name),
                  Set(item.allergyCodes).isDisjoint(with:allergies) else { return nil }
            let nutrients=MealCoachRequest.nutrientIDs(meal:meal,selectedIndex:index)
            return nutrients.isEmpty ? nil : DailyMealReviewItem(id:"m\(index)",name:name,nutrients:nutrients)
        }
        return DailyMealReviewRequest(requestId: requestId.uuidString.lowercased(), sessionId: sessionId.uuidString.lowercased(), items:items, wholeMeal:MealCoachRequest.wholeMealValues(meal))
    }
    static func day(_ date: Date) -> String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=TimeZone(identifier:"Asia/Seoul");formatter.dateFormat="yyyy-MM-dd";return formatter.string(from:date)
    }
    static func visibleHighlights(_ record: DailyMealReviewRecord, allergies: [Int]) -> [DailyMealReviewHighlight] {
        let eligible=Set(request(meal:record.meal,allergies:allergies).items.map(\.id))
        return (record.response.highlights ?? []).filter {eligible.contains($0.itemId)}
    }
    static func visibleMenus(_ record: DailyMealReviewRecord, allergies: [Int]) -> [DailyMealReviewMenu] {
        let eligible=Set(request(meal:record.meal,allergies:allergies).items.map(\.id))
        return (record.response.menus ?? []).filter {eligible.contains($0.itemId)}
    }
    static func contextKey(profileID: String, officeCode: String?, schoolCode: String?) -> String {
        let components=[profileID,officeCode ?? "",schoolCode ?? "","lunch"]
        let data=(try? JSONEncoder().encode(components)) ?? Data()
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    static func role(_ nutrient: String) -> String {
        MealCoachAnswer.basic(question:.benefits,nutrientIDs:[nutrient]).benefit
    }
    static func nutrientLabel(_ nutrient: String) -> String {
        ["fiber":"식이섬유","vitamin":"비타민","protein":"단백질","iron":"철분","calcium":"칼슘","carbohydrate":"탄수화물"][nutrient] ?? nutrient
    }
}
