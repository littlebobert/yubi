# Yubi Keyboard

Yubi is an iOS keyboard prototype with local autocorrect and selected-text translation. Select text, then hold the spacebar to translate the selection to Japanese using Apple's on-device Foundation Models when available.

## Build And Run

1. Open `Yubi.xcodeproj` in Xcode.
2. Set signing for both the `Yubi` app and `YubiKeyboard` extension targets.
3. Build and run the `Yubi` app on an iPhone or simulator.
4. Tap `Open Settings`, then enable `Yubi Keyboard`. If needed, go to Settings > General > Keyboard > Keyboards > Add New Keyboard.
5. Switch to Yubi from the system globe key.

The keyboard does not request Full Access. The word-frequency autocorrect dictionary is generated during the keyboard extension build and ignored by git.
