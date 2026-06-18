import Foundation

struct MealFetchResult {
    var meals: [MealDay]
    var usedSample: Bool
    var message: String?
}

struct MealService {
    var client: NEISClient
    var sampleProvider: SampleDataProvider

    init(client: NEISClient = NEISClient(), sampleProvider: SampleDataProvider = SampleDataProvider()) {
        self.client = client
        self.sampleProvider = sampleProvider
    }

    func fetchDailyMeal(school: School, date: Date) async -> MealFetchResult {
        let dateText = DateUtils.apiString(from: date)
        let result = await fetchMonthlyMeals(school: school, year: Calendar.current.component(.year, from: date), month: Calendar.current.component(.month, from: date))
        if let found = result.meals.first(where: { $0.date == dateText }) {
            return MealFetchResult(meals: [found], usedSample: result.usedSample, message: result.message)
        }
        if result.usedSample {
            let sample = sampleProvider.sampleMeal(for: date)
            return MealFetchResult(meals: [sample], usedSample: true, message: result.message ?? "오늘은 샘플 급식으로 체험 중이에요.")
        }
        return MealFetchResult(meals: [], usedSample: false, message: "선택한 날짜의 급식 데이터가 아직 없어요.")
    }

    func fetchMonthlyMeals(school: School, year: Int, month: Int) async -> MealFetchResult {
        let calendar = Calendar.current
        guard
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
        else {
            return sampleFallback(monthDate: Date())
        }

        if isSampleSchool(school) {
            return MealFetchResult(
                meals: [],
                usedSample: true,
                message: "샘플 학교가 선택되어 있어요. 설정에서 실제 학교를 다시 선택해 주세요."
            )
        }

        do {
            let data = try await client.request(
                path: "mealServiceDietInfo",
                query: [
                    "ATPT_OFCDC_SC_CODE": school.officeCode,
                    "SD_SCHUL_CODE": school.schoolCode,
                    "MMEAL_SC_CODE": "2",
                    "MLSV_FROM_YMD": DateUtils.apiString(from: start),
                    "MLSV_TO_YMD": DateUtils.apiString(from: end)
                ]
            )
            let decoded = try JSONDecoder().decode(MealInfoResponse.self, from: data)
            let rows = decoded.mealServiceDietInfo?.flatMap { $0.row ?? [] } ?? []
            let meals = rows.compactMap { row -> MealDay? in
                let items = MealParser.parseMealItems(rawDishName: row.DDISH_NM)
                guard !items.isEmpty else { return nil }
                return MealDay(
                    date: row.MLSV_YMD,
                    menuItems: items,
                    calorie: row.CAL_INFO ?? "정보 없음",
                    nutrition: MealParser.parseNutrition(text: row.NTR_INFO ?? ""),
                    isSample: false,
                    notice: nil
                )
            }

            if !meals.isEmpty {
                return MealFetchResult(meals: meals, usedSample: false, message: nil)
            }
        } catch NEISClientError.missingAPIKey {
            return sampleFallback(monthDate: start)
        } catch {
            return MealFetchResult(
                meals: [],
                usedSample: false,
                message: "NEIS 급식 정보를 불러오지 못했어요. 네트워크 상태를 확인하고 다시 시도해 주세요."
            )
        }

        return MealFetchResult(
            meals: [],
            usedSample: false,
            message: "\(year)년 \(month)월 중식 데이터가 아직 없어요. 학교 선택이 맞는지 확인해 주세요."
        )
    }

    private func sampleFallback(monthDate: Date) -> MealFetchResult {
        MealFetchResult(
            meals: sampleProvider.sampleMeals(forMonthContaining: monthDate),
            usedSample: true,
            message: "API 키가 없어서 샘플 급식으로 체험 중이에요."
        )
    }

    private func isSampleSchool(_ school: School) -> Bool {
        sampleProvider.sampleSchools.contains {
            $0.officeCode == school.officeCode && $0.schoolCode == school.schoolCode
        }
    }
}

private struct MealInfoResponse: Decodable {
    var mealServiceDietInfo: [MealInfoSection]?
}

private struct MealInfoSection: Decodable {
    var row: [MealInfoRow]?
}

private struct MealInfoRow: Decodable {
    var MLSV_YMD: String
    var DDISH_NM: String
    var CAL_INFO: String?
    var NTR_INFO: String?
}
