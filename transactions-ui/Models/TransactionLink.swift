import Foundation

/// What a link means. `transfer` joins the two sides of one movement of money;
/// `related` covers everything else (e.g. employer RRSP/ESPP contributions
/// linked to a paycheque), with the specifics in the link's note.
enum LinkKind: String, Codable, Sendable {
    case transfer
    case related
}

/// An unordered pair of transaction `contentHash`es, stored sorted (`a <= b`)
/// so the same two transactions always produce the same pair.
struct HashPair: Hashable, Sendable {
    let a: String
    let b: String

    init(_ x: String, _ y: String) {
        if x <= y { a = x; b = y } else { a = y; b = x }
    }

    var id: String { "\(a)|\(b)" }

    func contains(_ hash: String) -> Bool { a == hash || b == hash }

    /// The side that isn't `hash`.
    func other(than hash: String) -> String { a == hash ? b : a }
}

/// A user-made link between two transactions: an undirected edge keyed by
/// `contentHash`. Direction comes from the transactions' signs, not the link.
/// Auto-pairs are never stored — only links the user made or pinned (Keep).
struct TransactionLink: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var hashA: String
    var hashB: String
    var kind: LinkKind
    var note: String?
    var createdAt: Date

    init(id: UUID = UUID(), pair: HashPair, kind: LinkKind, note: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.hashA = pair.a
        self.hashB = pair.b
        self.kind = kind
        self.note = note
        self.createdAt = createdAt
    }

    var pair: HashPair { HashPair(hashA, hashB) }
}

/// An auto-pair the user unlinked. The auto-pairer never proposes this pair again.
struct LinkRejection: Codable, Equatable, Hashable {
    var hashA: String
    var hashB: String
    var rejectedAt: Date

    init(pair: HashPair, rejectedAt: Date = .now) {
        self.hashA = pair.a
        self.hashB = pair.b
        self.rejectedAt = rejectedAt
    }

    var pair: HashPair { HashPair(hashA, hashB) }
}

/// On-disk layout of `links.json`. A missing key decodes as empty.
struct LinksFile: Codable, Equatable {
    var links: [TransactionLink]
    var rejections: [LinkRejection]

    init(links: [TransactionLink] = [], rejections: [LinkRejection] = []) {
        self.links = links
        self.rejections = rejections
    }

    enum CodingKeys: String, CodingKey { case links, rejections }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        links      = try c.decodeIfPresent([TransactionLink].self, forKey: .links) ?? []
        rejections = try c.decodeIfPresent([LinkRejection].self, forKey: .rejections) ?? []
    }
}
