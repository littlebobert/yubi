import AudioToolbox
import os
import UIKit

private let keyboardTranslationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "YubiKeyboard",
    category: "Translation"
)

final class KeyboardViewController: UIInputViewController {
    private enum KeyboardMode {
        case letters
        case symbols
        case moreSymbols
        case emoji
    }

    private enum KeyAction {
        case character(String)
        case punctuation(String)
        case backspace
        case shift
        case space
        case returnKey
        case switchKeyboard
        case toggleMode
        case toggleMoreSymbols
        case toggleEmoji
    }

    private enum KeyStyle {
        case letter
        case control
        case space
        case returnKey
    }

    private enum OutputLanguage: String, CaseIterable {
        case japanese
        case korean
        case chineseSimplified
        case english
        case spanish
        case french
        case german

        private static let defaultsKey = "YubiOutputLanguage"

        var displayName: String {
            switch self {
            case .japanese:
                return KeyboardCopy.japanese
            case .korean:
                return KeyboardCopy.korean
            case .chineseSimplified:
                return KeyboardCopy.chinese
            case .english:
                return KeyboardCopy.english
            case .spanish:
                return KeyboardCopy.spanish
            case .french:
                return KeyboardCopy.french
            case .german:
                return KeyboardCopy.german
            }
        }

        var promptName: String {
            switch self {
            case .japanese:
                return "Japanese"
            case .korean:
                return "Korean"
            case .chineseSimplified:
                return "Simplified Chinese"
            case .english:
                return "English"
            case .spanish:
                return "Spanish"
            case .french:
                return "French"
            case .german:
                return "German"
            }
        }

        static var persisted: OutputLanguage {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let language = OutputLanguage(rawValue: rawValue)
            else {
                return defaultLanguage
            }

            return language
        }

        func persist() {
            UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        }

        private static var defaultLanguage: OutputLanguage {
            let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()

            if identifier.hasPrefix("ja") || identifier.hasPrefix("zh") || identifier.hasPrefix("ko") {
                return .english
            }

            return .japanese
        }
    }

    private enum JapaneseTone: String, CaseIterable {
        case polite
        case casual

        private static let defaultsKey = "YubiJapaneseTone"

        var displayName: String {
            switch self {
            case .polite:
                return KeyboardCopy.polite
            case .casual:
                return KeyboardCopy.casual
            }
        }

        var promptInstruction: String {
            switch self {
            case .polite:
                return "polite Japanese using natural desu/masu form"
            case .casual:
                return "casual Japanese using natural plain form"
            }
        }

        static var persisted: JapaneseTone {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let tone = JapaneseTone(rawValue: rawValue)
            else {
                return .polite
            }

            return tone
        }

        func persist() {
            UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    private enum KeyboardCopy {
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

        static var language: String {
            localized(en: "Language", ja: "言語", zhHans: "语言", zhHant: "語言", ko: "언어")
        }

        static var tone: String {
            localized(en: "Tone", ja: "トーン", zhHans: "语气", zhHant: "語氣", ko: "어조")
        }

        static var translateSelection: String {
            localized(en: "Translate Selection", ja: "選択範囲を翻訳", zhHans: "翻译所选内容", zhHant: "翻譯選取內容", ko: "선택 항목 번역")
        }

        static var selectTextToTranslate: String {
            localized(en: "Select text to translate", ja: "翻訳するテキストを選択", zhHans: "选择要翻译的文本", zhHant: "選取要翻譯的文字", ko: "번역할 텍스트 선택")
        }

        static var translating: String {
            localized(en: "Translating", ja: "翻訳中", zhHans: "正在翻译", zhHant: "正在翻譯", ko: "번역 중")
        }

        static func privacyHint(for backend: AIBackend) -> String {
            switch backend {
            case .apple:
                return localized(
                    en: "Translation uses Apple's privacy-preserving on-device model when available.",
                    ja: "翻訳には、利用可能な場合Appleのプライバシー保護型オンデバイスモデルを使用します。",
                    zhHans: "翻译会在可用时使用 Apple 保护隐私的设备端模型。",
                    zhHant: "翻譯會在可用時使用 Apple 保護隱私的裝置端模型。",
                    ko: "번역에는 가능한 경우 Apple의 개인정보 보호 온디바이스 모델을 사용합니다."
                )
            case .openAI:
                return localized(
                    en: "Translation sends selected text to OpenAI using your API key.",
                    ja: "翻訳では、選択したテキストをあなたのAPIキーでOpenAIに送信します。",
                    zhHans: "翻译会使用你的 API 密钥将所选文本发送到 OpenAI。",
                    zhHant: "翻譯會使用你的 API 金鑰將選取文字傳送到 OpenAI。",
                    ko: "번역은 선택한 텍스트를 사용자의 API 키로 OpenAI에 보냅니다."
                )
            case .claudeFable:
                return localized(
                    en: "Translation sends selected text to Claude Fable 5 using your API key.",
                    ja: "翻訳では、選択したテキストをあなたのAPIキーでClaude Fable 5に送信します。",
                    zhHans: "翻译会使用你的 API 密钥将所选文本发送到 Claude Fable 5。",
                    zhHant: "翻譯會使用你的 API 金鑰將選取文字傳送到 Claude Fable 5。",
                    ko: "번역은 선택한 텍스트를 사용자의 API 키로 Claude Fable 5에 보냅니다."
                )
            }
        }

        static var japanese: String {
            localized(en: "Japanese", ja: "日本語", zhHans: "日语", zhHant: "日文", ko: "일본어")
        }

        static var korean: String {
            localized(en: "Korean", ja: "韓国語", zhHans: "韩语", zhHant: "韓文", ko: "한국어")
        }

        static var chinese: String {
            localized(en: "Chinese", ja: "中国語", zhHans: "中文", zhHant: "中文", ko: "중국어")
        }

        static var english: String {
            localized(en: "English", ja: "英語", zhHans: "英语", zhHant: "英文", ko: "영어")
        }

        static var spanish: String {
            localized(en: "Spanish", ja: "スペイン語", zhHans: "西班牙语", zhHant: "西班牙文", ko: "스페인어")
        }

        static var french: String {
            localized(en: "French", ja: "フランス語", zhHans: "法语", zhHant: "法文", ko: "프랑스어")
        }

        static var german: String {
            localized(en: "German", ja: "ドイツ語", zhHans: "德语", zhHant: "德文", ko: "독일어")
        }

        static var polite: String {
            localized(en: "Polite", ja: "丁寧", zhHans: "礼貌", zhHant: "禮貌", ko: "공손체")
        }

        static var casual: String {
            localized(en: "Casual", ja: "カジュアル", zhHans: "随意", zhHant: "隨意", ko: "반말")
        }

        static func unavailable(_ language: String) -> String {
            switch InterfaceLanguage.current {
            case .english:
                return "\(language) unavailable"
            case .japanese:
                return "\(language)は利用できません"
            case .chineseSimplified:
                return "\(language)不可用"
            case .chineseTraditional:
                return "\(language)無法使用"
            case .korean:
                return "\(language) 사용할 수 없음"
            }
        }

        static var allowFullAccess: String {
            localized(en: "Allow Full Access", ja: "フルアクセスを許可", zhHans: "允许完全访问", zhHant: "允許完整取用", ko: "전체 접근 허용")
        }

        static var addAPIKey: String {
            localized(en: "Add API key in Yubi", ja: "YubiでAPIキーを追加", zhHans: "在 Yubi 中添加 API 密钥", zhHant: "在 Yubi 中加入 API 金鑰", ko: "Yubi에서 API 키 추가")
        }

        static var translationFailed: String {
            localized(en: "Translation failed", ja: "翻訳に失敗", zhHans: "翻译失败", zhHant: "翻譯失敗", ko: "번역 실패")
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

    fileprivate enum Theme {
        static let panelBackground = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1.0)
        static let keyBackground = UIColor.white
        static let controlBackground = UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1.0)
        static let activeControlBackground = UIColor(red: 0.58, green: 0.61, blue: 0.66, alpha: 1.0)
        static let border = UIColor(red: 0.68, green: 0.69, blue: 0.74, alpha: 1.0)
        static let text = UIColor.black
        static let mutedText = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        static let accent = UIColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1.0)
        static let keyShadow = UIColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1.0)

        static let letterFont = UIFont.systemFont(ofSize: 23, weight: .regular)
        static let controlFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let edgeControlFont = UIFont.systemFont(ofSize: 24, weight: .medium)
        static let modeFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let spaceFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let suggestionFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let hintFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        static let systemUtilityKeyWidth: CGFloat = 44
        static let systemReturnKeyWidth: CGFloat = 96
        static let homeRowInset: CGFloat = 24
        static let zRowInset: CGFloat = 64
        static let standardKeyboardHeight: CGFloat = 200
    }

    private let autocorrector = Autocorrector()
    private let keyFeedback = UIImpactFeedbackGenerator(style: .light)
    private let rootStack = UIStackView()

    private var mode: KeyboardMode = .letters
    private var isShifted = false
    private var isCapsLocked = false
    private var lastShiftTap = Date.distantPast
    private var letterButtons: [(button: UIButton, lowercasedLetter: String)] = []
    private var topRowHitTargets: [(button: UIButton, handler: (UIButton, CGPoint) -> Void)] = []
    private var suggestionButton: UIButton?
    private var shiftButton: UIButton?
    private var modeButton: UIButton?
    private var toneButton: UIButton?
    private var privacyHintLabel: UILabel?
    private var deleteActionButton: UIButton?
    private var spaceButton: UIButton?
    private var spaceSpinner: UIActivityIndicatorView?
    private var spaceTranslationStack: UIStackView?
    private var deleteTimer: Timer?
    private var deleteInitialTimer: Timer?
    private var deleteRepeatCount = 0
    private var heightConstraint: NSLayoutConstraint?
    private var currentWordTouches: [TouchObservation] = []
    private var isTranslatingSelection = false
    private var translationTask: Task<Void, Never>?
    private var shouldReturnToLettersAfterSpace = false
    private var pendingAutocorrection: AppliedAutocorrection?
    private var suggestionBarState: SuggestionBarState?
    private var autocorrectionHistory: [AppliedAutocorrection] = []
    private var outputLanguage = OutputLanguage.persisted
    private var japaneseTone = JapaneseTone.persisted

    override func viewDidLoad() {
        super.viewDidLoad()

        configureRootView()
        renderKeyboard()
        keyFeedback.prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isTranslatingSelection = false
        refreshTranslationControls()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDeleteRepeat()
        translationTask?.cancel()
        translationTask = nil
        isTranslatingSelection = false
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshTranslationControls()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        refreshTranslationControls()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        heightConstraint?.constant = Theme.standardKeyboardHeight
    }

    private func configureRootView() {
        view.backgroundColor = Theme.panelBackground

        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.alignment = .fill
        rootStack.distribution = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.isLayoutMarginsRelativeArrangement = true
        rootStack.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: Theme.standardKeyboardHeight)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
    }

    private func loadSupplementaryLexicon() {
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.autocorrector.addLexiconEntries(lexicon.entries)
        }
    }

    private func renderKeyboard() {
        rootStack.arrangedSubviews.forEach { view in
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        letterButtons.removeAll()
        topRowHitTargets.removeAll()
        suggestionButton = nil
        shiftButton = nil
        modeButton = nil
        toneButton = nil
        deleteActionButton = nil
        spaceButton = nil
        spaceSpinner = nil
        spaceTranslationStack = nil

        rootStack.addArrangedSubview(makeTranslatorPanel())
        refreshTranslationControls()
    }

    private func makeTranslatorPanel() -> UIView {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        let controls = UIStackView(arrangedSubviews: [
            makePickerControlsRow(),
            makeTranslationActionRow(),
            makePrivacyHintLabel()
        ])
        controls.axis = .vertical
        controls.alignment = .fill
        controls.distribution = .fill
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: panel.layoutMarginsGuide.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: panel.layoutMarginsGuide.trailingAnchor),
            controls.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
        ])

        return panel
    }

    private func makePickerControlsRow() -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 66).isActive = true

        var columns = [makeLanguagePickerColumn()]
        if outputLanguage == .japanese {
            columns.append(makeJapaneseToneColumn())
        }

        let stack = UIStackView(arrangedSubviews: columns)
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            stack.topAnchor.constraint(equalTo: row.topAnchor),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    private func makeLanguagePickerColumn() -> UIView {
        let languageButton = ExpandedHitButton(type: .system)
        configureButton(languageButton, title: outputLanguage.displayName, style: .space)
        languageButton.showsMenuAsPrimaryAction = true
        languageButton.menu = outputLanguageMenu()
        modeButton = languageButton

        return makePickerColumn(labelText: KeyboardCopy.language, button: languageButton)
    }

    private func makeJapaneseToneColumn() -> UIView {
        let button = ExpandedHitButton(type: .system)
        configureButton(button, title: japaneseTone.displayName, style: .space)
        button.showsMenuAsPrimaryAction = true
        button.menu = japaneseToneMenu()
        toneButton = button

        return makePickerColumn(labelText: KeyboardCopy.tone, button: button)
    }

    private func makePickerColumn(labelText: String, button: UIButton) -> UIView {
        let label = UILabel()
        label.text = labelText
        label.font = Theme.suggestionFont
        label.textColor = Theme.mutedText
        label.textAlignment = .center

        let column = UIStackView(arrangedSubviews: [label, button])
        column.axis = .vertical
        column.alignment = .fill
        column.distribution = .fill
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        column.widthAnchor.constraint(equalToConstant: 148).isActive = true
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true

        return column
    }

    private func makeTranslationActionRow() -> UIView {
        let row = makeHorizontalRow(height: 46)
        row.spacing = 8

        let button = ExpandedHitButton(type: .system)
        configureButton(button, title: "", style: .space)
        button.addAction(UIAction { [weak self] _ in
            self?.handleTranslateSelectionTap()
        }, for: .touchUpInside)
        configureSpaceSpinner(in: button)
        spaceButton = button

        let deleteButton = DeleteKeyButton(type: .system)
        configureButton(deleteButton, title: "⌫", style: .space)
        deleteButton.titleLabel?.font = Theme.edgeControlFont
        deleteButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        deleteButton.onPressBegan = { [weak self] in
            guard let self, !self.isTranslatingSelection else { return }
            self.beginDeletePress()
        }
        deleteButton.onPressEnded = { [weak self] in
            self?.stopDeleteRepeat()
        }
        deleteActionButton = deleteButton

        row.addArrangedSubview(button)
        row.addArrangedSubview(deleteButton)
        return row
    }

    private func makePrivacyHintLabel() -> UIView {
        let label = UILabel()
        label.text = KeyboardCopy.privacyHint(for: AIBackendSettings.selectedBackend)
        label.font = Theme.hintFont
        label.textColor = Theme.accent
        label.textAlignment = .center
        label.numberOfLines = 2
        privacyHintLabel = label
        return label
    }

    private func outputLanguageMenu() -> UIMenu {
        UIMenu(children: OutputLanguage.allCases.map { language in
            UIAction(
                title: language.displayName,
                state: language == outputLanguage ? .on : .off
            ) { [weak self] _ in
                self?.setOutputLanguage(language)
            }
        })
    }

    private func japaneseToneMenu() -> UIMenu {
        UIMenu(children: JapaneseTone.allCases.map { tone in
            UIAction(
                title: tone.displayName,
                state: tone == japaneseTone ? .on : .off
            ) { [weak self] _ in
                self?.setJapaneseTone(tone)
            }
        })
    }

    private func setOutputLanguage(_ language: OutputLanguage) {
        outputLanguage = language
        outputLanguage.persist()
        renderKeyboard()
    }

    private func setJapaneseTone(_ tone: JapaneseTone) {
        japaneseTone = tone
        japaneseTone.persist()
        toneButton?.setTitle(tone.displayName, for: .normal)
        toneButton?.menu = japaneseToneMenu()
        refreshTranslationControls()
    }

    private func makeTopCaptureBand() -> UIView {
        let band = TopRowHitProxyView()
        band.translatesAutoresizingMaskIntoConstraints = false
        band.backgroundColor = .clear
        band.heightAnchor.constraint(equalToConstant: 32).isActive = true
        band.onTap = { [weak self, weak band] localPoint in
            guard let self, let band else { return }
            self.handleTopCaptureTap(localPoint, in: band)
        }
        configureSuggestionButton(in: band)
        return band
    }

    private func configureSuggestionButton(in band: UIView) {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = Theme.keyBackground.withAlphaComponent(0.92)
        button.layer.cornerRadius = 8
        button.layer.borderColor = Theme.border.cgColor
        button.layer.borderWidth = 1
        button.titleLabel?.font = Theme.suggestionFont
        button.setTitleColor(Theme.mutedText, for: .normal)
        button.contentHorizontalAlignment = .center
        button.isHidden = true
        button.addAction(UIAction { [weak self] _ in
            self?.handleSuggestionTap()
        }, for: .touchUpInside)

        band.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: band.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: band.centerYAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        suggestionButton = button
    }

    private func makeLetterRow(_ letters: [String], sideInset: CGFloat, topHitOutset: CGFloat = 4, tracksTopRow: Bool = false) -> UIView {
        let row = makeHorizontalRow(height: 46)

        if sideInset > 0, let firstLetter = letters.first {
            row.addArrangedSubview(makeInvisibleLetterHitTarget(firstLetter, width: sideInset))
        }

        let lettersStack = makeHorizontalRow(height: 46)
        lettersStack.spacing = 6
        lettersStack.distribution = .fillEqually

        letters.forEach { letter in
            lettersStack.addArrangedSubview(makeLetterButton(letter, topHitOutset: topHitOutset, tracksTopRow: tracksTopRow))
        }

        row.addArrangedSubview(lettersStack)

        if sideInset > 0, let lastLetter = letters.last {
            row.addArrangedSubview(makeInvisibleLetterHitTarget(lastLetter, width: sideInset))
        }

        return row
    }

    private func makeZRow() -> UIView {
        let row = makeHorizontalRow(height: 46)

        let shift = makeButton(title: "⇧", style: .control, action: .shift)
        shift.titleLabel?.font = Theme.edgeControlFont
        shift.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true
        shiftButton = shift

        let lettersStack = makeHorizontalRow(height: 46)
        lettersStack.spacing = 6
        lettersStack.distribution = .fillEqually

        ["z", "x", "c", "v", "b", "n", "m"].forEach { letter in
            lettersStack.addArrangedSubview(makeLetterButton(letter))
        }

        let delete = makeDeleteButton()
        delete.titleLabel?.font = Theme.edgeControlFont
        delete.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        row.addArrangedSubview(shift)
        row.addArrangedSubview(lettersStack)
        row.addArrangedSubview(delete)

        return row
    }

    private func makeControlStrip() -> UIView {
        let row = makeHorizontalRow(height: 46)

        let shift = makeButton(title: "⇧", style: .control, action: .shift)
        shift.titleLabel?.font = Theme.edgeControlFont
        shift.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true
        shiftButton = shift

        let delete = makeDeleteButton()
        delete.titleLabel?.font = Theme.edgeControlFont
        delete.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        row.addArrangedSubview(shift)
        row.addArrangedSubview(makeDeadSpace())
        row.addArrangedSubview(delete)

        return row
    }

    private func makeBottomRow(modeTitle: String) -> UIView {
        let row = makeHorizontalRow(height: 46)
        row.spacing = 8

        let modeKey = makeButton(title: modeTitle, style: .control, action: .toggleMode)
        modeKey.titleLabel?.font = Theme.modeFont
        modeKey.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true
        modeButton = modeKey

        let emoji = makeButton(title: "😊", style: .control, action: .toggleEmoji)
        emoji.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        let space = makeButton(title: "space", style: .space, action: .space)
        spaceButton = space
        configureSpaceSpinner(in: space)
        let translateGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
        translateGesture.cancelsTouchesInView = true
        space.addGestureRecognizer(translateGesture)

        let returnKey = makeButton(title: "↵", style: .returnKey, action: .returnKey)
        returnKey.widthAnchor.constraint(equalToConstant: Theme.systemReturnKeyWidth).isActive = true

        row.addArrangedSubview(modeKey)
        row.addArrangedSubview(emoji)
        row.addArrangedSubview(space)
        row.addArrangedSubview(returnKey)

        return row
    }

    private func makeSymbolRow(_ symbols: [String], sideInset: CGFloat, tracksTopRow: Bool = false) -> UIView {
        let row = makeHorizontalRow(height: 46)

        if sideInset > 0 {
            row.addArrangedSubview(makeDeadSpace(width: sideInset))
        }

        let symbolsStack = makeHorizontalRow(height: 46)
        symbolsStack.spacing = 6
        symbolsStack.distribution = .fillEqually

        symbols.forEach { symbol in
            let button = makeButton(title: symbol, style: .letter, action: .punctuation(symbol))
            if tracksTopRow {
                topRowHitTargets.append((button, { [weak self] _, _ in
                    self?.handle(.punctuation(symbol))
                }))
            }
            symbolsStack.addArrangedSubview(button)
        }

        row.addArrangedSubview(symbolsStack)

        if sideInset > 0 {
            row.addArrangedSubview(makeDeadSpace(width: sideInset))
        }

        return row
    }

    private func makeSymbolZRow(_ symbols: [String], modeTitle: String = "#+=", modeAction: KeyAction = .toggleMoreSymbols) -> UIView {
        let row = makeHorizontalRow(height: 46)

        let symbolsModeKey = makeButton(title: modeTitle, style: .control, action: modeAction)
        symbolsModeKey.titleLabel?.font = Theme.modeFont
        symbolsModeKey.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        let symbolsStack = makeHorizontalRow(height: 46)
        symbolsStack.spacing = 6
        symbolsStack.distribution = .fillEqually

        symbols.forEach { symbol in
            symbolsStack.addArrangedSubview(makeButton(title: symbol, style: .letter, action: .punctuation(symbol)))
        }

        let delete = makeDeleteButton()
        delete.titleLabel?.font = Theme.edgeControlFont
        delete.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        row.addArrangedSubview(symbolsModeKey)
        row.addArrangedSubview(symbolsStack)
        row.addArrangedSubview(delete)

        return row
    }

    private func makeSymbolControlStrip() -> UIView {
        let row = makeHorizontalRow(height: 46)

        let moreSymbols = makeButton(title: "#+=", style: .control, action: .punctuation(""))
        moreSymbols.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true
        moreSymbols.alpha = 0.45
        moreSymbols.isEnabled = false

        let delete = makeDeleteButton()
        delete.titleLabel?.font = Theme.edgeControlFont
        delete.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        row.addArrangedSubview(moreSymbols)
        row.addArrangedSubview(makeDeadSpace())
        row.addArrangedSubview(delete)

        return row
    }

    private func makeEmojiRow(_ emoji: [String], tracksTopRow: Bool = false) -> UIView {
        let row = makeHorizontalRow(height: 46)
        row.addArrangedSubview(makeDeadSpace(width: 18))

        let emojiStack = makeHorizontalRow(height: 46)
        emojiStack.spacing = 6
        emojiStack.distribution = .fillEqually

        emoji.forEach { symbol in
            let button = makeButton(title: symbol, style: .letter, action: .character(symbol))
            if tracksTopRow {
                topRowHitTargets.append((button, { [weak self] _, _ in
                    self?.handle(.character(symbol))
                }))
            }
            emojiStack.addArrangedSubview(button)
        }

        row.addArrangedSubview(emojiStack)
        row.addArrangedSubview(makeDeadSpace(width: 18))

        return row
    }

    private func makeEmojiDeleteRow(_ emoji: [String]) -> UIView {
        let row = makeHorizontalRow(height: 46)
        row.addArrangedSubview(makeDeadSpace(width: Theme.systemUtilityKeyWidth))

        let emojiStack = makeHorizontalRow(height: 46)
        emojiStack.spacing = 6
        emojiStack.distribution = .fillEqually

        emoji.forEach { symbol in
            emojiStack.addArrangedSubview(makeButton(title: symbol, style: .letter, action: .character(symbol)))
        }

        let delete = makeDeleteButton()
        delete.titleLabel?.font = Theme.edgeControlFont
        delete.widthAnchor.constraint(equalToConstant: Theme.systemUtilityKeyWidth).isActive = true

        row.addArrangedSubview(emojiStack)
        row.addArrangedSubview(delete)

        return row
    }

    private func makeHorizontalRow(height: CGFloat) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }

    private func makeDeadSpace(width: CGFloat? = nil) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear

        if let width {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }

        return view
    }

    private func configureSpaceSpinner(in space: UIButton) {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = KeyboardCopy.translating
        label.font = Theme.spaceFont
        label.textColor = Theme.mutedText

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = Theme.mutedText
        spinner.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.isHidden = true
        stack.isUserInteractionEnabled = false

        space.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: space.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: space.centerYAnchor)
        ])

        spaceSpinner = spinner
        spaceTranslationStack = stack
    }

    private func handleTopCaptureTap(_ localPoint: CGPoint, in band: UIView) {
        guard let target = nearestTopRowHitTarget(to: band.convert(localPoint, to: view)) else {
            return
        }

        let keyboardPoint = band.convert(localPoint, to: view)
        let targetPoint = view.convert(keyboardPoint, to: target.button)
        target.handler(target.button, targetPoint)
    }

    private func nearestTopRowHitTarget(to keyboardPoint: CGPoint) -> (button: UIButton, handler: (UIButton, CGPoint) -> Void)? {
        topRowHitTargets.min { first, second in
            let firstCenter = first.button.convert(CGPoint(x: first.button.bounds.midX, y: first.button.bounds.midY), to: view)
            let secondCenter = second.button.convert(CGPoint(x: second.button.bounds.midX, y: second.button.bounds.midY), to: view)
            return abs(firstCenter.x - keyboardPoint.x) < abs(secondCenter.x - keyboardPoint.x)
        }
    }

    private func makeLetterButton(_ lowercasedLetter: String, topHitOutset: CGFloat = 4, tracksTopRow: Bool = false) -> UIButton {
        let button = LetterKeyButton(type: .system)
        button.hitTestOutsets.top = -topHitOutset
        configureButton(button, title: lowercasedLetter.uppercased(), style: .letter)
        let tapHandler: (LetterKeyButton, CGPoint) -> Void = { [weak self] button, localPoint in
            guard let self else { return }
            self.performKeyFeedback()
            let keyboardPoint = button.convert(localPoint, to: self.view)
            let touchObservation = self.touchObservation(for: keyboardPoint, typedLetter: lowercasedLetter)
            self.insertLetter(lowercasedLetter, touchObservation: touchObservation)
        }
        button.onTap = tapHandler
        if tracksTopRow {
            topRowHitTargets.append((button, { button, localPoint in
                guard let letterButton = button as? LetterKeyButton else { return }
                tapHandler(letterButton, localPoint)
            }))
        }
        letterButtons.append((button, lowercasedLetter))
        return button
    }

    private func makeInvisibleLetterHitTarget(_ lowercasedLetter: String, width: CGFloat) -> UIButton {
        let button = LetterKeyButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.onTap = { [weak self] button, localPoint in
            guard let self else { return }
            self.performKeyFeedback()
            let keyboardPoint = button.convert(localPoint, to: self.view)
            let touchObservation = self.touchObservation(for: keyboardPoint, typedLetter: lowercasedLetter)
            self.insertLetter(lowercasedLetter, touchObservation: touchObservation)
        }
        return button
    }

    private func makeButton(title: String, subtitle: String? = nil, style: KeyStyle, action: KeyAction) -> UIButton {
        let button = ExpandedHitButton(type: .system)
        configureButton(button, title: title, subtitle: subtitle, style: style)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.handle(action)
        }, for: .touchUpInside)

        return button
    }

    private func makeDeleteButton() -> UIButton {
        let button = DeleteKeyButton(type: .system)
        configureButton(button, title: "⌫", style: .control)
        button.onPressBegan = { [weak self] in
            self?.beginDeletePress()
        }
        button.onPressEnded = { [weak self] in
            self?.stopDeleteRepeat()
        }
        return button
    }

    private func performKeyFeedback() {
        keyFeedback.impactOccurred(intensity: 0.55)
        AudioServicesPlaySystemSound(1519)
        keyFeedback.prepare()
    }

    @objc private func handleSpaceLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, !isTranslatingSelection else {
            return
        }

        guard let selectedText = selectedTextForTranslation else {
            return
        }

        isTranslatingSelection = true
        currentWordTouches.removeAll()
        performKeyFeedback()
        refreshSpaceKey()

        translationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let translation = try await self.translate(selectedText, to: self.outputLanguage, japaneseTone: self.japaneseTone)
                try Task.checkCancellation()
                self.textDocumentProxy.insertText(translation)
                self.saveTextEditHistory(
                    sourceText: selectedText,
                    translatedText: translation,
                    targetLanguage: self.outputLanguage,
                    japaneseTone: self.japaneseTone
                )
            } catch is CancellationError {
                return
            } catch {
                keyboardTranslationLogger.error("Long-press translation failed: \(String(describing: error), privacy: .public)")
                self.spaceButton?.setTitle(self.translationErrorTitle(error, targetLanguage: self.outputLanguage), for: .normal)
            }

            self.translationTask = nil
            self.isTranslatingSelection = false
            self.refreshTranslationControls(afterDelay: 0.8)
        }
    }

    private func handleTranslateSelectionTap() {
        guard !isTranslatingSelection else {
            return
        }

        guard let selectedText = selectedTextForTranslation else {
            return
        }

        let targetLanguage = outputLanguage
        let targetTone = japaneseTone
        isTranslatingSelection = true
        currentWordTouches.removeAll()
        performKeyFeedback()
        refreshTranslationControls()

        translationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let translation = try await self.translate(selectedText, to: targetLanguage, japaneseTone: targetTone)
                try Task.checkCancellation()
                self.textDocumentProxy.insertText(translation)
                self.saveTextEditHistory(
                    sourceText: selectedText,
                    translatedText: translation,
                    targetLanguage: targetLanguage,
                    japaneseTone: targetTone
                )
            } catch is CancellationError {
                return
            } catch {
                keyboardTranslationLogger.error("Selection translation failed: \(String(describing: error), privacy: .public)")
                self.spaceButton?.setTitle(self.translationErrorTitle(error, targetLanguage: targetLanguage), for: .normal)
            }

            self.translationTask = nil
            self.isTranslatingSelection = false
            self.refreshTranslationControls(afterDelay: 0.8)
        }
    }

    private func saveTextEditHistory(
        sourceText: String,
        translatedText: String,
        targetLanguage: OutputLanguage,
        japaneseTone: JapaneseTone
    ) {
        TextEditHistoryStore.save(TextEditHistoryItem(
            date: Date(),
            sourceText: sourceText,
            translatedText: translatedText,
            targetLanguage: targetLanguage.displayName,
            tone: targetLanguage == .japanese ? japaneseTone.displayName : nil
        ))
    }

    private var selectedTextForTranslation: String? {
        guard let selectedText = textDocumentProxy.selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return selectedText
    }

    private func refreshSpaceKey(afterDelay delay: TimeInterval = 0) {
        refreshTranslationControls(afterDelay: delay)
    }

    private func refreshTranslationControls(afterDelay delay: TimeInterval = 0) {
        let update = { [weak self] in
            guard let self else { return }

            let selectedText = self.selectedTextForTranslation
            let availabilityError = self.backendAvailabilityError

            self.privacyHintLabel?.text = KeyboardCopy.privacyHint(for: AIBackendSettings.selectedBackend)

            self.deleteActionButton?.isEnabled = !self.isTranslatingSelection
            self.deleteActionButton?.alpha = self.isTranslatingSelection ? 0.62 : 1

            if self.isTranslatingSelection {
                self.spaceButton?.setTitle("", for: .normal)
                self.spaceButton?.isEnabled = false
                self.spaceButton?.alpha = 1
                self.spaceTranslationStack?.isHidden = false
                self.spaceSpinner?.startAnimating()
            } else if let availabilityError {
                self.spaceTranslationStack?.isHidden = true
                self.spaceButton?.setTitle(
                    self.translationErrorTitle(availabilityError, targetLanguage: self.outputLanguage),
                    for: .normal
                )
                self.spaceButton?.isEnabled = false
                self.spaceButton?.alpha = 1
                self.spaceSpinner?.stopAnimating()
            } else if selectedText != nil {
                self.spaceTranslationStack?.isHidden = true
                self.spaceButton?.setTitle(KeyboardCopy.translateSelection, for: .normal)
                self.spaceButton?.isEnabled = true
                self.spaceButton?.alpha = 1
                self.spaceSpinner?.stopAnimating()
            } else {
                self.spaceTranslationStack?.isHidden = true
                self.spaceButton?.setTitle(KeyboardCopy.selectTextToTranslate, for: .normal)
                self.spaceButton?.isEnabled = false
                self.spaceButton?.alpha = 0.62
                self.spaceSpinner?.stopAnimating()
            }
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: update)
        } else {
            update()
        }
    }

    private var backendAvailabilityError: Error? {
        do {
            try validateBackendAvailability()
            return nil
        } catch {
            return error
        }
    }

    private func translate(_ text: String, to targetLanguage: OutputLanguage, japaneseTone: JapaneseTone) async throws -> String {
        try validateBackendAvailability()

        return try await AIBackendClient.translate(
            text,
            targetLanguage: targetLanguage.promptName,
            toneInstruction: targetLanguage == .japanese ? japaneseTone.promptInstruction : nil
        )
    }

    private func validateBackendAvailability() throws {
        switch AIBackendSettings.selectedBackend {
        case .apple:
            return
        case .openAI:
            guard hasFullAccess else {
                throw KeyboardTranslationError.fullAccessRequired
            }

            guard !AIBackendSettings.openAIAPIKey.isEmpty else {
                throw KeyboardTranslationError.missingAPIKey
            }
        case .claudeFable:
            guard hasFullAccess else {
                throw KeyboardTranslationError.fullAccessRequired
            }

            guard !AIBackendSettings.claudeAPIKey.isEmpty else {
                throw KeyboardTranslationError.missingAPIKey
            }
        }
    }

    private func translationErrorTitle(_ error: Error, targetLanguage: OutputLanguage) -> String {
        if let keyboardError = error as? KeyboardTranslationError {
            switch keyboardError {
            case .fullAccessRequired:
                return KeyboardCopy.allowFullAccess
            case .missingAPIKey:
                return KeyboardCopy.addAPIKey
            }
        }

        if let aiError = error as? AIBackendError {
            switch aiError {
            case .missingAPIKey:
                return KeyboardCopy.addAPIKey
            default:
                return KeyboardCopy.translationFailed
            }
        }

        return KeyboardCopy.unavailable(targetLanguage.displayName)
    }

    private func configureButton(_ button: UIButton, title: String, subtitle: String? = nil, style: KeyStyle) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.clipsToBounds = false
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.layer.borderColor = Theme.border.cgColor
        button.layer.borderWidth = 0
        button.layer.shadowColor = Theme.keyShadow.cgColor
        button.layer.shadowOpacity = 0.28
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1.2)
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.numberOfLines = subtitle == nil ? 1 : 2
        button.tintColor = Theme.text
        button.contentHorizontalAlignment = .center

        if let subtitle {
            let titleText = NSMutableAttributedString(
                string: title,
                attributes: [
                    .font: Theme.spaceFont,
                    .foregroundColor: Theme.mutedText
                ]
            )
            titleText.append(NSAttributedString(
                string: "\n\(subtitle)",
                attributes: [
                    .font: Theme.hintFont,
                    .foregroundColor: Theme.accent
                ]
            ))
            button.setAttributedTitle(titleText, for: .normal)
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = font(for: style)
            button.setTitleColor(titleColor(for: style), for: .normal)
        }

        button.backgroundColor = backgroundColor(for: style)
    }

    private func font(for style: KeyStyle) -> UIFont {
        switch style {
        case .letter:
            return Theme.letterFont
        case .control, .returnKey:
            return Theme.controlFont
        case .space:
            return Theme.spaceFont
        }
    }

    private func backgroundColor(for style: KeyStyle) -> UIColor {
        switch style {
        case .letter, .space:
            return Theme.keyBackground
        case .control, .returnKey:
            return Theme.controlBackground
        }
    }

    private func titleColor(for style: KeyStyle) -> UIColor {
        switch style {
        case .letter:
            return Theme.text
        case .space, .control, .returnKey:
            return Theme.mutedText
        }
    }

    private func refreshLetterLabels() {
        letterButtons.forEach { button, lowercasedLetter in
            let title = isShifted || isCapsLocked ? lowercasedLetter.uppercased() : lowercasedLetter
            button.setTitle(title, for: .normal)
        }
    }

    private func refreshModeKeys() {
        shiftButton?.backgroundColor = isShifted || isCapsLocked ? Theme.activeControlBackground : backgroundColor(for: .control)
        modeButton?.setTitle(mode == .letters ? "123" : "ABC", for: .normal)
    }

    private func insertLetter(_ lowercasedLetter: String, touchObservation: TouchObservation?) {
        let text = isShifted || isCapsLocked ? lowercasedLetter.uppercased() : lowercasedLetter
        textDocumentProxy.insertText(text)

        if let touchObservation {
            currentWordTouches.append(touchObservation)
        }

        if isShifted && !isCapsLocked {
            isShifted = false
            refreshLetterLabels()
            refreshModeKeys()
        }

        refreshAutocorrectionSuggestion()
    }

    private func touchObservation(for touchLocation: CGPoint, typedLetter: String) -> TouchObservation? {
        guard let typedCharacter = typedLetter.first else {
            return nil
        }

        let sigmaX: CGFloat = 22
        let sigmaY: CGFloat = 18
        var scores: [Character: Double] = [:]

        for (button, lowercasedLetter) in letterButtons {
            guard let letter = lowercasedLetter.first else {
                continue
            }

            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: view)
            let dx = Double((touchLocation.x - center.x) / sigmaX)
            let dy = Double((touchLocation.y - center.y) / sigmaY)
            scores[letter] = exp(-0.5 * (dx * dx + dy * dy))
        }

        let totalScore = scores.values.reduce(0, +)
        guard totalScore > 0 else {
            return nil
        }

        let logProbabilities = scores.mapValues { score in
            log(max(score / totalScore, 0.00001))
        }

        return TouchObservation(typedLetter: typedCharacter, logProbabilities: logProbabilities)
    }

    private func handle(_ action: KeyAction) {
        performKeyFeedback()

        switch action {
        case .character(let lowercasedLetter):
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            textDocumentProxy.insertText(lowercasedLetter)
            refreshAutocorrectionSuggestion()

        case .punctuation(let punctuation):
            if let appliedAutocorrection = applyAutocorrectionIfNeeded() {
                recordAutocorrection(appliedAutocorrection)
            }
            currentWordTouches.removeAll()
            textDocumentProxy.insertText(punctuation)
            shouldReturnToLettersAfterSpace = shouldReturnToLettersAfterPunctuation(punctuation)
            refreshAutocorrectionSuggestion()

        case .backspace:
            shouldReturnToLettersAfterSpace = false
            textDocumentProxy.deleteBackward()
            if currentWordTouches.isEmpty {
                currentWordTouches.removeAll()
            } else {
                currentWordTouches.removeLast()
            }
            refreshAutocorrectionSuggestion()

        case .shift:
            toggleShift()

        case .space:
            let shouldReturnToLetters = shouldReturnToLettersAfterSpace
            shouldReturnToLettersAfterSpace = false
            let appliedAutocorrection = applyAutocorrectionIfNeeded()
            currentWordTouches.removeAll()
            textDocumentProxy.insertText(" ")
            if let appliedAutocorrection {
                recordAutocorrection(appliedAutocorrection)
            }

            if shouldReturnToLetters {
                mode = .letters
                renderKeyboard()
            }

            refreshAutocorrectionSuggestion()

        case .returnKey:
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            textDocumentProxy.insertText("\n")
            refreshAutocorrectionSuggestion()

        case .switchKeyboard:
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            advanceToNextInputMode()

        case .toggleMode:
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            mode = mode == .letters ? .symbols : .letters
            renderKeyboard()

        case .toggleMoreSymbols:
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            mode = mode == .moreSymbols ? .symbols : .moreSymbols
            renderKeyboard()

        case .toggleEmoji:
            shouldReturnToLettersAfterSpace = false
            currentWordTouches.removeAll()
            mode = mode == .emoji ? .letters : .emoji
            renderKeyboard()
        }
    }

    private func shouldReturnToLettersAfterPunctuation(_ punctuation: String) -> Bool {
        (mode == .symbols || mode == .moreSymbols) && [".", ",", "?", "!", "'"].contains(punctuation)
    }

    private func toggleShift() {
        let now = Date()
        let isDoubleTap = now.timeIntervalSince(lastShiftTap) < 0.35
        lastShiftTap = now

        if isDoubleTap {
            isCapsLocked.toggle()
            isShifted = isCapsLocked
        } else {
            isCapsLocked = false
            isShifted.toggle()
        }

        refreshLetterLabels()
        refreshModeKeys()
    }

    private func refreshAutocorrectionSuggestion() {
        pendingAutocorrection = currentPendingAutocorrection()
        if let revertAutocorrection = currentRevertAutocorrection() {
            suggestionBarState = .revert(revertAutocorrection)
        } else if let pendingAutocorrection {
            suggestionBarState = .pending(pendingAutocorrection)
        } else {
            suggestionBarState = nil
        }

        refreshSuggestionBar()
        refreshSpaceKey()
    }

    private func refreshSuggestionBar() {
        guard mode == .letters else {
            suggestionButton?.isHidden = true
            return
        }

        switch suggestionBarState {
        case .pending(let autocorrection):
            suggestionButton?.setTitle(autocorrection.replacement, for: .normal)
            suggestionButton?.isHidden = false

        case .revert(let autocorrection):
            suggestionButton?.setTitle(autocorrection.original, for: .normal)
            suggestionButton?.isHidden = false

        case nil:
            suggestionButton?.isHidden = true
        }
    }

    private func handleSuggestionTap() {
        guard let suggestionBarState else {
            return
        }

        performKeyFeedback()

        switch suggestionBarState {
        case .pending(let autocorrection):
            replaceCurrentWord(with: autocorrection.replacement)
            recordAutocorrection(autocorrection.withContext(textDocumentProxy.documentContextBeforeInput))

        case .revert(let autocorrection):
            replaceCurrentWord(with: autocorrection.original)
            autocorrectionHistory.removeAll { $0 == autocorrection }
        }

        currentWordTouches.removeAll()
        refreshAutocorrectionSuggestion()
    }

    private func currentPendingAutocorrection() -> AppliedAutocorrection? {
        guard mode == .letters,
              selectedTextForTranslation == nil,
              let word = currentWordBeforeCursor(),
              let replacement = autocorrector.replacement(for: word, touches: matchingTouches(for: word)),
              replacement != word
        else {
            return nil
        }

        return AppliedAutocorrection(original: word, replacement: replacement)
    }

    private func currentRevertAutocorrection() -> AppliedAutocorrection? {
        guard mode == .letters,
              selectedTextForTranslation == nil,
              let word = currentWordBeforeCursor(),
              let context = textDocumentProxy.documentContextBeforeInput
        else {
            return nil
        }

        return autocorrectionHistory.last {
            $0.replacement.caseInsensitiveCompare(word) == .orderedSame
                && $0.contextAfterReplacement == context
        }
    }

    @discardableResult
    private func applyAutocorrectionIfNeeded() -> AppliedAutocorrection? {
        guard let word = currentWordBeforeCursor(),
              let replacement = autocorrector.replacement(for: word, touches: matchingTouches(for: word)),
              replacement != word
        else {
            return nil
        }

        word.forEach { _ in textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
        return AppliedAutocorrection(
            original: word,
            replacement: replacement,
            contextAfterReplacement: textDocumentProxy.documentContextBeforeInput
        )
    }

    private func replaceCurrentWord(with replacement: String) {
        guard let word = currentWordBeforeCursor() else {
            return
        }

        for _ in 0..<word.count {
            textDocumentProxy.deleteBackward()
        }

        textDocumentProxy.insertText(replacement)
    }

    private func recordAutocorrection(_ autocorrection: AppliedAutocorrection) {
        autocorrectionHistory.append(autocorrection)

        if autocorrectionHistory.count > 20 {
            autocorrectionHistory.removeFirst(autocorrectionHistory.count - 20)
        }
    }

    private func matchingTouches(for word: String) -> [TouchObservation] {
        let containsOnlyLetters = word.allSatisfy { $0.isLetter }
        guard containsOnlyLetters, currentWordTouches.count == word.count else {
            return []
        }

        return currentWordTouches
    }

    private func currentWordBeforeCursor() -> String? {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            return nil
        }

        var characters: [Character] = []

        for character in context.reversed() {
            if character.isLetter || character == "'" {
                characters.append(character)
            } else {
                break
            }
        }

        let word = String(characters.reversed())
        return word.isEmpty ? nil : word
    }

    private func beginDeletePress() {
        stopDeleteRepeat()
        deleteBackwardFromKey()

        let timer = Timer(timeInterval: 0.42, repeats: false) { [weak self] _ in
            self?.startDeleteRepeat(interval: 0.09)
        }

        deleteInitialTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startDeleteRepeat(interval: TimeInterval) {
        deleteRepeatCount = 0

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.deleteRepeatCount += 1
            self.deleteBackwardFromKey()

            if self.deleteRepeatCount == 10 {
                timer.invalidate()
                self.startDeleteRepeat(interval: 0.055)
            }
        }

        deleteTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func deleteBackwardFromKey() {
        performKeyFeedback()

        shouldReturnToLettersAfterSpace = false
        textDocumentProxy.deleteBackward()

        if currentWordTouches.isEmpty {
            currentWordTouches.removeAll()
        } else {
            currentWordTouches.removeLast()
        }

        refreshAutocorrectionSuggestion()
    }

    private func stopDeleteRepeat() {
        deleteInitialTimer?.invalidate()
        deleteInitialTimer = nil
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteRepeatCount = 0
    }
}

private struct TouchObservation {
    let typedLetter: Character
    let logProbabilities: [Character: Double]

    func logProbability(for letter: Character) -> Double {
        logProbabilities[Character(letter.lowercased())] ?? log(0.00001)
    }
}

private struct AppliedAutocorrection: Equatable {
    let original: String
    let replacement: String
    let contextAfterReplacement: String?

    init(original: String, replacement: String, contextAfterReplacement: String? = nil) {
        self.original = original
        self.replacement = replacement
        self.contextAfterReplacement = contextAfterReplacement
    }

    func withContext(_ context: String?) -> AppliedAutocorrection {
        AppliedAutocorrection(
            original: original,
            replacement: replacement,
            contextAfterReplacement: context
        )
    }
}

private enum SuggestionBarState {
    case pending(AppliedAutocorrection)
    case revert(AppliedAutocorrection)
}

private enum KeyboardTranslationError: Error {
    case fullAccessRequired
    case missingAPIKey
}

private final class TopRowHitProxyView: UIView {
    var onTap: ((CGPoint) -> Void)?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }

        onTap?(touch.location(in: self))
        super.touchesEnded(touches, with: event)
    }
}

private class ExpandedHitButton: UIButton {
    fileprivate var hitTestOutsets = UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: hitTestOutsets).contains(point)
    }
}

private final class LetterKeyButton: ExpandedHitButton {
    var onTap: ((LetterKeyButton, CGPoint) -> Void)?

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        defer {
            super.endTracking(touch, with: event)
        }

        guard let touch else {
            return
        }

        let localPoint = touch.location(in: self)
        guard point(inside: localPoint, with: event) else {
            return
        }

        onTap?(self, localPoint)
    }
}

private final class DeleteKeyButton: ExpandedHitButton {
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    private var isPressing = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        isPressing = true
        onPressBegan?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPressing {
            onPressEnded?()
        }
        isPressing = false
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPressing {
            onPressEnded?()
        }
        isPressing = false
        super.touchesCancelled(touches, with: event)
    }
}

private final class Autocorrector {
    private var learnedWords = Set<String>()
    private var commonWordSet = Set<String>()
    private var wordScores: [String: Double] = [:]
    private var wordsByLength: [Int: [String]] = [:]

    private let replacementMap: [String: String] = [
        "adn": "and",
        "ahve": "have",
        "becuase": "because",
        "beleive": "believe",
        "cant": "can't",
        "definately": "definitely",
        "dont": "don't",
        "goign": "going",
        "haev": "have",
        "hte": "the",
        "im": "I'm",
        "ive": "I've",
        "jsut": "just",
        "knwo": "know",
        "mkae": "make",
        "nead": "need",
        "recieve": "receive",
        "seperate": "separate",
        "teh": "the",
        "thats": "that's",
        "theres": "there's",
        "theyre": "they're",
        "thier": "their",
        "thsi": "this",
        "tjis": "this",
        "whta": "what",
        "wierd": "weird",
        "youre": "you're"
    ]

    private let fallbackRankedCommonWords = [
        "the", "and", "you", "that", "this", "with", "for", "not", "was", "are",
        "about", "actually", "after", "again", "also", "always", "another", "anything", "around", "because",
        "before", "being", "better", "between", "business", "calling", "coming", "could", "delete", "different",
        "digital", "does", "doing", "done", "enough", "every", "especially", "family", "first", "friend",
        "from", "getting", "going", "good", "great", "happy", "have", "hello", "house", "keyboard", "layout",
        "letter", "little", "maybe", "message", "might", "money", "needs", "never", "nothing", "people",
        "phone", "please", "position", "pretty", "probably", "really", "right", "should", "something", "space",
        "still", "test", "testing", "thanks", "their", "there", "these", "thing", "think", "those",
        "through", "today", "tomorrow", "tonight", "typing", "using", "watching", "where", "which", "while",
        "would", "wrong", "yesterday", "appointment", "doctor", "meeting", "dinner", "lunch", "morning", "weekend"
    ]

    init() {
        loadFallbackVocabulary()
        loadBundledFrequencyDictionary()
    }

    private func loadFallbackVocabulary() {
        let total = Double(fallbackRankedCommonWords.count)
        fallbackRankedCommonWords.enumerated().forEach { index, word in
            addWord(word, score: (total - Double(index)) / total)
        }
    }

    private func loadBundledFrequencyDictionary() {
        guard let url = Bundle.main.url(forResource: "WordFrequencies", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let frequencies = try? JSONDecoder().decode([String: Double].self, from: data)
        else {
            return
        }

        frequencies.forEach { word, score in
            addWord(word, score: score)
        }
    }

    private func addWord(_ rawWord: String, score: Double) {
        let word = rawWord.lowercased()
        guard word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" }) else {
            return
        }

        if !commonWordSet.contains(word) {
            commonWordSet.insert(word)
            wordsByLength[word.count, default: []].append(word)
        }

        wordScores[word] = max(score, wordScores[word] ?? 0)
    }

    func addLexiconEntries(_ entries: [UILexiconEntry]) {
        entries.forEach { entry in
            learnedWords.insert(entry.userInput.lowercased())
            learnedWords.insert(entry.documentText.lowercased())
        }
    }

    func replacement(for word: String, touches: [TouchObservation]) -> String? {
        let lowercasedWord = word.lowercased()

        guard lowercasedWord.count >= 2 else {
            return nil
        }

        if let replacement = replacementMap[lowercasedWord] {
            return replacement.applyingCasing(from: word)
        }

        if learnedWords.contains(lowercasedWord) || commonWordSet.contains(lowercasedWord) {
            return nil
        }

        guard lowercasedWord.count >= 4 else {
            return nil
        }

        guard let bestCandidate = bestCandidate(for: lowercasedWord, touches: touches) else {
            return nil
        }

        return bestCandidate.applyingCasing(from: word)
    }

    private func bestCandidate(for word: String, touches: [TouchObservation]) -> String? {
        let maxDistance = word.count >= 6 ? 2 : 1
        var bestCandidate: String?
        var bestScore = -Double.infinity

        for candidate in candidateWords(for: word, maxDistance: maxDistance) where candidate != word {
            guard let editDistance = word.editDistance(to: candidate, maxDistance: maxDistance) else {
                continue
            }

            let score = score(candidate: candidate, typedWord: word, editDistance: editDistance, touches: touches)

            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        guard let bestCandidate else {
            return nil
        }

        let minimumScore = bestCandidate.count == word.count ? -3.25 : -1.1
        return bestScore >= minimumScore ? bestCandidate : nil
    }

    private func candidateWords(for word: String, maxDistance: Int) -> [String] {
        let lengthRange = max(1, word.count - maxDistance)...(word.count + maxDistance)
        var candidates: [String] = []

        for length in lengthRange {
            candidates.append(contentsOf: wordsByLength[length, default: []])
        }

        candidates.append(contentsOf: learnedWords.filter { abs($0.count - word.count) <= maxDistance })
        candidates.append(contentsOf: replacementMap.values.map { $0.lowercased() }.filter { abs($0.count - word.count) <= maxDistance })
        return candidates
    }

    private func score(candidate: String, typedWord: String, editDistance: Int, touches: [TouchObservation]) -> Double {
        let frequencyScore = wordScores[candidate] ?? (learnedWords.contains(candidate) ? 0.65 : 0.3)
        let frequencyBoost = log(max(frequencyScore, 0.05)) * 0.55
        let editPenalty = Double(editDistance) * 0.95
        let rawTouchBoost = touchDelta(candidate: candidate, typedWord: typedWord, touches: touches) * 0.7
        let touchBoost = min(max(rawTouchBoost, -1.5), 1.2)

        return frequencyBoost - editPenalty + touchBoost
    }

    private func touchDelta(candidate: String, typedWord: String, touches: [TouchObservation]) -> Double {
        let candidateLetters = Array(candidate)
        guard !touches.isEmpty, touches.count == candidateLetters.count, typedWord.count == candidateLetters.count else {
            return 0
        }

        let deltas = zip(touches, candidateLetters).compactMap { observation, candidateLetter -> Double? in
            guard observation.typedLetter.lowercased() != candidateLetter.lowercased() else {
                return nil
            }

            return observation.logProbability(for: candidateLetter) - observation.logProbability(for: observation.typedLetter)
        }

        guard !deltas.isEmpty else {
            return 0
        }

        return deltas.reduce(0, +) / Double(deltas.count)
    }
}

private extension String {
    func applyingCasing(from original: String) -> String {
        if original == original.uppercased() {
            return uppercased()
        }

        guard let first = original.first, first.isUppercase else {
            return self
        }

        return prefix(1).uppercased() + dropFirst()
    }

    func isOneEditAway(from other: String) -> Bool {
        let source = Array(self)
        let target = Array(other)

        if source == target {
            return true
        }

        if abs(source.count - target.count) > 1 {
            return false
        }

        if source.count == target.count {
            let mismatchedIndices = source.indices.filter { source[$0] != target[$0] }

            if mismatchedIndices.count == 1 {
                return true
            }

            if mismatchedIndices.count == 2,
               mismatchedIndices[1] == mismatchedIndices[0] + 1,
               source[mismatchedIndices[0]] == target[mismatchedIndices[1]],
               source[mismatchedIndices[1]] == target[mismatchedIndices[0]] {
                return true
            }

            return false
        }

        let shorter = source.count < target.count ? source : target
        let longer = source.count < target.count ? target : source
        var shorterIndex = 0
        var longerIndex = 0
        var skippedCharacter = false

        while shorterIndex < shorter.count && longerIndex < longer.count {
            if shorter[shorterIndex] == longer[longerIndex] {
                shorterIndex += 1
                longerIndex += 1
            } else if skippedCharacter {
                return false
            } else {
                skippedCharacter = true
                longerIndex += 1
            }
        }

        return true
    }

    func editDistance(to other: String, maxDistance: Int) -> Int? {
        let source = Array(self)
        let target = Array(other)

        if abs(source.count - target.count) > maxDistance {
            return nil
        }

        var previousRow = Array(0...target.count)

        for sourceIndex in 1...source.count {
            var currentRow = [sourceIndex]
            var rowMinimum = sourceIndex

            for targetIndex in 1...target.count {
                let substitutionCost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1
                let insertion = currentRow[targetIndex - 1] + 1
                let deletion = previousRow[targetIndex] + 1
                let substitution = previousRow[targetIndex - 1] + substitutionCost
                let value = Swift.min(insertion, deletion, substitution)
                currentRow.append(value)
                rowMinimum = Swift.min(rowMinimum, value)
            }

            if rowMinimum > maxDistance {
                return nil
            }

            previousRow = currentRow
        }

        let distance = previousRow[target.count]
        return distance <= maxDistance ? distance : nil
    }
}
