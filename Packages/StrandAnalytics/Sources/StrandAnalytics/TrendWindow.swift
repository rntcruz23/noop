import Foundation

/// Pure selected-window projection shared by trend-card callers.
public enum TrendWindow {
    public struct Point: Equatable, Sendable {
        public let day: String
        public let value: Double

        public init(day: String, value: Double) {
            self.day = day
            self.value = value
        }
    }

    public struct Result: Equatable, Sendable {
        public let points: [Point]
        public let startDay: String?
        public let endDay: String
        public let observed: Int
        public let expected: Int
        public let hasOlderHistory: Bool
    }

    public static func project(rows: [(day: String, value: Double?)],
                               todayKey: String,
                               dayCount: Int?) -> Result {
        guard let today = parse(todayKey) else {
            return Result(points: [], startDay: nil, endDay: todayKey,
                          observed: 0, expected: 0, hasOlderHistory: false)
        }
        var resolved: [String: Double] = [:]
        for row in rows {
            guard let date = parse(row.day), date <= today,
                  let value = row.value, value.isFinite else { continue }
            resolved[row.day] = value
        }
        let sorted = resolved.map { Point(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
        let start: Date?
        if let dayCount {
            guard dayCount > 0 else {
                return Result(points: [], startDay: nil, endDay: todayKey,
                              observed: 0, expected: 0, hasOlderHistory: !sorted.isEmpty)
            }
            start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)
        } else {
            start = sorted.first.flatMap { parse($0.day) }
        }
        guard let start else {
            return Result(points: [], startDay: nil, endDay: todayKey,
                          observed: 0, expected: 0, hasOlderHistory: false)
        }
        let startKey = format(start)
        let points = sorted.filter { $0.day >= startKey && $0.day <= todayKey }
        let expected = (calendar.dateComponents([.day], from: start, to: today).day ?? -1) + 1
        return Result(points: points, startDay: startKey, endDay: todayKey,
                      observed: points.count, expected: max(0, expected),
                      hasOlderHistory: sorted.contains { $0.day < startKey })
    }

    /// Finite observations in the equal calendar interval immediately before the selected window.
    public static func previousPoints(rows: [(day: String, value: Double?)],
                                      todayKey: String,
                                      dayCount: Int?) -> [Point] {
        guard let dayCount, dayCount > 0, let today = parse(todayKey),
              let previousEnd = calendar.date(byAdding: .day, value: -dayCount, to: today) else { return [] }
        return project(rows: rows, todayKey: format(previousEnd), dayCount: dayCount).points
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func parse(_ key: String) -> Date? {
        guard let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }

    private static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        return formatter
    }()
}
