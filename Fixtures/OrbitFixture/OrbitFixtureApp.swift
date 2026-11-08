import SwiftUI

@main
struct OrbitFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            FixtureView()
        }
    }
}

private struct FixtureView: View {
    @State private var tapCount = 0
    @State private var enteredText = ""
    @State private var lastLink = "none"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("OrbitFixture")
                .font(.largeTitle.bold())
            Text("Ready")
                .accessibilityIdentifier("fixture.status")
            Button("Tap target") { tapCount += 1 }
                .accessibilityIdentifier("fixture.tap")
            Text("Taps: \(tapCount)")
                .accessibilityIdentifier("fixture.tap-count")
            TextField("Type here", text: $enteredText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fixture.input")
            Text("Input: \(enteredText)")
                .accessibilityIdentifier("fixture.input-value")
            Text("Link: \(lastLink)")
                .accessibilityIdentifier("fixture.link")
            Spacer()
        }
        .padding(30)
        .onOpenURL { lastLink = $0.absoluteString }
    }
}
