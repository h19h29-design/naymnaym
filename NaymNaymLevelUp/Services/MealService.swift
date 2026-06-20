import Foundation

struct MealFetchResult {
    var meals: [MealDay]
    var status: MealDataState
    var message: String?

    var usedSample: Bool {
        status.usesSample
    }

    init(meals: [MealDay], status: MealDataState, message: String? = nil) {
        self.meals = meals
        self.status = status
        self.message = message
    }
}

struct MealService {
    var client: NEISClient
    var sampleProvider: SampleDataProvider

    init(client: NEISClient = NEISClient(), sampleProvider: SampleDataProvider = SampleDataProvider()) {
        self.client = client
        self.sampleProvider = sampleProvider
    }

    func fetchDailyMeal(school: School, date: Date, allowsDemo: Bool = false) async -> MealFetchResult {
        let dateText = DateUtils.apiString(from: date)
        let result = await fetchMonthlyMeals(
            school: school,
            year: Calendar.current.component(.year, from: date),
            month: Calendar.current.component(.month, from: date),
            allowsDemo: allowsDemo
        )
        if let found = result.meals.first(where: { $0.date == dateText }) {
            return MealFetchResult(meals: [found], status: result.status, message: result.message)
        }
        if result.usedSample {
            let sample = sampleProvider.sampleMeal(for: date)
            return MealFetchResult(meals: [sample], status: result.status, message: result.message ?? "오늘은 샘플 급식으로 체험 중이에요.")
        }
        return MealFetchResult(meals: [], status: .noMeal, message: "선택한 날짜의 급식 데이터가 아직 없어요.")
    }

    func fetchMonthlyMeals(school: School, year: Int, month: Int, allowsDemo: Bool = false) async -> MealFetchResult {
        let calendar = Calendar.current
        guard
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
        else {
            return MealFetchResult(meals: [], status: .error, message: "날짜 범위를 만들 수 없어 급식 정보를 조회하지 못했어요.")
        }

        if isSampleSchool(school) {
            if allowsDemo {
                return demoMeals(monthDate: start)
            }
            return MealFetchResult(
                meals: [],
                status: .sampleSchool,
                message: "샘플 학교가 선택되어 있어요. 실제 급식을 보려면 설정에서 실제 학교를 다시 선택해 주세요."
            )
        }

        do {
            NEISDebugLog.info(
                "mealServiceDietInfo params ATPT_OFCDC_SC_CODE=\(school.officeCode) SD_SCHUL_CODE=\(school.schoolCode) MMEAL_SC_CODE=2 MLSV_FROM_YMD=\(DateUtils.apiString(from: start)) MLSV_TO_YMD=\(DateUtils.apiString(from: end))"
            )
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
            NEISDebugLog.info("mealServiceDietInfo hasSection=\(decoded.mealServiceDietInfo != nil) rowCount=\(rows.count) resultCode=\(decoded.RESULT?.CODE ?? "none")")
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
                NEISDebugLog.info("mealServiceDietInfo converted MealDay count=\(meals.count)")
                return MealFetchResult(meals: meals, status: .live, message: nil)
            }

            if let result = decoded.RESULT {
                if result.CODE == "INFO-200" {
                    return MealFetchResult(
                        meals: [],
                        status: .noMeal,
                        message: "\(year)년 \(month)월 중식 데이터가 아직 없어요. 학교 선택이 맞는지 확인해 주세요."
                    )
                }
                return MealFetchResult(
                    meals: [],
                    status: .error,
                    message: "NEIS 응답 오류(\(result.CODE))가 발생했어요. API 키, 학교 설정, 네트워크를 확인해 주세요."
                )
            }

            if decoded.mealServiceDietInfo == nil {
                return MealFetchResult(
                    meals: [],
                    status: .error,
                    message: "NEIS 급식 응답 구조를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
                )
            }

            if !rows.isEmpty {
                return MealFetchResult(
                    meals: [],
                    status: .error,
                    message: "NEIS 급식 메뉴를 읽지 못했어요. 응답 형식이 바뀌었을 수 있어요."
                )
            }
        } catch NEISClientError.missingAPIKey {
            return MealFetchResult(
                meals: [],
                status: .missingAPIKey,
                message: "NEIS API 키가 설정되지 않아 실제 급식 정보를 조회할 수 없어요. 설정 파일을 확인해 주세요."
            )
        } catch {
            NEISDebugLog.info("mealServiceDietInfo error=\(error)")
            return MealFetchResult(
                meals: [],
                status: .error,
                message: "NEIS 급식 정보를 불러오지 못했어요. 네트워크 상태를 확인하고 다시 시도해 주세요."
            )
        }

        return MealFetchResult(
            meals: [],
            status: .noMeal,
            message: "\(year)년 \(month)월 중식 데이터가 아직 없어요. 학교 선택이 맞는지 확인해 주세요."
        )
    }

    private func demoMeals(monthDate: Date) -> MealFetchResult {
        MealFetchResult(
            meals: sampleProvider.sampleMeals(forMonthContaining: monthDate),
            status: .demo,
            message: "체험 모드입니다. 실제 학교 급식이 아닙니다."
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
    var RESULT: NEISResult?
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

private struct NEISResult: Decodable {
    var CODE: String
    var MESSAGE: String?
}
