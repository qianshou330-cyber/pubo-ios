import Foundation

/// Chat-only zh-CN wording and thresholds from the inspected H5 MkTime snapshot.
/// Does not change timestamps, calendars, or any non-chat formatter.
public enum ChatRelativeTimePolicy {
    public static func label(date: Date?, now: Date) -> String {
        guard let date else { return "没有" }
        let ago = now.timeIntervalSince(date)
        guard ago.isFinite else { return "没有" }
        let units: [(Double, String)] = [
            (31_536_000, "年"), (2_592_000, "个月"), (604_800, "周"),
            (86_400, "天"), (3_600, "小时")
        ]
        func number(_ value: Double) -> String {
            String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        for (seconds, unit) in units where ago >= seconds {
            return number((ago / seconds).rounded(.toNearestOrAwayFromZero)) + unit + "前"
        }
        if ago >= 60 { return number((ago / 60).rounded(.towardZero)) + "分钟前" }
        if ago >= 10 { return number(ago.truncatingRemainder(dividingBy: 60).rounded(.towardZero)) + "秒前" }
        if ago >= -3 { return "刚刚" }
        // H5 intentionally uses strict > thresholds for future values (not >=).
        let future = -ago
        for (seconds, unit) in units where future > seconds {
            return number((future / seconds).rounded(.toNearestOrAwayFromZero)) + unit + "后"
        }
        if future > 60 { return number((future / 60).rounded(.towardZero)) + "分钟后" }
        return number(future.truncatingRemainder(dividingBy: 60).rounded(.towardZero)) + "秒后"
    }
}
