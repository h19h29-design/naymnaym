import XCTest
@testable import NaymNaymLevelUp

final class MealParserTests: XCTestCase {
    func testParseMealItemsSplitsHtmlLineBreaksAndAllergies() {
        let items = MealParser.parseMealItems(rawDishName: "현미밥<br/>닭갈비(5.6.15)<br/>우유(2)")

        XCTAssertEqual(items.map(\.name), ["현미밥", "닭갈비", "우유"])
        XCTAssertEqual(items[1].allergyCodes, [5, 6, 15])
        XCTAssertEqual(items[2].allergyCodes, [2])
    }

    func testParseNutritionExtractsNumbers() {
        let nutrition = MealParser.parseNutrition(text: "탄수화물(g) : 88.2<br/>단백질(g) : 24.1<br/>지방(g) : 15.0<br/>칼슘(mg) : 220.0<br/>철(mg) : 3.4<br/>비타민 : 42")

        XCTAssertEqual(nutrition.carbs, 88.2, accuracy: 0.01)
        XCTAssertEqual(nutrition.protein, 24.1, accuracy: 0.01)
        XCTAssertEqual(nutrition.calcium, 220.0, accuracy: 0.01)
        XCTAssertEqual(nutrition.iron, 3.4, accuracy: 0.01)
    }
}

