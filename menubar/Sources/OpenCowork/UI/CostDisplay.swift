import SwiftUI
import Combine

final class CostViewModel: ObservableObject {
    @Published var tokens: Int = 0
    @Published var cost: Double = 0.0

    private var cancellables = Set<AnyCancellable>()

    var formatted: String {
        "\(tokens.formatted()) tokens · ~$\(String(format: "%.4f", cost))"
    }

    init() {
        // Placeholder for future Combine publisher integration
    }
}

struct CostDisplay: View {
    @StateObject private var model = CostViewModel()

    var body: some View {
        HStack {
            Spacer()
            Text(model.formatted)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}