//  CalendarMonthModel.swift

import Foundation

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let number: Int
    var id: Date { date }
}

struct CalendarMonthModel {
    let calendar: Calendar
    let monthStart: Date

    init(containing date: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    func adding(months: Int) -> CalendarMonthModel {
        CalendarMonthModel(
            containing: calendar.date(byAdding: .month, value: months, to: monthStart)!,
            calendar: calendar
        )
    }

    var title: String { monthStart.formatted(.dateTime.month(.wide).year()) }

    /// Whole weeks. nil entries are leading and trailing blanks.
    var cells: [CalendarDay?] {
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [CalendarDay?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            result.append(CalendarDay(date: calendar.date(byAdding: .day, value: d, to: monthStart)!, number: d + 1))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

enum CalendarPhaseLookup {
    static func phase(on date: Date, events: [Event], calendar: Calendar = .current) -> Event.EventType? {
        events.first { calendar.isDate($0.date, inSameDayAs: date) }?.eventType
    }

    static func isPredictedPeriod(_ date: Date, start: Date?, length: Int = 5, calendar: Calendar = .current) -> Bool {
        guard let start else { return false }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? -1
        return d >= 0 && d < length
    }
}
