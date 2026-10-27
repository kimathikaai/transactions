import Foundation

/// Small helper that wraps `JSONEncoder`/`JSONDecoder` with the project-wide
/// conventions (pretty-printed, sorted keys, ISO-8601 dates) and performs
/// atomic writes so a crash mid-write cannot leave a corrupt file on disk.
enum AtomicJSONFile {

    static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    /// Returns nil when the file does not exist. Throws on IO or decode error.
    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder().decode(type, from: data)
    }

    /// Atomically writes `value` to `url`. Creates any missing parent
    /// directories. Uses `Data.write(options: .atomic)` which writes to a
    /// temp file and renames — crash-safe.
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder().encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
