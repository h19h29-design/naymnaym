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
    let foodCategory: MealFoodCategory?
    let confidence: NutritionMatchConfidence?
    let iconKey: String?
    let representativeNutrientIDs: [String]

    init(
        ruleVersion: Int,
        nutrients: [Nutrient],
        omissionCopy: String,
        educationNotice: String,
        foodCategory: MealFoodCategory? = nil,
        confidence: NutritionMatchConfidence? = nil,
        iconKey: String? = nil,
        representativeNutrientIDs: [String] = []
    ) {
        self.ruleVersion = ruleVersion
        self.nutrients = nutrients
        self.omissionCopy = omissionCopy
        self.educationNotice = educationNotice
        self.foodCategory = foodCategory
        self.confidence = confidence
        self.iconKey = iconKey
        self.representativeNutrientIDs = representativeNutrientIDs
    }
}

struct NutritionRulePresentationMatch: Equatable, Sendable {
    let matchKind: NutritionMatchConfidence
    let confidence: NutritionMatchConfidence
    let foodCategory: MealFoodCategory?
    let iconKey: String?
    let representativeNutrientIDs: [String]?
    let nutrientIDs: [String]
}

struct NutritionRuleEngine {
    static let supportedRuleVersion = 1
    static let unavailableFallbackRuleVersion = 0

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
        let presentationMatches = presentationMatches(menuName: menuName)
        let presentationMatch = presentationMatches.first {
            $0.matchKind == .exact
        } ?? presentationMatches.first {
            $0.matchKind == .keyword
        }

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
            educationNotice: rules.educationNotice,
            foodCategory: presentationMatch?.foodCategory,
            confidence: presentationMatch?.confidence,
            iconKey: presentationMatch?.iconKey,
            representativeNutrientIDs: presentationMatch?.representativeNutrientIDs ?? []
        )
    }

    func presentationMatches(menuName: String) -> [NutritionRulePresentationMatch] {
        let comparableName = menuName.lowercased()
        let compactName = compact(comparableName)
        return rules.rules.compactMap { rule in
            let exact = rule.keywords.contains {
                compact($0.lowercased()) == compactName
            }
            let keyword = rule.keywords.contains {
                comparableName.contains($0.lowercased())
            }
            guard exact || keyword else { return nil }
            let matchKind: NutritionMatchConfidence = exact ? .exact : .keyword
            return NutritionRulePresentationMatch(
                matchKind: matchKind,
                confidence: Self.resolvedConfidence(
                    matchKind: matchKind,
                    declared: rule.confidence.flatMap(
                        NutritionMatchConfidence.init(rawValue:)
                    )
                ),
                foodCategory: rule.foodCategory.flatMap(MealFoodCategory.init(rawValue:)),
                iconKey: rule.iconKey,
                representativeNutrientIDs: rule.representativeNutrientIDs,
                nutrientIDs: rule.nutrients
            )
        }
    }

    func orderedKnownNutrientIDs(from values: [String]) -> [String] {
        MealNutrientCanonicalizer.orderedKnownIDs(from: values)
    }

    var ruleVersion: Int {
        rules.version
    }

    private func compact(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber }
    }

    private static func resolvedConfidence(
        matchKind: NutritionMatchConfidence,
        declared: NutritionMatchConfidence?
    ) -> NutritionMatchConfidence {
        switch matchKind {
        case .exact:
            // Exact text evidence remains stronger than a broader declared
            // rule hint, while keyword matches can opt into a safer/lower or
            // explicitly verified confidence from the contract.
            return .exact
        case .keyword:
            return declared ?? .keyword
        case .fallback:
            return .fallback
        }
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
        let foodCategory: String?
        let confidence: String?
        let iconKey: String?
        let representativeNutrientIDs: [String]?

        private enum CodingKeys: String, CodingKey {
            case keywords
            case nutrients
            case foodCategory
            case confidence
            case iconKey
            case representativeNutrientIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keywords = try container.decode([String].self, forKey: .keywords)
            nutrients = try container.decode([String].self, forKey: .nutrients)
            if container.contains(.foodCategory) {
                foodCategory = try container.decode(String.self, forKey: .foodCategory)
            } else {
                foodCategory = nil
            }
            if container.contains(.confidence) {
                confidence = try container.decode(String.self, forKey: .confidence)
            } else {
                confidence = nil
            }
            if container.contains(.iconKey) {
                iconKey = try container.decode(String.self, forKey: .iconKey)
            } else {
                iconKey = nil
            }
            if container.contains(.representativeNutrientIDs) {
                representativeNutrientIDs = try container.decode(
                    [String].self,
                    forKey: .representativeNutrientIDs
                )
            } else {
                representativeNutrientIDs = nil
            }
        }
    }

    let version: Int
    let matching: String
    let deduplicateNutrientIds: Bool
    let omissionCopy: String
    let educationNotice: String
    let nutrientOrder: [String]
    let nutrients: [String: Nutrient]
    let rules: [Rule]
    let iconManifest: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case version
        case matching
        case deduplicateNutrientIds
        case omissionCopy
        case educationNotice
        case nutrientOrder
        case nutrients
        case rules
        case iconManifest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        matching = try container.decode(String.self, forKey: .matching)
        deduplicateNutrientIds = try container.decode(Bool.self, forKey: .deduplicateNutrientIds)
        omissionCopy = try container.decode(String.self, forKey: .omissionCopy)
        educationNotice = try container.decode(String.self, forKey: .educationNotice)
        nutrientOrder = try container.decode([String].self, forKey: .nutrientOrder)
        nutrients = try container.decode([String: Nutrient].self, forKey: .nutrients)
        rules = try container.decode([Rule].self, forKey: .rules)
        if container.contains(.iconManifest) {
            iconManifest = try container.decode(
                [String: String].self,
                forKey: .iconManifest
            )
        } else {
            iconManifest = nil
        }
    }

    var isValid: Bool {
        guard version == 1,
              matching == "caseInsensitiveSubstring",
              deduplicateNutrientIds,
              omissionCopy == "영양소를 조금 놓칠 수 있어요.",
              educationNotice
                == "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요.",
              !nutrientOrder.isEmpty,
              nutrientOrder == MealNutrientCanonicalizer.orderedIDs,
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
        guard rules.allSatisfy({ rule in
            !rule.keywords.isEmpty
                && Set(rule.keywords).count == rule.keywords.count
                && rule.keywords.allSatisfy { !$0.isEmpty }
                && !rule.nutrients.isEmpty
                && Set(rule.nutrients).count == rule.nutrients.count
                && rule.nutrients.allSatisfy(nutrients.keys.contains)
        }) else {
            return false
        }

        guard rules.allSatisfy({ rule in
            if let foodCategory = rule.foodCategory,
               MealFoodCategory(rawValue: foodCategory) == nil {
                return false
            }
            if let confidence = rule.confidence,
               NutritionMatchConfidence(rawValue: confidence) == nil {
                return false
            }
            if let iconKey = rule.iconKey,
               MealVisualIconManifest.systemSymbol(for: iconKey) == nil {
                return false
            }
            if let representativeNutrientIDs = rule.representativeNutrientIDs {
                guard !representativeNutrientIDs.isEmpty,
                      Set(representativeNutrientIDs).count == representativeNutrientIDs.count,
                      representativeNutrientIDs.allSatisfy(nutrients.keys.contains)
                else {
                    return false
                }
            }
            return true
        }) else {
            return false
        }

        if let iconManifest {
            guard Set(iconManifest.keys) == MealVisualIconManifest.semanticKeys,
                  iconManifest.allSatisfy({ key, value in
                      MealVisualIconManifest.systemSymbol(for: key) == value
                  }) else {
                return false
            }
        }
        return true
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
