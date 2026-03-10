import SwiftUI
import BeachStatus

/// Horizontal scrolling filter bar with city picker and status pills.
struct FilterBarView: View {
    @Bindable var viewModel: BeachViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // City picker
                Menu {
                    Button("All Cities") {
                        viewModel.selectedCity = nil
                    }
                    ForEach(viewModel.cities, id: \.self) { city in
                        Button(city) {
                            viewModel.selectedCity = city
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                        Text(viewModel.selectedCity ?? "All Cities")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.ocean600))
                }

                // Status filter pills
                StatusPill(
                    label: "All",
                    count: viewModel.ramps.count,
                    isSelected: viewModel.selectedStatus == nil,
                    color: .ocean600
                ) {
                    viewModel.selectedStatus = nil
                }

                ForEach(StatusCategory.allCases, id: \.self) { status in
                    StatusPill(
                        label: status.label,
                        count: countFor(status),
                        isSelected: viewModel.selectedStatus == status,
                        color: status.color
                    ) {
                        viewModel.selectedStatus = status
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func countFor(_ status: StatusCategory) -> Int {
        switch status {
        case .open: return viewModel.openCount
        case .limited: return viewModel.limitedCount
        case .closed: return viewModel.closedCount
        }
    }
}

/// Individual filter pill with count badge.
struct StatusPill: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(isSelected ? .white.opacity(0.3) : color.opacity(0.2))
                    }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : color)
            .background {
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
    }
}
