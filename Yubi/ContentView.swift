import Combine
import os
import SwiftUI
import UIKit

private let shortcutURLLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "ShortcutURL"
)

@MainActor
private final class AnalysisBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

private enum ContentTab: String {
    case intro
    case setup
    case history
}

private enum OnboardingStep: Int, CaseIterable {
    case intro
    case backend
    case keyboard
    case shortcut
    case done
}

private enum SetupPane: String {
    case screenshots
    case textSelections
}

private enum HistoryPane: String {
    case screenshots
    case textEdits
}

private enum APIKeyField: Hashable {
    case openAI
    case claude
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("YubiHasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("YubiSelectedTab") private var selectedTabValue = ContentTab.intro.rawValue
    @AppStorage("YubiSelectedSetupPane") private var selectedSetupPaneValue = SetupPane.screenshots.rawValue
    @AppStorage("YubiSelectedHistoryAnalysisID") private var selectedHistoryAnalysisID = ""
    @AppStorage("YubiSelectedHistoryPane") private var selectedHistoryPaneValue = HistoryPane.screenshots.rawValue
    @AppStorage("YubiOnboardingStep") private var onboardingStepValue = OnboardingStep.intro.rawValue
    @State private var selectedTab: ContentTab = .intro
    @State private var selectedSetupPane: SetupPane = .screenshots
    @State private var selectedHistoryPane: HistoryPane = .screenshots
    @State private var historyPath: [UUID] = []
    @State private var analyses = ScreenshotAnalysisStore.loadHistory()
    @State private var textEditHistory = TextEditHistoryStore.loadHistory()
    @State private var analysisStatus = ScreenshotAnalysisStatusStore.load()
    @State private var selectedAIBackend = AIBackendSettings.selectedBackend
    @State private var openAIAPIKey = AIBackendSettings.openAIAPIKey
    @State private var claudeAPIKey = AIBackendSettings.claudeAPIKey
    @State private var didCopyShortcutPrompt = false
    @State private var shortcutStatusMessage: String?
    @State private var isAnalyzingShortcutText = false
    @State private var resumingAnalysisIDs: Set<UUID> = []
    @State private var autoNavigatedAnalysisIDs: Set<UUID> = []
    @State private var shouldRevealAnalysisWhenFinished = false
    @FocusState private var focusedAPIKeyField: APIKeyField?

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var onboardingStep: OnboardingStep {
        OnboardingStep(rawValue: onboardingStepValue) ?? .intro
    }

    private var isShowingAnalysisSplash: Bool {
        guard hasCompletedOnboarding else {
            return false
        }

        if analysisStatus.phase == .running {
            return true
        }

        // Warm Action Button launches can mark running before @State catches up.
        return ScreenshotAnalysisStatusStore.load().phase == .running
    }

    var body: some View {
        ZStack {
            Group {
                if hasCompletedOnboarding {
                    mainTabs
                } else {
                    onboarding
                }
            }

            if isShowingAnalysisSplash {
                analysisSplashView
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingAnalysisSplash)
        .onAppear {
            restoreNavigationState()
            refreshAnalysisState()
        }
        .onChange(of: selectedTab) { _, newTab in
            selectedTabValue = newTab.rawValue

            if newTab != .history {
                selectedHistoryAnalysisID = ""
            }
        }
        .onChange(of: historyPath) { _, newPath in
            selectedHistoryAnalysisID = newPath.last?.uuidString ?? ""
        }
        .onChange(of: selectedSetupPane) { _, newPane in
            selectedSetupPaneValue = newPane.rawValue
        }
        .onChange(of: selectedHistoryPane) { _, newPane in
            selectedHistoryPaneValue = newPane.rawValue
        }
        .onChange(of: selectedAIBackend) { _, newBackend in
            AIBackendSettings.selectedBackend = newBackend
        }
        .onChange(of: openAIAPIKey) { _, newKey in
            AIBackendSettings.openAIAPIKey = newKey
        }
        .onChange(of: claudeAPIKey) { _, newKey in
            AIBackendSettings.claudeAPIKey = newKey
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshAnalysisState()
            }
        }
        .onReceive(refreshTimer) { _ in
            refreshAnalysisState()
        }
        .onOpenURL(perform: handleIncomingURL)
    }

    private var analysisSplashView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(AppCopy.title)
                    .font(.largeTitle.bold())

                ProgressView()
                    .controlSize(.large)
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text(AppCopy.analysisRunningTitle)
                        .font(.title3.weight(.semibold))

                    Text(
                        analysisStatus.message
                            ?? AppCopy.analysisRunningBody(
                                backendName: AIBackendSettings.selectedBackend.displayName,
                                isImage: true
                            )
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppCopy.title). \(AppCopy.analysisRunningTitle)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            introTab
                .tabItem {
                    Label(AppCopy.introTab, systemImage: "hand.point.up.left")
                }
                .tag(ContentTab.intro)

            setupTab
                .tabItem {
                    Label(AppCopy.setupTab, systemImage: "gearshape")
                }
                .tag(ContentTab.setup)

            historyTab
                .tabItem {
                    Label(AppCopy.historyTab, systemImage: "clock")
                }
                .tag(ContentTab.history)
        }
    }

    private var onboarding: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(AppCopy.onboardingStepLabel(current: onboardingStep.rawValue + 1, total: OnboardingStep.allCases.count))
                            .font(.callout.bold())
                            .foregroundStyle(.secondary)

                        onboardingStepContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(AppCopy.skipOnboarding) {
                        completeOnboarding()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if onboardingStep.rawValue > 0 {
                        Button(AppCopy.backButton) {
                            moveOnboardingBack()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(onboardingStep == .done ? AppCopy.doneButton : AppCopy.nextButton) {
                        moveOnboardingForward()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle(AppCopy.onboardingTitle)
        }
    }

    @ViewBuilder
    private var onboardingStepContent: some View {
        switch onboardingStep {
        case .intro:
            VStack(alignment: .leading, spacing: 16) {
                onboardingHeader(
                    title: AppCopy.onboardingWhatIsYubiTitle,
                    body: AppCopy.onboardingWhatIsYubiBody
                )
                featureSummary
                privacyBlurb
            }
        case .backend:
            VStack(alignment: .leading, spacing: 16) {
                onboardingHeader(
                    title: AppCopy.onboardingBackendTitle,
                    body: AppCopy.onboardingBackendBody
                )
                aiBackendSetup(showHeader: false)
            }
        case .keyboard:
            VStack(alignment: .leading, spacing: 16) {
                onboardingHeader(
                    title: AppCopy.onboardingKeyboardTitle,
                    body: AppCopy.onboardingKeyboardBody
                )
                setup
            }
        case .shortcut:
            VStack(alignment: .leading, spacing: 16) {
                onboardingHeader(
                    title: AppCopy.onboardingShortcutTitle,
                    body: AppCopy.onboardingShortcutBody(supportsSmartCreation: supportsShortcutSmartCreation)
                )
                actionButtonSetup
            }
        case .done:
            VStack(alignment: .leading, spacing: 16) {
                onboardingHeader(
                    title: AppCopy.onboardingDoneTitle
                )
                featureSummary
            }
        }
    }

    private func onboardingHeader(title: String, body: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            if let body, !body.isEmpty {
                Text(body)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func moveOnboardingForward() {
        guard let nextStep = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else {
            completeOnboarding()
            return
        }

        onboardingStepValue = nextStep.rawValue
    }

    private func moveOnboardingBack() {
        guard let previousStep = OnboardingStep(rawValue: onboardingStep.rawValue - 1) else {
            return
        }

        onboardingStepValue = previousStep.rawValue
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onboardingStepValue = OnboardingStep.intro.rawValue
        selectedTab = .intro
        selectedTabValue = ContentTab.intro.rawValue
    }

    private func restartOnboarding() {
        onboardingStepValue = OnboardingStep.intro.rawValue
        hasCompletedOnboarding = false
    }

    private var introTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introHero
                    featureSummary
                    privacyBlurb
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(AppCopy.introTitle)
        }
    }

    private var setupTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button(action: restartOnboarding) {
                        Label(AppCopy.runSetupGuideAgain, systemImage: "list.bullet.clipboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    aiBackendSetup()

                    Picker(AppCopy.setupTitle, selection: $selectedSetupPane) {
                        Text(AppCopy.screenshotsPane).tag(SetupPane.screenshots)
                        Text(AppCopy.textSelectionsPane).tag(SetupPane.textSelections)
                    }
                    .pickerStyle(.segmented)

                    if selectedSetupPane == .screenshots {
                        actionButtonSetup
                    } else {
                        textSelectionSetup
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(AppCopy.setupTitle)
        }
    }

    private var textSelectionSetup: some View {
        VStack(alignment: .leading, spacing: 24) {
            hero
            setup
        }
    }

    private func aiBackendSetup(showHeader: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                Label(AppCopy.aiBackendTitle, systemImage: "brain")
                    .font(.title2.bold())
            }

            VStack(spacing: 10) {
                ForEach(AIBackend.allCases) { backend in
                    Button {
                        guard backend.isAvailable else {
                            return
                        }

                        selectedAIBackend = backend
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedAIBackend == backend ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAIBackend == backend ? Color.accentColor : .secondary)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppCopy.aiBackendOptionTitle(backend))
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(AppCopy.aiBackendOptionDetail(backend))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!backend.isAvailable)
                    .opacity(backend.isAvailable ? 1 : 0.55)
                }
            }

            if selectedAIBackend == .openAI {
                HStack(spacing: 10) {
                    SecureField(AppCopy.openAIAPIKeyPlaceholder, text: $openAIAPIKey)
                        .focused($focusedAPIKeyField, equals: .openAI)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedAPIKeyField = nil
                        }

                    if !openAIAPIKey.isEmpty {
                        Button(role: .destructive) {
                            openAIAPIKey = ""
                            focusedAPIKeyField = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .accessibilityLabel(AppCopy.removeAPIKey)
                    }
                }
                .padding(12)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                Text(AppCopy.openAIModelNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if selectedAIBackend == .claudeFable {
                HStack(spacing: 10) {
                    SecureField(AppCopy.claudeAPIKeyPlaceholder, text: $claudeAPIKey)
                        .focused($focusedAPIKeyField, equals: .claude)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedAPIKeyField = nil
                        }

                    if !claudeAPIKey.isEmpty {
                        Button(role: .destructive) {
                            claudeAPIKey = ""
                            focusedAPIKeyField = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .accessibilityLabel(AppCopy.removeAPIKey)
                    }
                }
                .padding(12)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            Text(AppCopy.aiBackendStorageNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var historyTab: some View {
        NavigationStack(path: $historyPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(AppCopy.historyTitle, selection: $selectedHistoryPane) {
                        Text(AppCopy.screenshotsPane).tag(HistoryPane.screenshots)
                        Text(AppCopy.textEditsPane).tag(HistoryPane.textEdits)
                    }
                    .pickerStyle(.segmented)

                    if selectedHistoryPane == .screenshots && analysisStatus.phase == .running {
                        analysisProgressView
                    }

                    if selectedHistoryPane == .screenshots {
                        screenshotHistoryList
                    } else {
                        textEditHistoryList
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(AppCopy.historyTitle)
            .navigationDestination(for: UUID.self) { analysisID in
                AnalysisDetailView(analysisID: analysisID)
            }
        }
    }

    @ViewBuilder
    private var screenshotHistoryList: some View {
        if screenshotAnalyses.isEmpty {
            ContentUnavailableView(
                AppCopy.noHistoryTitle,
                systemImage: "doc.text.magnifyingglass",
                description: Text(AppCopy.noHistoryBody)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            ForEach(groupedAnalyses) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ForEach(group.analyses) { analysis in
                        NavigationLink(value: analysis.id) {
                            AnalysisHistoryCard(analysis: analysis)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var textEditHistoryList: some View {
        if textEditHistory.isEmpty {
            ContentUnavailableView(
                AppCopy.noTextEditHistoryTitle,
                systemImage: "text.cursor",
                description: Text(AppCopy.noTextEditHistoryBody)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            ForEach(groupedTextEdits) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ForEach(group.items) { item in
                        TextEditHistoryCard(item: item)
                    }
                }
            }
        }
    }

    private var analysisProgressView: some View {
        HStack(spacing: 12) {
            ProgressView()

            VStack(alignment: .leading, spacing: 2) {
                Text(AppCopy.analysisRunningTitle)
                    .font(.headline)

                Text(analysisStatus.message ?? AppCopy.analysisRunningBody(backendName: AIBackendSettings.selectedBackend.displayName, isImage: true))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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

    private var introHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppCopy.introSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var featureSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureRow(
                systemImage: "photo",
                title: AppCopy.screenshotsPane,
                description: AppCopy.introScreenshotsFeature
            )

            FeatureRow(
                systemImage: "text.cursor",
                title: AppCopy.textSelectionsPane,
                description: AppCopy.introTextSelectionsFeature
            )
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
            StepView(number: 3, text: AppCopy.stepSwitchKeyboard)
            StepView(number: 4, text: AppCopy.stepTranslate)
        }
    }

    private var actionButtonSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppCopy.actionButtonTitle, systemImage: "button.programmable")
                .font(.title2.bold())

            Text(AppCopy.actionButtonBody(supportsSmartCreation: supportsShortcutSmartCreation))
                .foregroundStyle(.secondary)

            Text(AppCopy.shortcutPrompt)
                .font(.callout.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            if isAnalyzingShortcutText {
                Label(AppCopy.analyzingShortcutText, systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let shortcutStatusMessage {
                Text(shortcutStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: copyShortcutPrompt) {
                    Label(didCopyShortcutPrompt ? AppCopy.copiedPrompt : AppCopy.copyShortcutPrompt, systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: openShortcuts) {
                    Label(AppCopy.openShortcuts, systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Text(AppCopy.actionButtonFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var supportsShortcutSmartCreation: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }

    private func copyShortcutPrompt() {
        UIPasteboard.general.string = AppCopy.shortcutPrompt
        didCopyShortcutPrompt = true
    }

    private func openShortcuts() {
        guard let shortcutsURL = URL(string: "shortcuts://create-shortcut"),
              let appStoreURL = URL(string: "https://apps.apple.com/app/shortcuts/id1462947752")
        else {
            return
        }

        UIApplication.shared.open(shortcutsURL) { didOpen in
            if !didOpen {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "yubi" else {
            return
        }

        let route = url.host?.lowercased() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard route.isEmpty || route == "analyze" || route == "analyze-clipboard" else {
            shortcutURLLogger.warning("Ignoring unsupported URL route: \(route, privacy: .public)")
            return
        }

        let text = textParameter(from: url) ?? UIPasteboard.general.string
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedText.isEmpty else {
            shortcutURLLogger.warning("Shortcut URL opened without text")
            shortcutStatusMessage = AppCopy.noShortcutText
            return
        }

        shortcutURLLogger.info("Shortcut URL analysis started; characters=\(trimmedText.count, privacy: .public)")
        isAnalyzingShortcutText = true
        shortcutStatusMessage = nil
        ScreenshotAnalysisStatusStore.markRunning(AppCopy.analyzingShortcutText)

        Task {
            do {
                let result = try await ScreenshotTextAnalyzer.analyze(trimmedText)
                let analysis = ScreenshotAnalysis(date: Date(), detectedText: trimmedText, result: result)
                ScreenshotAnalysisStore.save(analysis)
                ScreenshotAnalysisStatusStore.markCompleted(AppCopy.shortcutAnalysisComplete)

                await MainActor.run {
                    analyses = ScreenshotAnalysisStore.loadHistory()
                    analysisStatus = ScreenshotAnalysisStatusStore.load()
                    isAnalyzingShortcutText = false
                    shortcutStatusMessage = AppCopy.shortcutAnalysisComplete
                }
                shortcutURLLogger.info("Shortcut URL analysis completed; resultCharacters=\(result.count, privacy: .public)")
            } catch {
                await MainActor.run {
                    analysisStatus = ScreenshotAnalysisStatusStore.load()
                    isAnalyzingShortcutText = false
                    shortcutStatusMessage = AppCopy.shortcutAnalysisFailed
                }
                ScreenshotAnalysisStatusStore.markFailed(AppCopy.shortcutAnalysisFailed)
                shortcutURLLogger.error("Shortcut URL analysis failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func textParameter(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "text" }?
            .value
    }

    private func refreshAnalysisState() {
        analyses = ScreenshotAnalysisStore.loadHistory()
        textEditHistory = TextEditHistoryStore.loadHistory()
        analysisStatus = ScreenshotAnalysisStatusStore.load()
        removeStaleHistoryPathIfNeeded()
        prepareRunningAnalysisUIIfNeeded()
        navigateToFinishedAnalysisIfNeeded()
        resumePendingAnalysesIfNeeded()
    }

    private func restoreNavigationState() {
        analyses = ScreenshotAnalysisStore.loadHistory()
        textEditHistory = TextEditHistoryStore.loadHistory()
        analysisStatus = ScreenshotAnalysisStatusStore.load()

        if let restoredPane = SetupPane(rawValue: selectedSetupPaneValue) {
            selectedSetupPane = restoredPane
        }

        // While a shortcut/Action Button analysis is in flight, skip restoring the
        // previous history detail so it does not flash under the splash screen.
        if analysisStatus.phase == .running {
            shouldRevealAnalysisWhenFinished = true
            hasCompletedOnboarding = true
            selectedHistoryPane = .screenshots
            selectedHistoryPaneValue = HistoryPane.screenshots.rawValue
            selectedTab = .history
            selectedTabValue = ContentTab.history.rawValue
            historyPath = []
            selectedHistoryAnalysisID = ""
            return
        }

        if let restoredTab = ContentTab(rawValue: selectedTabValue) {
            selectedTab = restoredTab
        }

        if let restoredPane = HistoryPane(rawValue: selectedHistoryPaneValue) {
            selectedHistoryPane = restoredPane
        }

        if selectedTab == .history,
           let analysisID = UUID(uuidString: selectedHistoryAnalysisID),
           analyses.contains(where: { $0.id == analysisID }) {
            historyPath = [analysisID]
        } else if selectedTab != .history {
            historyPath = []
        }
    }

    private func removeStaleHistoryPathIfNeeded() {
        guard let analysisID = historyPath.last else {
            return
        }

        if !analyses.contains(where: { $0.id == analysisID }) {
            historyPath = []
            selectedHistoryAnalysisID = ""
        }
    }

    private func prepareRunningAnalysisUIIfNeeded() {
        guard analysisStatus.phase == .running else {
            return
        }

        shouldRevealAnalysisWhenFinished = true
        hasCompletedOnboarding = true
        onboardingStepValue = OnboardingStep.intro.rawValue
        selectedHistoryPane = .screenshots
        selectedHistoryPaneValue = HistoryPane.screenshots.rawValue
        selectedTab = .history
        selectedTabValue = ContentTab.history.rawValue

        // Keep the previous session off-screen under the splash until this run finishes.
        if !historyPath.isEmpty {
            historyPath = []
        }
        if !selectedHistoryAnalysisID.isEmpty {
            selectedHistoryAnalysisID = ""
        }
    }

    private func navigateToFinishedAnalysisIfNeeded() {
        guard shouldRevealAnalysisWhenFinished,
              analysisStatus.phase == .completed || analysisStatus.phase == .failed,
              let analysisID = analysisStatus.analysisID,
              analyses.contains(where: { $0.id == analysisID }),
              !autoNavigatedAnalysisIDs.contains(analysisID)
        else {
            return
        }

        shouldRevealAnalysisWhenFinished = false
        autoNavigatedAnalysisIDs.insert(analysisID)
        hasCompletedOnboarding = true
        onboardingStepValue = OnboardingStep.intro.rawValue
        selectedHistoryPane = .screenshots
        selectedHistoryPaneValue = HistoryPane.screenshots.rawValue
        selectedTab = .history
        selectedTabValue = ContentTab.history.rawValue
        selectedHistoryAnalysisID = analysisID.uuidString

        if historyPath.last != analysisID {
            historyPath = [analysisID]
        }
    }

    private func resumePendingAnalysesIfNeeded() {
        guard resumingAnalysisIDs.isEmpty else {
            return
        }

        let currentStatus = analysisStatus
        let pendingAnalyses = analyses.filter { analysis in
            !analysis.isComplete
                && (
                    !analysis.detectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || analysis.imageFilename != nil
                )
                && !resumingAnalysisIDs.contains(analysis.id)
                && !(currentStatus.phase == .failed && currentStatus.analysisID == analysis.id)
        }

        guard let analysis = pendingAnalyses.first(where: { $0.id == currentStatus.analysisID }) ?? pendingAnalyses.first else {
            return
        }

        resumingAnalysisIDs.insert(analysis.id)
        ScreenshotAnalysisStatusStore.markRunning(
            AppCopy.analysisRunningBody(
                backendName: AIBackendSettings.selectedBackend.displayName,
                isImage: analysis.imageFilename != nil
            ),
            analysisID: analysis.id
        )
        let backgroundTask = AnalysisBackgroundTask(name: "Screenshot analysis")

        Task {
            let notificationAuthorizationTask = Task {
                await ScreenshotAnalysisNotificationService.requestAuthorizationIfNeeded()
            }

            do {
                let resumedAnalysis = try await resumedScreenshotAnalysis(for: analysis) { message in
                    ScreenshotAnalysisStatusStore.markRunning(message, analysisID: analysis.id)
                }
                ScreenshotAnalysisStore.save(ScreenshotAnalysis(
                    id: analysis.id,
                    date: analysis.date,
                    detectedText: resumedAnalysis.detectedText,
                    result: resumedAnalysis.result,
                    imageFilename: analysis.imageFilename,
                    isComplete: true
                ))
                ScreenshotAnalysisStatusStore.markCompleted(AppCopy.shortcutAnalysisComplete, analysisID: analysis.id)
                await notificationAuthorizationTask.value
                await ScreenshotAnalysisNotificationService.notifyCompleted(analysisID: analysis.id)

                await MainActor.run {
                    backgroundTask.end()
                    resumingAnalysisIDs.remove(analysis.id)
                    refreshAnalysisState()
                }
            } catch {
                notificationAuthorizationTask.cancel()
                let message = AppCopy.analysisFailedMessage(error)
                ScreenshotAnalysisStatusStore.markFailed(message, analysisID: analysis.id)

                await MainActor.run {
                    backgroundTask.end()
                    resumingAnalysisIDs.remove(analysis.id)
                    refreshAnalysisState()
                }
                shortcutURLLogger.error("Foreground analysis resume failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func resumedScreenshotAnalysis(
        for analysis: ScreenshotAnalysis,
        status: AIBackendClient.StatusHandler? = nil
    ) async throws -> (detectedText: String, result: String) {
        if let imageData = ScreenshotAnalysisStore.imageData(for: analysis),
           AIBackendSettings.selectedBackend != .apple || analysis.detectedText.isEmpty,
           let cgImage = UIImage(data: imageData)?.cgImage {
            let imageAnalysis = try await ScreenshotTextAnalyzer.analyzeImage(cgImage, status: status)
            return (
                detectedText: imageAnalysis.transcript.isEmpty ? analysis.detectedText : imageAnalysis.transcript,
                result: imageAnalysis.result
            )
        }

        let result = try await ScreenshotTextAnalyzer.analyze(analysis.detectedText, status: status)
        return (detectedText: analysis.detectedText, result: result)
    }

    private var groupedAnalyses: [AnalysisDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: screenshotAnalyses) { analysis in
            calendar.startOfDay(for: analysis.date)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                AnalysisDayGroup(
                    date: day,
                    title: title(forAnalysisDay: day),
                    analyses: (grouped[day] ?? []).sorted { $0.date > $1.date }
                )
            }
    }

    private var screenshotAnalyses: [ScreenshotAnalysis] {
        analyses.filter { $0.imageFilename != nil }
    }

    private var groupedTextEdits: [TextEditDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: textEditHistory) { item in
            calendar.startOfDay(for: item.date)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                TextEditDayGroup(
                    date: day,
                    title: title(forAnalysisDay: day),
                    items: (grouped[day] ?? []).sorted { $0.date > $1.date }
                )
            }
    }

    private func title(forAnalysisDay day: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(day) {
            return AppCopy.todaySection
        }

        if calendar.isDateInYesterday(day) {
            return AppCopy.yesterdaySection
        }

        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private var privacyBlurb: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppCopy.privacyTitle, systemImage: "lock.shield")
                .font(.title2.bold())

            Text(AppCopy.privacyBody)

            Link(destination: URL(string: "https://github.com/littlebobert/yubi")!) {
                Text(AppCopy.githubRepoLink)
            }
            .font(.callout)
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

    static var onboardingTitle: String {
        localized(
            en: "Set Up Yubi",
            ja: "Yubiを設定",
            zhHans: "设置 Yubi",
            zhHant: "設定 Yubi",
            ko: "Yubi 설정"
        )
    }

    static func onboardingStepLabel(current: Int, total: Int) -> String {
        localized(
            en: "Step \(current) of \(total)",
            ja: "\(total)ステップ中\(current)",
            zhHans: "第 \(current) 步，共 \(total) 步",
            zhHant: "第 \(current) 步，共 \(total) 步",
            ko: "\(total)단계 중 \(current)단계"
        )
    }

    static var onboardingBackendTitle: String {
        localized(
            en: "Choose your AI backend",
            ja: "AIバックエンドを選択",
            zhHans: "选择你的 AI 后端",
            zhHant: "選擇你的 AI 後端",
            ko: "AI 백엔드 선택"
        )
    }

    static var onboardingWhatIsYubiTitle: String {
        localized(
            en: "What is Yubi?",
            ja: "Yubiとは？",
            zhHans: "Yubi 是什么？",
            zhHant: "Yubi 是什麼？",
            ko: "Yubi란?"
        )
    }

    static var onboardingWhatIsYubiBody: String {
        localized(
            en: "Yubi translates screenshots and selected text. Use Shortcuts for screenshots, or the Yubi keyboard for text you select in any app.",
            ja: "Yubiはスクリーンショットと選択したテキストを翻訳します。スクリーンショットにはショートカットを、任意のアプリで選択したテキストにはYubiキーボードを使います。",
            zhHans: "Yubi 可以翻译截图和选中的文本。截图使用快捷指令，任何 App 中选中的文本使用 Yubi 键盘。",
            zhHant: "Yubi 可以翻譯截圖和選取的文字。截圖使用捷徑，任何 App 中選取的文字使用 Yubi 鍵盤。",
            ko: "Yubi는 스크린샷과 선택한 텍스트를 번역합니다. 스크린샷은 단축어를, 어느 앱에서든 선택한 텍스트는 Yubi 키보드를 사용하세요."
        )
    }

    static var onboardingBackendBody: String {
        localized(
            en: "OpenAI or Anthropic API keys give the best translations. Apple is private and free, but weaker.",
            ja: "OpenAIまたはAnthropicのAPIキーを使うと翻訳品質が最も高くなります。Appleはプライベートで無料ですが、性能は控えめです。",
            zhHans: "OpenAI 或 Anthropic API 密钥能提供最佳翻译。Apple 私密且免费，但能力较弱。",
            zhHant: "OpenAI 或 Anthropic API 金鑰能提供最佳翻譯。Apple 私密且免費，但能力較弱。",
            ko: "OpenAI 또는 Anthropic API 키가 가장 좋은 번역을 제공합니다. Apple은 비공개이고 무료지만 성능은 더 약합니다."
        )
    }

    static var onboardingKeyboardTitle: String {
        localized(
            en: "Enable text selection translation",
            ja: "テキスト選択翻訳を有効にする",
            zhHans: "启用文本选择翻译",
            zhHant: "啟用文字選取翻譯",
            ko: "텍스트 선택 번역 활성화"
        )
    }

    static var onboardingKeyboardBody: String {
        localized(
            en: "Add Yubi as a keyboard so you can select text in any app, switch to Yubi, and translate it in place.",
            ja: "Yubiをキーボードとして追加すると、任意のアプリでテキストを選択し、Yubiに切り替えてその場で翻訳できます。",
            zhHans: "将 Yubi 添加为键盘后，你可以在任何 App 中选择文本，切换到 Yubi，并就地翻译。",
            zhHant: "將 Yubi 加入為鍵盤後，你可以在任何 App 中選取文字，切換到 Yubi，並就地翻譯。",
            ko: "Yubi를 키보드로 추가하면 어느 앱에서든 텍스트를 선택하고 Yubi로 전환해 바로 번역할 수 있습니다."
        )
    }

    static var onboardingShortcutTitle: String {
        localized(
            en: "Set up screenshot translation",
            ja: "スクリーンショット翻訳を設定",
            zhHans: "设置截图翻译",
            zhHant: "設定截圖翻譯",
            ko: "스크린샷 번역 설정"
        )
    }

    static func onboardingShortcutBody(supportsSmartCreation: Bool) -> String {
        actionButtonBody(supportsSmartCreation: supportsSmartCreation)
    }

    static var onboardingDoneTitle: String {
        localized(
            en: "You are ready",
            ja: "準備完了",
            zhHans: "准备就绪",
            zhHant: "準備就緒",
            ko: "준비 완료"
        )
    }

    static var skipOnboarding: String {
        localized(
            en: "Skip for Now",
            ja: "今はスキップ",
            zhHans: "暂时跳过",
            zhHant: "暫時跳過",
            ko: "지금은 건너뛰기"
        )
    }

    static var backButton: String {
        localized(
            en: "Back",
            ja: "戻る",
            zhHans: "返回",
            zhHant: "返回",
            ko: "뒤로"
        )
    }

    static var nextButton: String {
        localized(
            en: "Next",
            ja: "次へ",
            zhHans: "下一步",
            zhHant: "下一步",
            ko: "다음"
        )
    }

    static var doneButton: String {
        localized(
            en: "Done",
            ja: "完了",
            zhHans: "完成",
            zhHant: "完成",
            ko: "완료"
        )
    }

    static var runSetupGuideAgain: String {
        localized(
            en: "Run Setup Guide Again",
            ja: "設定ガイドを再実行",
            zhHans: "重新运行设置指南",
            zhHant: "重新執行設定指南",
            ko: "설정 가이드 다시 실행"
        )
    }

    static var introTab: String {
        localized(
            en: "Intro",
            ja: "紹介",
            zhHans: "简介",
            zhHant: "簡介",
            ko: "소개"
        )
    }

    static var introTitle: String {
        localized(
            en: "Yubi Translation",
            ja: "Yubi翻訳",
            zhHans: "Yubi 翻译",
            zhHant: "Yubi 翻譯",
            ko: "Yubi 번역"
        )
    }

    static var introSubtitle: String {
        localized(
            en: "Two quick ways to translate what you are looking at.",
            ja: "見ている内容をすばやく翻訳する2つの方法。",
            zhHans: "两种快速翻译当前内容的方式。",
            zhHant: "兩種快速翻譯目前內容的方式。",
            ko: "보고 있는 내용을 빠르게 번역하는 두 가지 방법."
        )
    }

    static var introScreenshotsFeature: String {
        localized(
            en: "Analyze a screenshot from Shortcuts, then get a summary and translation.",
            ja: "ショートカットからスクリーンショットを解析し、要約と翻訳を表示します。",
            zhHans: "从快捷指令分析截图，然后获取摘要和翻译。",
            zhHant: "從捷徑分析截圖，然後取得摘要和翻譯。",
            ko: "단축어에서 스크린샷을 분석한 뒤 요약과 번역을 받습니다."
        )
    }

    static var introTextSelectionsFeature: String {
        localized(
            en: "Select text in any app, switch to Yubi, and translate it in place.",
            ja: "任意のアプリでテキストを選択し、Yubiに切り替えて、その場で翻訳します。",
            zhHans: "在任何 App 中选中文本，切换到 Yubi，并就地翻译。",
            zhHant: "在任何 App 中選取文字，切換到 Yubi，並就地翻譯。",
            ko: "어느 앱에서든 텍스트를 선택하고 Yubi로 전환해 바로 번역합니다."
        )
    }

    static var aiBackendTitle: String {
        localized(
            en: "AI Backend",
            ja: "AIバックエンド",
            zhHans: "AI 后端",
            zhHant: "AI 後端",
            ko: "AI 백엔드"
        )
    }

    static func aiBackendOptionTitle(_ backend: AIBackend) -> String {
        switch backend {
        case .apple:
            return localized(
                en: "Apple (Coming Soon)",
                ja: "Apple（近日対応予定）",
                zhHans: "Apple（即将推出）",
                zhHant: "Apple（即將推出）",
                ko: "Apple(출시 예정)"
            )
        case .openAI:
            return "OpenAI"
        case .claudeFable:
            return "Claude Fable 5"
        }
    }

    static func aiBackendOptionDetail(_ backend: AIBackend) -> String {
        switch backend {
        case .apple:
            return localized(
                en: "weaker, but private and free",
                ja: "弱めですが、プライベートで無料",
                zhHans: "较弱，但私密且免费",
                zhHant: "較弱，但私密且免費",
                ko: "약하지만 비공개이며 무료"
            )
        case .openAI:
            return localized(
                en: "balanced",
                ja: "バランス型",
                zhHans: "均衡",
                zhHant: "均衡",
                ko: "균형형"
            )
        case .claudeFable:
            return localized(
                en: "strongest, most expensive",
                ja: "最も強力で、最も高価",
                zhHans: "最强，费用最高",
                zhHant: "最強，費用最高",
                ko: "가장 강력하고 가장 비쌈"
            )
        }
    }

    static var openAIAPIKeyPlaceholder: String {
        localized(
            en: "OpenAI API key",
            ja: "OpenAI APIキー",
            zhHans: "OpenAI API 密钥",
            zhHant: "OpenAI API 金鑰",
            ko: "OpenAI API 키"
        )
    }

    static var claudeAPIKeyPlaceholder: String {
        localized(
            en: "Claude API key",
            ja: "Claude APIキー",
            zhHans: "Claude API 密钥",
            zhHant: "Claude API 金鑰",
            ko: "Claude API 키"
        )
    }

    static var removeAPIKey: String {
        localized(
            en: "Remove API key",
            ja: "APIキーを削除",
            zhHans: "移除 API 密钥",
            zhHant: "移除 API 金鑰",
            ko: "API 키 삭제"
        )
    }

    static var openAIModelNote: String {
        localized(
            en: "Uses GPT-5.6 Sol with high reasoning.",
            ja: "GPT-5.6 Solを高推論設定で使用します。",
            zhHans: "使用 GPT-5.6 Sol，并启用高推理设置。",
            zhHant: "使用 GPT-5.6 Sol，並啟用高推理設定。",
            ko: "GPT-5.6 Sol을 높은 추론 설정으로 사용합니다."
        )
    }

    static var aiBackendStorageNote: String {
        localized(
            en: "API keys are stored securely in this device's Keychain and shared only with the Yubi keyboard.",
            ja: "APIキーはこのデバイスのキーチェーンに安全に保存され、Yubiキーボードとのみ共有されます。",
            zhHans: "API 密钥安全地存储在此设备的钥匙串中，并且仅与 Yubi 键盘共享。",
            zhHant: "API 金鑰安全地儲存在此裝置的鑰匙圈中，並且僅與 Yubi 鍵盤共享。",
            ko: "API 키는 이 기기의 키체인에 안전하게 저장되며 Yubi 키보드와만 공유됩니다."
        )
    }

    static var setupTab: String {
        localized(
            en: "Setup",
            ja: "設定",
            zhHans: "设置",
            zhHant: "設定",
            ko: "설정"
        )
    }

    static var setupTitle: String {
        localized(
            en: "Yubi Translation",
            ja: "Yubi翻訳",
            zhHans: "Yubi 翻译",
            zhHant: "Yubi 翻譯",
            ko: "Yubi 번역"
        )
    }

    static var historyTab: String {
        localized(
            en: "History",
            ja: "履歴",
            zhHans: "历史",
            zhHant: "記錄",
            ko: "기록"
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

    static var actionButtonTitle: String {
        localized(
            en: "Action Button shortcut",
            ja: "アクションボタンのショートカット",
            zhHans: "操作按钮快捷指令",
            zhHant: "動作按鈕捷徑",
            ko: "동작 버튼 단축어"
        )
    }

    static func actionButtonBody(supportsSmartCreation: Bool) -> String {
        if supportsSmartCreation {
            localized(
                en: "On iOS 27 or later, use Shortcuts Smart Creation: paste the prompt below and let Shortcuts build the screenshot translation Shortcut for you.",
                ja: "iOS 27以降では、ショートカットのSmart Creationを使います。下のプロンプトを貼り付けると、スクリーンショット翻訳のショートカットを自動で作成できます。",
                zhHans: "在 iOS 27 或更高版本中，使用快捷指令的 Smart Creation：粘贴下方提示，让快捷指令为你创建截图翻译快捷指令。",
                zhHant: "在 iOS 27 或以上版本中，使用捷徑的 Smart Creation：貼上下方提示，讓捷徑為你建立截圖翻譯捷徑。",
                ko: "iOS 27 이상에서는 단축어 Smart Creation을 사용하세요. 아래 프롬프트를 붙여 넣으면 스크린샷 번역 단축어를 만들어 줍니다."
            )
        } else {
            localized(
                en: "Create the Shortcut manually: add Take Screenshot, then Analyze Image with Yubi, and assign that Shortcut to the Action Button.",
                ja: "ショートカットを手動で作成します。「スクリーンショットを撮る」を追加し、次に「Yubiで画像を解析」を追加して、そのショートカットをアクションボタンに割り当てます。",
                zhHans: "手动创建快捷指令：添加“截屏”，然后添加“用 Yubi 分析图像”，并将该快捷指令分配给操作按钮。",
                zhHant: "手動建立捷徑：加入「截圖」，再加入「用 Yubi 分析影像」，並將該捷徑指定給動作按鈕。",
                ko: "단축어를 직접 만드세요. ‘스크린샷 찍기’를 추가한 다음 ‘Yubi로 이미지 분석’을 추가하고, 그 단축어를 동작 버튼에 지정하세요."
            )
        }
    }

    static var shortcutPrompt: String {
        localized(
            en: "Take Screenshot -> Analyze Image with Yubi",
            ja: "スクリーンショットを撮る -> Yubiで画像を解析",
            zhHans: "截屏 -> 用 Yubi 分析图像",
            zhHant: "截圖 -> 用 Yubi 分析影像",
            ko: "스크린샷 찍기 -> Yubi로 이미지 분석"
        )
    }

    static var copyShortcutPrompt: String {
        localized(
            en: "Copy Prompt",
            ja: "プロンプトをコピー",
            zhHans: "复制提示",
            zhHant: "複製提示",
            ko: "프롬프트 복사"
        )
    }

    static var copiedPrompt: String {
        localized(
            en: "Copied",
            ja: "コピー済み",
            zhHans: "已复制",
            zhHant: "已複製",
            ko: "복사됨"
        )
    }

    static var openShortcuts: String {
        localized(
            en: "Open Shortcuts",
            ja: "ショートカットを開く",
            zhHans: "打开快捷指令",
            zhHant: "打開捷徑",
            ko: "단축어 열기"
        )
    }

    static var actionButtonFooter: String {
        localized(
            en: "Pass the screenshot into Yubi's Image parameter. Yubi will extract text, summarize and translate it, then show the latest result here.",
            ja: "スクリーンショットをYubiの「画像」パラメータに渡します。Yubiがテキストを抽出し、要約して翻訳し、最新の結果をここに表示します。",
            zhHans: "将截图传入 Yubi 的“图像”参数。Yubi 会提取文本、总结并翻译，然后在此显示最新结果。",
            zhHant: "將截圖傳入 Yubi 的「影像」參數。Yubi 會擷取文字、摘要並翻譯，然後在此顯示最新結果。",
            ko: "스크린샷을 Yubi의 이미지 매개변수로 전달하세요. Yubi가 텍스트를 추출하고 요약 및 번역한 뒤 최신 결과를 여기에 표시합니다."
        )
    }

    static var analyzingShortcutText: String {
        localized(
            en: "Analyzing shortcut text...",
            ja: "ショートカットのテキストを解析中...",
            zhHans: "正在分析快捷指令文本...",
            zhHant: "正在分析捷徑文字...",
            ko: "단축어 텍스트 분석 중..."
        )
    }

    static var noShortcutText: String {
        localized(
            en: "Yubi opened, but there was no text in the URL or clipboard.",
            ja: "Yubiを開きましたが、URLまたはクリップボードにテキストがありませんでした。",
            zhHans: "Yubi 已打开，但 URL 或剪贴板中没有文本。",
            zhHant: "Yubi 已打開，但 URL 或剪貼簿中沒有文字。",
            ko: "Yubi가 열렸지만 URL 또는 클립보드에 텍스트가 없습니다."
        )
    }

    static var shortcutAnalysisComplete: String {
        localized(
            en: "Analysis complete.",
            ja: "解析が完了しました。",
            zhHans: "分析完成。",
            zhHant: "分析完成。",
            ko: "분석이 완료되었습니다."
        )
    }

    static var shortcutAnalysisFailed: String {
        localized(
            en: "Yubi could not analyze that text.",
            ja: "Yubiはそのテキストを解析できませんでした。",
            zhHans: "Yubi 无法分析该文本。",
            zhHant: "Yubi 無法分析該文字。",
            ko: "Yubi가 해당 텍스트를 분석할 수 없습니다."
        )
    }

    static func analysisFailedMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription

        return localized(
            en: "Analysis failed: \(message)",
            ja: "解析に失敗しました: \(message)",
            zhHans: "分析失败：\(message)",
            zhHant: "分析失敗：\(message)",
            ko: "분석 실패: \(message)"
        )
    }

    static var latestAnalysisTitle: String {
        localized(
            en: "Latest screenshot analysis",
            ja: "最新のスクリーンショット解析",
            zhHans: "最新截图分析",
            zhHant: "最新截圖分析",
            ko: "최근 스크린샷 분석"
        )
    }

    static var historyTitle: String {
        localized(
            en: "History",
            ja: "履歴",
            zhHans: "历史",
            zhHant: "記錄",
            ko: "기록"
        )
    }

    static var screenshotsPane: String {
        localized(
            en: "Screenshots",
            ja: "スクリーンショット",
            zhHans: "截图",
            zhHant: "截圖",
            ko: "스크린샷"
        )
    }

    static var textSelectionsPane: String {
        localized(
            en: "Text Selections",
            ja: "テキスト選択",
            zhHans: "文本选择",
            zhHant: "文字選取",
            ko: "텍스트 선택"
        )
    }

    static var textEditsPane: String {
        localized(
            en: "Text Edits",
            ja: "テキスト編集",
            zhHans: "文本编辑",
            zhHant: "文字編輯",
            ko: "텍스트 편집"
        )
    }

    static var noHistoryTitle: String {
        localized(
            en: "No screenshots yet",
            ja: "スクリーンショットはまだありません",
            zhHans: "还没有截图",
            zhHant: "尚無截圖",
            ko: "아직 스크린샷이 없습니다"
        )
    }

    static var noHistoryBody: String {
        localized(
            en: "Run the Action Button shortcut or analyze an image from Shortcuts to see results here.",
            ja: "アクションボタンのショートカットを実行するか、ショートカットから画像を解析すると、ここに結果が表示されます。",
            zhHans: "运行操作按钮快捷指令，或从快捷指令分析图像，即可在此查看结果。",
            zhHant: "執行動作按鈕捷徑，或從捷徑分析影像，即可在此查看結果。",
            ko: "동작 버튼 단축어를 실행하거나 단축어에서 이미지를 분석하면 여기에 결과가 표시됩니다."
        )
    }

    static var noTextEditHistoryTitle: String {
        localized(
            en: "No text edits yet",
            ja: "テキスト編集はまだありません",
            zhHans: "还没有文本编辑",
            zhHant: "尚無文字編輯",
            ko: "아직 텍스트 편집이 없습니다"
        )
    }

    static var noTextEditHistoryBody: String {
        localized(
            en: "Translate selected text with the Yubi keyboard to keep those translations here.",
            ja: "Yubiキーボードで選択したテキストを翻訳すると、その翻訳がここに保存されます。",
            zhHans: "使用 Yubi 键盘翻译选中的文本后，翻译会保存在这里。",
            zhHant: "使用 Yubi 鍵盤翻譯選取的文字後，翻譯會儲存在這裡。",
            ko: "Yubi 키보드로 선택한 텍스트를 번역하면 해당 번역이 여기에 저장됩니다."
        )
    }

    static var sourceTextLabel: String {
        localized(
            en: "Source",
            ja: "原文",
            zhHans: "原文",
            zhHant: "原文",
            ko: "원문"
        )
    }

    static var analysisRunningTitle: String {
        localized(
            en: "Analyzing",
            ja: "解析中",
            zhHans: "正在分析",
            zhHant: "正在分析",
            ko: "분석 중"
        )
    }

    static func analysisRunningBody(backendName: String, isImage: Bool) -> String {
        if isImage {
            return localized(
                en: "\(backendName) is analyzing the image...",
                ja: "\(backendName)が画像を解析しています...",
                zhHans: "\(backendName) 正在分析图像...",
                zhHant: "\(backendName) 正在分析影像...",
                ko: "\(backendName)이(가) 이미지를 분석 중입니다..."
            )
        }

        return localized(
            en: "\(backendName) is analyzing the text...",
            ja: "\(backendName)がテキストを解析しています...",
            zhHans: "\(backendName) 正在分析文本...",
            zhHant: "\(backendName) 正在分析文字...",
            ko: "\(backendName)이(가) 텍스트를 분석 중입니다..."
        )
    }

    static var analysisStoppedTitle: String {
        localized(
            en: "Analysis stopped",
            ja: "解析が停止しました",
            zhHans: "分析已停止",
            zhHant: "分析已停止",
            ko: "분석이 중단됨"
        )
    }

    static var analysisStoppedBody: String {
        localized(
            en: "This analysis did not finish. Check your API key and try again.",
            ja: "この解析は完了しませんでした。APIキーを確認して、もう一度お試しください。",
            zhHans: "此分析未完成。请检查 API 密钥后重试。",
            zhHant: "此分析未完成。請檢查 API 金鑰後再試一次。",
            ko: "이 분석이 완료되지 않았습니다. API 키를 확인한 후 다시 시도하세요."
        )
    }

    static var analysisContinuingInApp: String {
        localized(
            en: "Continuing analysis in Yubi.",
            ja: "Yubiで解析を続行しています。",
            zhHans: "正在 Yubi 中继续分析。",
            zhHant: "正在 Yubi 中繼續分析。",
            ko: "Yubi에서 분석을 계속합니다."
        )
    }

    static var detectedTextLabel: String {
        localized(
            en: "Detected text",
            ja: "検出したテキスト",
            zhHans: "检测到的文本",
            zhHant: "偵測到的文字",
            ko: "감지된 텍스트"
        )
    }

    static var todaySection: String {
        localized(
            en: "Today",
            ja: "今日",
            zhHans: "今天",
            zhHant: "今天",
            ko: "오늘"
        )
    }

    static var yesterdaySection: String {
        localized(
            en: "Yesterday",
            ja: "昨日",
            zhHans: "昨天",
            zhHant: "昨天",
            ko: "어제"
        )
    }

    static var screenshotLabel: String {
        localized(
            en: "Screenshot",
            ja: "スクリーンショット",
            zhHans: "截图",
            zhHant: "截圖",
            ko: "스크린샷"
        )
    }

    static var summaryLabel: String {
        localized(
            en: "Summary",
            ja: "要約",
            zhHans: "摘要",
            zhHant: "摘要",
            ko: "요약"
        )
    }

    static var translationLabel: String {
        localized(
            en: "Translation",
            ja: "翻訳",
            zhHans: "翻译",
            zhHant: "翻譯",
            ko: "번역"
        )
    }

    static var transcriptLabel: String {
        localized(
            en: "Transcript",
            ja: "文字起こし",
            zhHans: "转录",
            zhHant: "逐字稿",
            ko: "전사"
        )
    }

    static var waitingForTranscript: String {
        localized(
            en: "Reading screenshot...",
            ja: "スクリーンショットを読み取り中...",
            zhHans: "正在读取截图...",
            zhHant: "正在讀取截圖...",
            ko: "스크린샷 읽는 중..."
        )
    }

    static var waitingForTranslation: String {
        localized(
            en: "Analyzing transcript...",
            ja: "文字起こしを解析中...",
            zhHans: "正在分析转录...",
            zhHant: "正在分析逐字稿...",
            ko: "전사 분석 중..."
        )
    }

    static var noScreenshotLabel: String {
        localized(
            en: "No screenshot saved for this analysis.",
            ja: "この解析にはスクリーンショットが保存されていません。",
            zhHans: "此分析没有保存截图。",
            zhHant: "此分析沒有保存截圖。",
            ko: "이 분석에는 스크린샷이 저장되지 않았습니다."
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
            en: "Open Keyboards, enable Yubi Keyboard, and Allow Full Access.",
            ja: "「キーボード」を開き、Yubiキーボードを有効にして、フルアクセスを許可します。",
            zhHans: "打开“键盘”，启用 Yubi 键盘，并允许完全访问。",
            zhHant: "打開「鍵盤」，啟用 Yubi 鍵盤，並允許完整取用。",
            ko: "키보드를 열고 Yubi 키보드를 활성화한 다음 전체 접근을 허용하세요."
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
            en: "Apple runs privately on device when available. OpenAI and Claude send requests to the selected provider using your API key. Full Access lets the keyboard use that backend and save Text Edits history in Yubi.",
            ja: "Appleは利用可能な場合、デバイス上でプライベートに実行されます。OpenAIとClaudeは、あなたのAPIキーを使って選択したプロバイダにリクエストを送信します。フルアクセスを許可すると、キーボードがそのバックエンドを使用し、テキスト編集履歴をYubiに保存できます。",
            zhHans: "Apple 可用时会在设备端私密运行。OpenAI 和 Claude 会使用你的 API 密钥向所选提供商发送请求。完全访问权限可让键盘使用该后端并将文本编辑历史保存到 Yubi。",
            zhHant: "Apple 可用時會在裝置端私密執行。OpenAI 和 Claude 會使用你的 API 金鑰向所選提供商傳送要求。完整取用權限可讓鍵盤使用該後端並將文字編輯記錄儲存到 Yubi。",
            ko: "Apple은 가능한 경우 기기에서 비공개로 실행됩니다. OpenAI와 Claude는 사용자의 API 키로 선택한 제공업체에 요청을 보냅니다. 전체 접근 권한을 허용하면 키보드가 해당 백엔드를 사용하고 텍스트 편집 기록을 Yubi에 저장할 수 있습니다."
        )
    }

    static var githubRepoLink: String {
        localized(
            en: "Yubi is open source. See it on GitHub.",
            ja: "Yubiはオープンソースです。GitHubで見る。",
            zhHans: "Yubi 是开源的。在 GitHub 上查看。",
            zhHant: "Yubi 是開源的。在 GitHub 上查看。",
            ko: "Yubi는 오픈 소스입니다. GitHub에서 확인하세요."
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
        HStack(alignment: .center, spacing: 12) {
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

private struct FeatureRow: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AnalysisDayGroup: Identifiable {
    let date: Date
    let title: String
    let analyses: [ScreenshotAnalysis]

    var id: Date {
        date
    }
}

private struct TextEditDayGroup: Identifiable {
    let date: Date
    let title: String
    let items: [TextEditHistoryItem]

    var id: Date {
        date
    }
}

private struct AnalysisHistoryCard: View {
    let analysis: ScreenshotAnalysis

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !analysis.isComplete {
                ProgressView()
                    .padding(.top, 2)
            }

            Text(cardText)
                .font(.body)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48, alignment: .topLeading)
        }
        .padding(14)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var cardText: String {
        if !analysis.isComplete {
            return analysis.detectedText.isEmpty ? AppCopy.waitingForTranscript : analysis.detectedText
        }

        return analysis.summary
    }
}

private struct TextEditHistoryCard: View {
    let item: TextEditHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.targetLanguage)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let tone = item.tone {
                    Text(tone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(item.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.preview.isEmpty ? item.translatedText : item.preview)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(AppCopy.sourceTextLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text(item.sourceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AnalysisDetailView: View {
    let analysisID: UUID
    @State private var isShowingFullImage = false
    @State private var analysis: ScreenshotAnalysis?
    @State private var analysisStatus = ScreenshotAnalysisStatusStore.load()

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var screenshotImage: UIImage? {
        analysis.flatMap(ScreenshotAnalysisStore.imageData(for:)).flatMap(UIImage.init(data:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let analysis {
                    if !analysis.isComplete {
                        if analysisStatus.phase == .running && analysisStatus.analysisID == analysis.id {
                            analysisProgressView
                        } else {
                            analysisFailureView
                        }
                    }

                    screenshotSection

                    if !analysis.result.isEmpty {
                        detailSection(title: AppCopy.summaryLabel, text: analysis.summary)
                        markdownDetailSection(title: AppCopy.translationLabel, text: analysis.translation)
                    }
                } else {
                    ContentUnavailableView(
                        AppCopy.noHistoryTitle,
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(AppCopy.noHistoryBody)
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(analysis?.date.formatted(date: .abbreviated, time: .shortened) ?? AppCopy.historyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshAnalysis)
        .onReceive(refreshTimer) { _ in
            refreshAnalysis()
        }
        .sheet(isPresented: $isShowingFullImage) {
            if let screenshotImage {
                FullScreenshotView(image: screenshotImage)
            }
        }
    }

    private var analysisProgressView: some View {
        HStack(spacing: 12) {
            ProgressView()

            VStack(alignment: .leading, spacing: 2) {
                Text(AppCopy.analysisRunningTitle)
                    .font(.headline)

                Text(analysisStatus.message ?? AppCopy.analysisRunningBody(
                    backendName: AIBackendSettings.selectedBackend.displayName,
                    isImage: analysis?.imageFilename != nil
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var analysisFailureView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppCopy.analysisStoppedTitle)
                    .font(.headline)

                Text(analysisFailureMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var analysisFailureMessage: String {
        guard analysisStatus.phase == .failed,
              analysisStatus.analysisID == analysisID
        else {
            return AppCopy.analysisStoppedBody
        }

        return analysisStatus.message ?? AppCopy.analysisStoppedBody
    }

    @ViewBuilder
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let screenshotImage {
                Button {
                    isShowingFullImage = true
                } label: {
                    Image(uiImage: screenshotImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            } else {
                Text(AppCopy.noScreenshotLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())

            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func markdownDetailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())

            Text(markdownAttributedString(from: text))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func markdownAttributedString(from text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func refreshAnalysis() {
        analysis = ScreenshotAnalysisStore.loadHistory().first { $0.id == analysisID }
        analysisStatus = ScreenshotAnalysisStatusStore.load()
    }
}

private struct FullScreenshotView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableImageView(image: image)
            .background(Color.black.opacity(0.95))
            .navigationTitle(AppCopy.screenshotLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

#Preview {
    ContentView()
}
