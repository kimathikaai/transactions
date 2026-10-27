import SwiftUI

struct SectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.light)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.leading, 16)

            content()
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(.thickMaterial, in: .rect(cornerRadius: 16))
                .glassEffect(
                    .regular.tint(.clear),
                    in: .rect(cornerRadius: 16)
                )
        }
    }
}
