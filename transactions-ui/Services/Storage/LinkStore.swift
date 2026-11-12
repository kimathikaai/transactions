import Foundation

/// Persists the user's link actions in `links.json`: manual links (including
/// auto-pairs pinned with Keep) and rejections (auto-pairs the user unlinked).
/// Auto-pairs themselves are recomputed on every load and never saved here.
final class LinkStore {

    private let fileURL: URL
    private(set) var links: [TransactionLink] = []
    private(set) var rejections: [LinkRejection] = []

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Reads the file into memory. Missing file → empty.
    func load() throws {
        let file = try AtomicJSONFile.load(LinksFile.self, from: fileURL) ?? LinksFile()
        links = file.links
        rejections = file.rejections
    }

    func save() throws {
        try AtomicJSONFile.save(LinksFile(links: links, rejections: rejections), to: fileURL)
    }

    /// Adds a link and drops any rejection of the same pair, then persists.
    func add(_ link: TransactionLink) throws {
        links.append(link)
        rejections.removeAll { $0.pair == link.pair }
        try save()
    }

    /// Removes the link with the given id. No-op if not found, then persists.
    func removeLink(id: UUID) throws {
        links.removeAll { $0.id == id }
        try save()
    }

    /// Unlinks a manual link: removes it and rejects its pair in one save, so
    /// the auto-pairer doesn't re-propose the pair the user just unlinked.
    func unlink(id: UUID, at date: Date = .now) throws {
        guard let link = links.first(where: { $0.id == id }) else { return }
        links.removeAll { $0.id == id }
        if !rejections.contains(where: { $0.pair == link.pair }) {
            rejections.append(LinkRejection(pair: link.pair, rejectedAt: date))
        }
        try save()
    }

    /// Records an unlinked auto-pair. Rejecting a pair twice keeps one record.
    func reject(_ pair: HashPair, at date: Date = .now) throws {
        guard !rejections.contains(where: { $0.pair == pair }) else { return }
        rejections.append(LinkRejection(pair: pair, rejectedAt: date))
        try save()
    }

    /// Removes every link and rejection that mentions `hash` (used when the
    /// transaction is deleted), then persists. Writes nothing when no record
    /// mentions it, so deleting an unlinked row leaves the file untouched.
    func removeAll(mentioning hash: String) throws {
        guard links.contains(where: { $0.pair.contains(hash) })
                || rejections.contains(where: { $0.pair.contains(hash) })
        else { return }
        links.removeAll { $0.pair.contains(hash) }
        rejections.removeAll { $0.pair.contains(hash) }
        try save()
    }
}
