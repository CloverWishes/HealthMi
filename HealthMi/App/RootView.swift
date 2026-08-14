import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isConfigured {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isConfigured)
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
