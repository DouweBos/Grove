// Views/History/CommitDateFormat.swift
// Grove

import Foundation

extension Date {
    /// "just now", "12 min ago", "3 hr ago", "Yesterday", "4 days ago", then "12 Sep" / "12 Sep 2024".
    func commitRelative(now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(self)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(self, inSameDayAs: now) { return "\(Int(seconds / 3600)) hr ago" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days) days ago" }
        if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            return formatted(.dateTime.day().month(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Group title for the commit list: "Today", "Yesterday", "Monday, 21 September".
    var commitDayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return formatted(.dateTime.day().month(.wide).year())
    }

    /// Full timestamp for the detail header.
    var commitTimestamp: String {
        formatted(.dateTime.day().month(.wide).year().hour().minute())
    }
}
