# Yubi Keyboard

Yubi is an iOS keyboard prototype for selected-text translation. Select text, switch to Yubi, choose an output language, then tap the translate button. Translation uses Apple's Foundation Models when available.

## Build And Run

1. Open `Yubi.xcodeproj` in Xcode.
2. Set signing for both the `Yubi` app and `YubiKeyboard` extension targets.
3. Build and run the `Yubi` app on an iPhone or simulator.
4. Tap `Open Settings`, then enable `Yubi Keyboard`. If needed, go to Settings > General > Keyboard > Keyboards > Add New Keyboard.
5. Switch to Yubi from the system globe key.

The keyboard does not request Full Access. English UI defaults to Japanese output; Japanese, Chinese, and Korean UI default to English output. The last selected output language is remembered.
