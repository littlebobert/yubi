import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    setup
                    notes
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Yubi Keyboard")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Translate selected text to Japanese.")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("Select text in any app, switch to Yubi, then hold the spacebar when it says “hold for 日本語”.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enable the keyboard", systemImage: "keyboard")
                .font(.title2.bold())

            Button(action: openSettings) {
                Label("Open Settings", systemImage: "gear")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            StepView(number: 1, text: "Tap the button above to open Yubi's Settings page.")
            StepView(number: 2, text: "If needed, go to General > Keyboard > Keyboards > Add New Keyboard.")
            StepView(number: 3, text: "Choose Yubi Keyboard.")
            StepView(number: 4, text: "Use the globe key to switch to Yubi.")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prototype notes", systemImage: "wand.and.stars")
                .font(.title2.bold())

            Text("Translation uses Apple's on-device Foundation Models when available. Yubi does not request Full Access.")

            Text("Autocorrect is local and runs when you press space or punctuation.")
                .foregroundStyle(.secondary)
        }
        .font(.body)
    }
}

private struct StepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ContentView()
}
