import SwiftUI

/// Why water: each benefit in one sentence, with where it comes from.
struct BenefitsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIconBadge().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why water?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("What finishing your bottles does for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(Benefit.all.enumerated()), id: \.element.id) { index, benefit in
                    if index > 0 { Divider().padding(.leading, 46) }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: benefit.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(benefit.fact)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(benefit.source)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Sip isn’t medical advice. If you have kidney or heart problems, or take water pills, ask your doctor how much to drink.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
    }
}
