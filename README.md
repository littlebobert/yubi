# Yubi

Yubi is an iOS translation app for screenshots and selected text. It can analyze a screenshot from Shortcuts, summarize what is on screen, and translate the meaningful visible text. It also includes a lightweight keyboard extension for translating selected text in place.

Yubi supports Apple Foundation Models, OpenAI, and Claude Fable 5 as AI backends. Apple runs privately on device when available; OpenAI and Claude use your own API key.

## Build And Run

1. Open `Yubi.xcodeproj` in Xcode.
2. Set signing for both the `Yubi` app and `YubiKeyboard` extension targets.
3. Build and run the `Yubi` app on an iPhone or simulator.
4. In Yubi, choose an AI backend in Setup.
5. For screenshot translation, create a Shortcut with `Take Screenshot` followed by `Analyze Image with Yubi`.
6. For selected-text translation, enable `Yubi Keyboard` from Settings > General > Keyboard > Keyboards > Add New Keyboard.

Full Access lets the keyboard extension use your selected AI backend and save Text Edits history in Yubi.

## TestFlight

Submit builds from GitHub Actions on a **stable** Xcode (App Store Connect rejects local Xcode betas). See [ci/TESTFLIGHT.md](ci/TESTFLIGHT.md) and the **TestFlight** workflow under Actions.
