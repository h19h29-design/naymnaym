import Foundation

enum AllergyMap {
    static let names: [Int: String] = [
        1: "난류",
        2: "우유",
        3: "메밀",
        4: "땅콩",
        5: "대두",
        6: "밀",
        7: "고등어",
        8: "게",
        9: "새우",
        10: "돼지고기",
        11: "복숭아",
        12: "토마토",
        13: "아황산류",
        14: "호두",
        15: "닭고기",
        16: "쇠고기",
        17: "오징어",
        18: "조개류",
        19: "잣"
    ]

    static var allCodes: [Int] {
        Array(1...19)
    }

    static func name(for code: Int) -> String {
        names[code] ?? "\(code)번"
    }

    static func label(for code: Int) -> String {
        "\(code) \(name(for: code))"
    }
}

