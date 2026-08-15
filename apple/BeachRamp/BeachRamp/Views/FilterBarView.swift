import SwiftUI
import BeachStatus

/// Four count buttons — All / Open / Limited / Closed. This is where the old
/// summary cards' counts live. Active is a solid accent field with white
/// type; the rest are 2px-bordered. 34pt tall with a 44pt touch area.
struct FilterBarView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.ground) private var ground

    var body: some View {
        HStack(spacing: 8) {
            filterButton("All", count: viewModel.cityRamps.count, matches: nil)
            filterButton("Open", count: viewModel.openCount, matches: .open)
            filterButton("Limited", count: viewModel.limitedCount, matches: .limited)
            filterButton("Closed", count: viewModel.closedCount, matches: .closed)
            Spacer(minLength: 0)
        }
    }

    private func filterButton(_ label: String, count: Int, matches status: StatusCategory?) -> some View {
        let t = ground.tokens
        let isActive = viewModel.selectedStatus == status
        let isEmpty = count == 0 && status != nil
        return Button {
            viewModel.selectedStatus = status
        } label: {
            Text("\(label) \(count)")
                .font(.archivo(14, weight: .extraBold))
                .monospacedDigit()
                .foregroundStyle(isActive ? .white : t.ink.opacity(isEmpty ? 0.4 : 1))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isActive ? t.accent : .clear)
                .overlay {
                    if !isActive {
                        Rectangle().strokeBorder(
                            isEmpty ? t.rule2 : t.rule, lineWidth: 2)
                    }
                }
                .padding(.vertical, 5)   // 34pt control, 44pt touch area
                .contentShape(Rectangle())
        }
        .buttonStyle(PressTintButtonStyle())
        .disabled(isEmpty && !isActive)
        .accessibilityLabel("\(label), \(count) ramps")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Pressed tint per the handoff: accent at 8% opacity.
struct PressTintButtonStyle: ButtonStyle {
    @Environment(\.ground) private var ground

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ground.tokens.accent.opacity(0.08) : .clear)
    }
}
