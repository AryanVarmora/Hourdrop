import Foundation

enum Format {
    /// 1234 ml -> "1.2 L"
    static func liters(_ ml: Int) -> String {
        String(format: "%.1f L", Double(ml) / 1000)
    }

    /// US fluid ounces, e.g. 665 ml -> "22.5 oz".
    static func ounces(_ ml: Int) -> String {
        String(format: "%.1f oz", Double(ml) / 29.5735)
    }

    /// Small amounts in ml (to the nearest 10), bigger ones in liters: "300 ml", "1.2 L".
    static func amount(_ ml: Int) -> String {
        let ml = abs(ml)
        return ml < 1000 ? "\((ml + 5) / 10 * 10) ml" : liters(ml)
    }

    /// "9 AM", "12 PM", "10 PM"
    static func hour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}
