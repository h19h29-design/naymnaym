import Foundation

enum DateUtils {
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
    }()

    static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }()

    static func apiString(from date: Date) -> String {
        apiDateFormatter.string(from: date)
    }

    static func displayString(fromAPIString value: String) -> String {
        guard let date = apiDateFormatter.date(from: value) else { return value }
        return displayDateFormatter.string(from: date)
    }

    static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func daysInMonth(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let start = startOfMonth(for: date)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    static func isSameDay(_ first: Date, _ second: Date) -> Bool {
        Calendar.current.isDate(first, inSameDayAs: second)
    }
}

