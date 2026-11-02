import Foundation

/// 版本号只从 Info.plist 取，避免设置页、关于页、工程配置三处各写一份。
enum AppVersion {
    static var display: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short?.isEmpty == false ? short! : "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// 「1.1.0 (2)」
    static var full: String { "\(display) (\(build))" }
}
