import SwiftUI

/// A reserve's emoji in a colored rounded chip, tinted by the emoji's dominant
/// color (`Color.fromEmoji`, falling back to white so an empty emoji still
/// renders a uniform block). Shared by `ReserveCardView` (default 25) and the
/// Reserves-page Activity rows (smaller, to suit their caption-sized text).
struct ReserveEmojiChip: View {
    let emoji: String
    var size: CGFloat = 25

    private var tint: Color {
        Color.fromEmoji(emoji) ?? .white
    }

    var body: some View {
        Text(emoji)
            .font(size >= 24 ? .body : .caption)
            .frame(width: size, height: size)
            .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }
}
