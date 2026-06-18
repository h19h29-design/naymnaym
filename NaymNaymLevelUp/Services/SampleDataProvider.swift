import Foundation

struct SampleDataProvider {
    let sampleSchools: [School] = [
        School(name: "냠냠중학교", officeCode: "B10", schoolCode: "7010111", region: "서울", address: "서울시 마포구 샘플로 12", schoolType: "중학교"),
        School(name: "레벨업중학교", officeCode: "J10", schoolCode: "7530421", region: "경기", address: "경기도 성남시 레벨업로 25", schoolType: "중학교"),
        School(name: "행복고등학교", officeCode: "C10", schoolCode: "7240180", region: "부산", address: "부산시 해운대구 행복길 7", schoolType: "고등학교"),
        School(name: "한입도전중학교", officeCode: "D10", schoolCode: "7340220", region: "대구", address: "대구시 수성구 도전로 18", schoolType: "중학교")
    ]

    func sampleMeal(for date: Date) -> MealDay {
        let meals = sampleMeals(forMonthContaining: date)
        let apiDate = DateUtils.apiString(from: date)
        return meals.first(where: { $0.date == apiDate }) ?? makeMeal(date: apiDate, names: menuTemplates[0], index: 0)
    }

    func sampleMeals(forMonthContaining date: Date) -> [MealDay] {
        let days = DateUtils.daysInMonth(for: date)
        var meals: [MealDay] = []
        for day in days {
            let weekday = Calendar.current.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }
            let index = meals.count % menuTemplates.count
            meals.append(makeMeal(date: DateUtils.apiString(from: day), names: menuTemplates[index], index: index))
        }
        return meals
    }

    private func makeMeal(date: String, names: [String], index: Int) -> MealDay {
        let items = names.map { makeItem($0) }
        return MealDay(
            date: date,
            menuItems: items,
            calorie: "\(610 + index * 12) kcal",
            nutrition: NutritionInfo(
                carbs: 78 + Double(index % 5) * 4,
                protein: 23 + Double(index % 4) * 3,
                fat: 14 + Double(index % 3) * 2,
                calcium: 190 + Double(index % 6) * 18,
                iron: 2.6 + Double(index % 5) * 0.3,
                vitamin: 36 + Double(index % 7) * 4
            ),
            isSample: true,
            notice: "오늘은 샘플 급식으로 체험 중이에요."
        )
    }

    private func makeItem(_ raw: String) -> MealItem {
        let clean = MealParser.cleanedMealName(raw)
        return MealItem(
            name: clean,
            allergyCodes: MealParser.parseAllergyCodes(text: raw),
            nutrients: NutritionEstimator.estimateNutrients(forName: clean),
            tags: NutritionEstimator.tags(forName: clean),
            sourceRawText: raw
        )
    }

    private let menuTemplates: [[String]] = [
        ["현미밥", "미역국(5.6)", "닭갈비(5.6.15)", "콩나물무침(5)", "배추김치(9)"],
        ["보리밥", "김치찌개(5.9.10)", "계란찜(1)", "시금치나물", "과일"],
        ["차조밥", "맑은콩나물국(5)", "제육볶음(5.6.10)", "토마토샐러드(12)", "우유(2)"],
        ["흑미밥", "된장국(5.6)", "고등어구이(5.6.7)", "멸치볶음(5)", "깍두기(9)"],
        ["잡곡밥", "닭곰탕(15)", "두부조림(5.6)", "오이무침", "배추김치(9)"],
        ["쌀밥", "어묵국(5.6)", "잡채(5.6.10)", "브로콜리무침", "요구르트(2)"],
        ["귀리밥", "소고기무국(16)", "계란말이(1)", "김치볶음(9)", "사과"],
        ["기장밥", "순두부찌개(5.9)", "돼지고기장조림(10)", "상추겉절이", "우유(2)"],
        ["카레라이스(2.5.6.10)", "유부국(5)", "치킨샐러드(1.5.6.15)", "깍두기(9)", "귤"],
        ["수수밥", "북엇국(1)", "소불고기(5.6.16)", "콩나물무침(5)", "배추김치(9)"],
        ["현미밥", "감자수제비국(5.6)", "닭강정(5.6.15)", "토마토샐러드(12)", "우유(2)"],
        ["보리밥", "참치김치찌개(5.9)", "두부구이(5)", "시금치나물", "과일"],
        ["쌀밥", "미역국(5.6)", "돼지불고기(5.6.10)", "오이무침", "요구르트(2)"],
        ["잡곡밥", "콩나물국(5)", "고등어조림(5.6.7)", "멸치볶음(5)", "배추김치(9)"]
    ]
}

