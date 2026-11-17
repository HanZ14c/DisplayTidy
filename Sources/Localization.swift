import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"

    var name: String { self == .english ? "English" : "中文" }
    var locale: Locale { Locale(identifier: rawValue) }
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .english
    }
    var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

func L(_ key: String, language: AppLanguage = .current) -> String {
    language.bundle.localizedString(forKey: key, value: key, table: nil)
}

struct AppMessage: Sendable, ExpressibleByStringLiteral {
    let key: String
    let arguments: [AppMessage]
    private let verbatim: Bool

    init(_ key: String, _ arguments: AppMessage...) { self.init(key, arguments: arguments) }
    init(_ key: String, arguments: [AppMessage]) {
        self.key = key; self.arguments = arguments; verbatim = false
    }
    init(stringLiteral value: String) { self.init(value) }
    init(verbatim value: String) { key = value; arguments = []; verbatim = true }
    init(error: Error) {
        self = (error as? PrototypeError)?.message ?? AppMessage(verbatim: error.localizedDescription)
    }
    func text(in language: AppLanguage = .current) -> String {
        if verbatim { return key }
        let format = L(key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments.map { $0.text(in: language) })
    }
}

struct LocalizedRoot<Content: View>: View {
    @ObservedObject var settings: SettingsManager
    let content: Content

    var body: some View {
        content.environment(\.locale, settings.language.locale).id(settings.language)
    }
}

@MainActor
func runLocalizationSelfChecks() throws {
    var tables: [[String: String]] = []
    for language in AppLanguage.allCases {
        guard let url = language.bundle.url(forResource: "Localizable", withExtension: "strings"),
              let table = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String] else {
            throw PrototypeError("Missing localization table: \(language.rawValue)")
        }
        for (key, value) in table {
            guard language != .english || key == value else {
                throw PrototypeError("English source text must match its localization key: \(key)")
            }
            guard key.components(separatedBy: "%@").count == value.components(separatedBy: "%@").count else {
                throw PrototypeError("Translation format mismatch: \(key)")
            }
        }
        tables.append(table)
    }
    guard Set(tables[0].keys) == Set(tables[1].keys) else { throw PrototypeError("Translation keys differ between languages.") }
    guard AppLanguage.allCases.map(\.name) == ["English", "中文"] else {
        throw PrototypeError("Language names must use their native spelling.")
    }
    let example = AppMessage("Current layout: %@ · %@", AppMessage("Below"), AppMessage("Center"))
    guard example.text(in: .english) == "Current layout: Below · Center",
          example.text(in: .chinese) == "当前排列：下方 · 居中",
          AppMessage("Could not apply layout: %@", AppMessage("No active displays.")).text(in: .english)
            == "Could not apply layout: No active displays.",
          AppMessage(verbatim: "LG HDR 4K").text(in: .chinese) == "LG HDR 4K" else {
        throw PrototypeError("Localization resources or nested messages failed.")
    }
    let original = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    defer { UserDefaults.standard.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
    for value in ["", "unsupported"] {
        var preferences = original
        preferences["appLanguage"] = value
        UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
        guard AppLanguage.current == .english, SettingsManager().language == .english else {
            throw PrototypeError("Missing or unsupported language must default to English.")
        }
    }
    for language in AppLanguage.allCases {
        var preferences = original
        preferences["appLanguage"] = language.rawValue
        UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
        guard AppLanguage.current == language, SettingsManager().language == language,
              example.text() == example.text(in: language),
              L("Settings") == (language == .english ? "Settings" : "设置") else {
            throw PrototypeError("Language selection or live message translation failed.")
        }
    }
    print("PASS: English default and source keys, language switching, bundled translations, nested messages and unchanged display names")
}
