import Foundation

enum MealParser {
    static func parseMealItems(rawDishName: String) -> [MealItem] {
        let normalized = rawDishName
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&amp;", with: "&")

        return normalized
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { raw in
                let cleanName = cleanedMealName(raw)
                let allergyCodes = parseAllergyCodes(text: raw)
                let nutrients = NutritionEstimator.estimateNutrients(forName: cleanName)
                return MealItem(
                    name: cleanName,
                    allergyCodes: allergyCodes,
                    nutrients: nutrients,
                    tags: NutritionEstimator.tags(forName: cleanName),
                    sourceRawText: raw
                )
            }
    }

    static func parseAllergyCodes(text: String) -> [Int] {
        let pattern = #"(?<!\d)([1-9]|1[0-9])(?=\.|\)|,|\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return Array(Set(matches.compactMap { match in
            guard let codeRange = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[codeRange])
        })).sorted()
    }

    static func parseNutrition(text: String) -> NutritionInfo {
        func value(after keywords: [String]) -> Double {
            for keyword in keywords {
                if let found = firstNumber(after: keyword, in: text) {
                    return found
                }
            }
            return 0
        }

        return NutritionInfo(
            carbs: value(after: ["탄수화물", "carbohydrate"]),
            protein: value(after: ["단백질", "protein"]),
            fat: value(after: ["지방", "fat"]),
            calcium: value(after: ["칼슘", "calcium"]),
            iron: value(after: ["철", "iron"]),
            vitamin: value(after: ["비타민", "vitamin"])
        )
    }

    static func cleanedMealName(_ raw: String) -> String {
        var value = raw
        value = value.replacingOccurrences(of: #"\([0-9\.\,\s]+\)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[0-9]+\."#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "*", with: "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNumber(after keyword: String, in text: String) -> Double? {
        guard let keywordRange = text.range(of: keyword, options: [.caseInsensitive]) else { return nil }
        let suffix = String(text[keywordRange.upperBound...])
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.firstMatch(in: suffix, range: range),
              let numberRange = Range(match.range(at: 1), in: suffix)
        else {
            return nil
        }
        return Double(suffix[numberRange])
    }
}

