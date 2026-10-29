import Foundation

enum Fmt {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static let hm = formatter("H:mm")
    static let md = formatter("M/d")
    static let ymd = formatter("yyyy/M/d")
    static let dayChip = formatter("M月d日(E)")
    static let dayChipYear = formatter("yyyy年M月d日(E)")
    static let storage: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func listTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return hm.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨日" }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) { return md.string(from: date) }
        return ymd.string(from: date)
    }

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今日" }
        if cal.isDateInYesterday(date) { return "昨日" }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) { return dayChip.string(from: date) }
        return dayChipYear.string(from: date)
    }
}
