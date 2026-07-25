import CoreFoundation
import Foundation

enum RebuildContractLoadError: Error, Equatable {
    case missing(String)
    case invalid(String)
}

struct NutritionInsight: Equatable, Sendable {
    struct Nutrient: Equatable, Sendable {
        let id: String
        let childName: String
        let alternatives: [String]
    }

    let ruleVersion: Int
    let nutrients: [Nutrient]
    let omissionCopy: String
    let educationNotice: String
}

struct NutritionRuleEngine {
    private let rules: NutritionRulesDocument

    init(bundle: Bundle = .main) throws {
        try self.init(
            ruleData: try loadRebuildContractData(
                named: "nutrition-rules.json",
                bundle: bundle
            )
        )
    }

    init(ruleData: Data) throws {
        let filename = "nutrition-rules.json"
        guard Self.hasStrictIntegerVersion(ruleData),
              let decoded = try? JSONDecoder().decode(
            NutritionRulesDocument.self,
            from: ruleData
        ), decoded.isValid else {
            throw RebuildContractLoadError.invalid(filename)
        }
        rules = decoded
    }

    func insight(menuName: String) -> NutritionInsight {
        let comparableName = menuName.lowercased()
        var seen = Set<String>()

        for rule in rules.rules
        where rule.keywords.contains(where: comparableName.contains) {
            for nutrientID in rule.nutrients {
                seen.insert(nutrientID)
            }
        }
        let nutrientIDs = rules.nutrientOrder.filter(seen.contains)

        return NutritionInsight(
            ruleVersion: rules.version,
            nutrients: nutrientIDs.compactMap { id in
                rules.nutrients[id].map {
                    NutritionInsight.Nutrient(
                        id: id,
                        childName: $0.childName,
                        alternatives: $0.alternatives
                    )
                }
            },
            omissionCopy: rules.omissionCopy,
            educationNotice: rules.educationNotice
        )
    }

    private static func hasStrictIntegerVersion(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
              let number = root["version"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return false
        }
        let type = String(cString: number.objCType)
        return type != "f" && type != "d"
    }
}

private struct NutritionRulesDocument: Decodable {
    struct Nutrient: Decodable {
        let childName: String
        let alternatives: [String]
    }

    struct Rule: Decodable {
        let keywords: [String]
        let nutrients: [String]
    }

    let version: Int
    let matching: String
    let deduplicateNutrientIds: Bool
    let omissionCopy: String
    let educationNotice: String
    let nutrientOrder: [String]
    let nutrients: [String: Nutrient]
    let rules: [Rule]

    var isValid: Bool {
        guard version == 1,
              matching == "caseInsensitiveSubstring",
              deduplicateNutrientIds,
              omissionCopy == "영양소를 조금 놓칠 수 있어요.",
              educationNotice
                == "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요.",
              !nutrientOrder.isEmpty,
              Set(nutrientOrder).count == nutrientOrder.count,
              Set(nutrientOrder) == Set(nutrients.keys),
              !rules.isEmpty else {
            return false
        }
        guard nutrients.values.allSatisfy({
            !$0.childName.isEmpty
                && !$0.alternatives.isEmpty
                && Set($0.alternatives).count == $0.alternatives.count
                && $0.alternatives.allSatisfy { !$0.isEmpty }
        }) else {
            return false
        }
        return rules.allSatisfy { rule in
            !rule.keywords.isEmpty
                && Set(rule.keywords).count == rule.keywords.count
                && rule.keywords.allSatisfy { !$0.isEmpty }
                && !rule.nutrients.isEmpty
                && Set(rule.nutrients).count == rule.nutrients.count
                && rule.nutrients.allSatisfy(nutrients.keys.contains)
        }
    }
}

func loadRebuildContractData(
    named filename: String,
    bundle: Bundle = .main
) throws -> Data {
    let name = (filename as NSString).deletingPathExtension
    let fileExtension = (filename as NSString).pathExtension
    guard let url = bundle.url(
        forResource: name,
        withExtension: fileExtension,
        subdirectory: "RebuildContracts"
    ) ?? bundle.url(forResource: name, withExtension: fileExtension) else {
        throw RebuildContractLoadError.missing(filename)
    }
    guard let data = try? Data(contentsOf: url) else {
        throw RebuildContractLoadError.invalid(filename)
    }
    return data
}
