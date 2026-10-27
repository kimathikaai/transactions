import Foundation

/// RAII scratch directory for store tests. Deletes itself on `cleanup()`.
final class TempDataDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transactions-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func cleanup() { try? FileManager.default.removeItem(at: url) }
    deinit { cleanup() }
}
