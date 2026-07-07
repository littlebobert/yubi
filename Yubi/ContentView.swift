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
            .navigationTitle(AppCopy.title)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppCopy.heroTitle)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(AppCopy.heroSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppCopy.enableKeyboard, systemImage: "keyboard")
                .font(.title2.bold())

            Button(action: openSettings) {
                Label(AppCopy.openSettings, systemImage: "gear")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            StepView(number: 1, text: AppCopy.stepOpenSettings)
            StepView(number: 2, text: AppCopy.stepAddKeyboard)
            StepView(number: 3, text: AppCopy.stepChooseKeyboard)
            StepView(number: 4, text: AppCopy.stepSwitchKeyboard)
            StepView(number: 5, text: AppCopy.stepTranslate)
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
            Label(AppCopy.privacyTitle, systemImage: "lock.shield")
                .font(.title2.bold())

            Text(AppCopy.privacyBody)

            Text(AppCopy.defaultsBody)
                .foregroundStyle(.secondary)
        }
        .font(.body)
    }
}

private enum AppCopy {
    private enum InterfaceLanguage {
        case english
        case japanese
        case chineseSimplified
        case chineseTraditional
        case korean

        static var current: InterfaceLanguage {
            let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()

            if identifier.hasPrefix("ja") {
                return .japanese
            }

            if identifier.hasPrefix("ko") {
                return .korean
            }

            if identifier.hasPrefix("zh") {
                if identifier.contains("hant")
                    || identifier.contains("-tw")
                    || identifier.contains("_tw")
                    || identifier.contains("-hk")
                    || identifier.contains("_hk")
                    || identifier.contains("-mo")
                    || identifier.contains("_mo") {
                    return .chineseTraditional
                }

                return .chineseSimplified
            }

            return .english
        }
    }

    static var title: String {
        localized(
            en: "Yubi Keyboard",
            ja: "Yubiキーボード",
            zhHans: "Yubi 键盘",
            zhHant: "Yubi 鍵盤",
            ko: "Yubi 키보드"
        )
    }

    static var heroTitle: String {
        localized(
            en: "Translate selected text.",
            ja: "選択したテキストを翻訳。",
            zhHans: "翻译选中的文本。",
            zhHant: "翻譯選取的文字。",
            ko: "선택한 텍스트를 번역하세요."
        )
    }

    static var heroSubtitle: String {
        localized(
            en: "Select text in any app, switch to Yubi, choose a language and tone, then tap Translate Selection.",
            ja: "どのアプリでもテキストを選択し、Yubiに切り替えて、言語とトーンを選び、「選択範囲を翻訳」をタップします。",
            zhHans: "在任何 App 中选中文本，切换到 Yubi，选择语言和语气，然后轻点“翻译所选内容”。",
            zhHant: "在任何 App 中選取文字，切換到 Yubi，選擇語言和語氣，然後點一下「翻譯選取內容」。",
            ko: "어느 앱에서든 텍스트를 선택하고 Yubi로 전환한 다음 언어와 어조를 고르고 ‘선택 항목 번역’을 탭하세요."
        )
    }

    static var enableKeyboard: String {
        localized(
            en: "Enable the keyboard",
            ja: "キーボードを有効にする",
            zhHans: "启用键盘",
            zhHant: "啟用鍵盤",
            ko: "키보드 활성화"
        )
    }

    static var openSettings: String {
        localized(
            en: "Open Settings",
            ja: "設定を開く",
            zhHans: "打开设置",
            zhHant: "打開設定",
            ko: "설정 열기"
        )
    }

    static var stepOpenSettings: String {
        localized(
            en: "Tap the button above to open Yubi's Settings page.",
            ja: "上のボタンをタップしてYubiの設定ページを開きます。",
            zhHans: "轻点上方按钮打开 Yubi 的设置页面。",
            zhHant: "點一下上方按鈕打開 Yubi 的設定頁面。",
            ko: "위 버튼을 탭해 Yubi 설정 페이지를 여세요."
        )
    }

    static var stepAddKeyboard: String {
        localized(
            en: "If needed, go to General > Keyboard > Keyboards > Add New Keyboard.",
            ja: "必要に応じて、「一般」>「キーボード」>「キーボード」>「新しいキーボードを追加」に進みます。",
            zhHans: "如有需要，前往“通用”>“键盘”>“键盘”>“添加新键盘”。",
            zhHant: "如有需要，前往「一般」>「鍵盤」>「鍵盤」>「加入新鍵盤」。",
            ko: "필요하면 일반 > 키보드 > 키보드 > 새로운 키보드 추가로 이동하세요."
        )
    }

    static var stepChooseKeyboard: String {
        localized(
            en: "Choose Yubi Keyboard.",
            ja: "Yubiキーボードを選択します。",
            zhHans: "选择 Yubi 键盘。",
            zhHant: "選擇 Yubi 鍵盤。",
            ko: "Yubi 키보드를 선택하세요."
        )
    }

    static var stepSwitchKeyboard: String {
        localized(
            en: "Select text in any app, then use the globe key to switch to Yubi.",
            ja: "任意のアプリでテキストを選択し、地球儀キーでYubiに切り替えます。",
            zhHans: "在任何 App 中选中文本，然后使用地球键切换到 Yubi。",
            zhHant: "在任何 App 中選取文字，然後使用地球鍵切換到 Yubi。",
            ko: "어느 앱에서든 텍스트를 선택한 뒤 지구본 키로 Yubi로 전환하세요."
        )
    }

    static var stepTranslate: String {
        localized(
            en: "Choose a language and tap Translate Selection.",
            ja: "言語を選び、「選択範囲を翻訳」をタップします。",
            zhHans: "选择语言并轻点“翻译所选内容”。",
            zhHant: "選擇語言並點一下「翻譯選取內容」。",
            ko: "언어를 선택하고 ‘선택 항목 번역’을 탭하세요."
        )
    }

    static var privacyTitle: String {
        localized(
            en: "Privacy and translation",
            ja: "プライバシーと翻訳",
            zhHans: "隐私与翻译",
            zhHant: "隱私與翻譯",
            ko: "개인정보 보호 및 번역"
        )
    }

    static var privacyBody: String {
        localized(
            en: "Translation uses Apple's privacy-preserving on-device model, or in some cases Private Cloud Compute. Yubi does not request Full Access.",
            ja: "翻訳にはAppleのプライバシー保護型オンデバイスモデルを使用し、場合によってはPrivate Cloud Computeを使用します。Yubiはフルアクセスを要求しません。",
            zhHans: "翻译会使用 Apple 保护隐私的设备端模型，某些情况下会使用 Private Cloud Compute。Yubi 不会请求完全访问权限。",
            zhHant: "翻譯會使用 Apple 保護隱私的裝置端模型，某些情況下會使用 Private Cloud Compute。Yubi 不會要求完整取用權限。",
            ko: "번역에는 Apple의 개인정보 보호 온디바이스 모델을 사용하며, 경우에 따라 Private Cloud Compute를 사용합니다. Yubi는 전체 접근 권한을 요청하지 않습니다."
        )
    }

    static var defaultsBody: String {
        localized(
            en: "English UI defaults to Japanese output. Japanese, Chinese, and Korean UI default to English output. Your last choices stay selected.",
            ja: "日本語、中国語、韓国語のUIでは出力言語の初期設定は英語です。英語UIでは日本語が初期設定です。最後に選んだ設定は保持されます。",
            zhHans: "日语、中文和韩语界面默认输出为英语；英语界面默认输出为日语。你上次的选择会保持选中。",
            zhHant: "日文、中文和韓文介面預設輸出為英文；英文介面預設輸出為日文。你上次的選擇會保持選取。",
            ko: "일본어, 중국어, 한국어 UI에서는 기본 출력 언어가 영어입니다. 영어 UI에서는 일본어가 기본입니다. 마지막 선택이 유지됩니다."
        )
    }

    private static func localized(en: String, ja: String, zhHans: String, zhHant: String, ko: String) -> String {
        switch InterfaceLanguage.current {
        case .english:
            return en
        case .japanese:
            return ja
        case .chineseSimplified:
            return zhHans
        case .chineseTraditional:
            return zhHant
        case .korean:
            return ko
        }
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
