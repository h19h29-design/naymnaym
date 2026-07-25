import Foundation

enum RebuildMealClientError: Error, Equatable {
    case invalidDate(String)
    case malformedResponse
    case result(code: String, message: String?)
}

struct RebuildMealClient: RebuildMealClientProtocol {
    private let neisClient: NEISClient

    init(neisClient: NEISClient = NEISClient()) {
        self.neisClient = neisClient
    }

    func fetch(
        date: String,
        school: RebuildSchool
    ) async throws -> RebuildMealDay? {
        let neisDate = try Self.neisDate(from: date)
        NEISDebugLog.info(
            "mealServiceDietInfo params ATPT_OFCDC_SC_CODE=\(school.officeCode) "
                + "SD_SCHUL_CODE=\(school.schoolCode) MMEAL_SC_CODE=2 "
                + "MLSV_FROM_YMD=\(neisDate) MLSV_TO_YMD=\(neisDate)"
        )
        let data = try await neisClient.request(
            path: "mealServiceDietInfo",
            query: [
                "ATPT_OFCDC_SC_CODE": school.officeCode,
                "SD_SCHUL_CODE": school.schoolCode,
                "MMEAL_SC_CODE": "2",
                "MLSV_FROM_YMD": neisDate,
                "MLSV_TO_YMD": neisDate,
            ]
        )
        let response = try JSONDecoder().decode(
            RebuildMealInfoResponse.self,
            from: data
        )
        let rows = response.mealServiceDietInfo?.flatMap { $0.row ?? [] } ?? []

        if let row = rows.first(where: { $0.MLSV_YMD == neisDate }) {
            let parsedItems = MealParser.parseMealItems(rawDishName: row.DDISH_NM)
            guard !parsedItems.isEmpty else {
                throw RebuildMealClientError.malformedResponse
            }
            let parsedNutrition = MealParser.parseNutrition(text: row.NTR_INFO ?? "")
            return RebuildMealDay(
                date: date,
                menuItems: parsedItems.map {
                    RebuildMealItem(
                        name: $0.name,
                        allergyCodes: $0.allergyCodes,
                        nutrients: $0.nutrients,
                        tags: $0.tags,
                        sourceRawText: $0.sourceRawText
                    )
                },
                calorie: row.CAL_INFO ?? "정보 없음",
                nutrition: RebuildNutritionInfo(
                    carbs: parsedNutrition.carbs,
                    protein: parsedNutrition.protein,
                    fat: parsedNutrition.fat,
                    calcium: parsedNutrition.calcium,
                    iron: parsedNutrition.iron,
                    vitamin: parsedNutrition.vitamin
                )
            )
        }

        if let result = response.RESULT {
            if result.CODE == "INFO-200" {
                return nil
            }
            throw RebuildMealClientError.result(
                code: result.CODE,
                message: result.MESSAGE
            )
        }

        if response.mealServiceDietInfo != nil {
            return nil
        }
        throw RebuildMealClientError.malformedResponse
    }

    private static func neisDate(from date: String) throws -> String {
        let components = date.split(separator: "-", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            components[0].count == 4,
            components[1].count == 2,
            components[2].count == 2,
            components.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else {
            throw RebuildMealClientError.invalidDate(date)
        }

        guard
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2]),
            year > 0
        else {
            throw RebuildMealClientError.invalidDate(date)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard
            let parsedDate = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
            )
        else {
            throw RebuildMealClientError.invalidDate(date)
        }
        let parsedComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: parsedDate
        )
        guard
            parsedComponents.year == year,
            parsedComponents.month == month,
            parsedComponents.day == day
        else {
            throw RebuildMealClientError.invalidDate(date)
        }
        return components.joined()
    }
}

private struct RebuildMealInfoResponse: Decodable {
    let mealServiceDietInfo: [RebuildMealInfoSection]?
    let RESULT: RebuildNEISResult?
}

private struct RebuildMealInfoSection: Decodable {
    let row: [RebuildMealInfoRow]?
}

private struct RebuildMealInfoRow: Decodable {
    let MLSV_YMD: String
    let DDISH_NM: String
    let CAL_INFO: String?
    let NTR_INFO: String?
}

private struct RebuildNEISResult: Decodable {
    let CODE: String
    let MESSAGE: String?
}
