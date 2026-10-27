import SwiftUI
import UniformTypeIdentifiers

struct TransactionsCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csv: String

    init(csv: String) {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        self.csv = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}
