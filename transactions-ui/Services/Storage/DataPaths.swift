import Foundation

/// A named data folder the app can load from. Each profile is a self-contained
/// subdirectory under `Data/` holding the full store set + `csv/`. Switching
/// profiles is just switching the base input folder every store reads from.
enum DataProfile: String, CaseIterable, Identifiable {
    case real
    case demo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .real: return "Real"
        case .demo: return "Demo"
        }
    }

    // MARK: - Persistence (last-selected profile, across launches)

    private static let defaultsKey = "dataProfile"

    /// The last-selected profile. When unset/unrecognized: `.real` if its
    /// folder exists, else `.demo` — so a fresh clone (no `Data/real/`, which
    /// is gitignored) opens on the demo data instead of an empty app.
    static var persisted: DataProfile {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let profile = DataProfile(rawValue: raw)
        else { return realDataExists ? .real : .demo }
        return profile
    }

    private static var realDataExists: Bool {
        FileManager.default.fileExists(atPath: DataPaths.dataDirectory(for: .real).path)
    }

    static func persist(_ profile: DataProfile) {
        UserDefaults.standard.set(profile.rawValue, forKey: defaultsKey)
    }
}

/// Source-tree data-directory resolver. Uses `#filePath` at compile time to
/// find the project's `transactions-ui/Data/` folder — works when running
/// from Xcode against the dev checkout. Release builds trap.
enum DataPaths {

    /// Root directory containing every per-profile data folder (`Data/`).
    static var rootDataDirectory: URL {
        #if DEBUG
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Storage/
            .deletingLastPathComponent()   // Services/
            .deletingLastPathComponent()   // transactions-ui/
            .appendingPathComponent("Data", isDirectory: true)
        #else
        fatalError("Local data files are only supported in DEBUG builds.")
        #endif
    }

    /// The data directory for a given profile (e.g. `Data/real`, `Data/demo`).
    static func dataDirectory(for profile: DataProfile) -> URL {
        rootDataDirectory.appendingPathComponent(profile.rawValue, isDirectory: true)
    }

    static func accountsFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("accounts.json")
    }
    static func reservesFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("reserves.json")
    }
    static func reservationsFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("reservations.json")
    }
    static func reserveEventsFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("reserveEvents.json")
    }
    static func editsFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("edits.json")
    }
    static func reimbursementsFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("reimbursements.json")
    }
    static func categoriesFile(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("categories.json")
    }
    static func csvDirectory(for profile: DataProfile) -> URL {
        dataDirectory(for: profile).appendingPathComponent("csv", isDirectory: true)
    }
    static func csvFile(named name: String, for profile: DataProfile) -> URL {
        csvDirectory(for: profile).appendingPathComponent(name)
    }

    // MARK: - Backward-compatible accessors (resolve to the real profile)

    static var accountsFile: URL   { accountsFile(for: .real) }
    static var reservesFile: URL   { reservesFile(for: .real) }
    static var reservationsFile: URL { reservationsFile(for: .real) }
    static var reserveEventsFile: URL { reserveEventsFile(for: .real) }
    static var editsFile: URL      { editsFile(for: .real) }
    static var reimbursementsFile: URL { reimbursementsFile(for: .real) }
    static var categoriesFile: URL { categoriesFile(for: .real) }

    static func csvFile(named name: String) -> URL {
        csvFile(named: name, for: .real)
    }
}
