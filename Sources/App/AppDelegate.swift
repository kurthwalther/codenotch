import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var store: UsageStore?
    private var monitors: [String: any AgentActivityMonitor] = [:]
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    /// Held for the life of the app: it owns the power assertion.
    private var keepAwake: KeepAwake?
    /// The notes beside the notch when an agent finishes or needs you.
    private var noticeCenter: SessionNoticeCenter?
    private var notices: NoticeWindowController?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set here, not in the Info.plist: this call is applied at launch and
        // overrides `LSUIElement` either way. Removing the plist key alone left
        // the app registered as a UIElement with no Dock tile, which looked
        // exactly like the icon having failed to install. The user's choice
        // replaces this a moment later, once preferences exist.
        NSApp.setActivationPolicy(.regular)
        guard !isRunningTests else { return }

        let controller = NotchWindowController()

        // `CODENOTCH_DEMO=1` puts the design frame's three providers on screen
        // with its numbers, for screenshots and for eyeballing the layout.
        if ProcessInfo.processInfo.environment["CODENOTCH_DEMO"] == "1" {
            controller.model.snapshots = Fixtures.snapshots()
        } else {
            // Nothing needs a browser session at the moment. `WebSessionProvider`
            // and `Sites.perplexity` are kept: they are the working pattern for a
            // site behind bot management, and re-registering is one line.
            let webProviders: [WebSessionProvider] = []
            controller.signInItems = webProviders.map { provider in
                (title: "Sign in to \(provider.displayName)…",
                 action: { [weak provider] in provider?.presentSignIn() })
            }
            // Before Preferences reads anything, or the first launch flag and
            // every choice would be read from an empty domain.
            Preferences.migrateFromPreviousName()
            let preferences = Preferences()
            self.preferences = preferences

            // Cursor reads the editor's own session rather than a browser one:
            // signing into cursor.com separately created a second, empty account.
            //
            // Built *after* preferences and told what is switched off, so the
            // very first list it draws already excludes them. Constructed first,
            // it drew every provider from the archive and only dropped the
            // switched-off ones once the binding below delivered.
            let store = UsageStore(
                providers: [ClaudeOAuthProvider(), CursorLocalProvider(),
                            CodexLocalProvider(), AntigravityProvider()]
                    + webProviders,
                disconnected: preferences.disconnectedProviders
            )

            // The stored edge goes in before the panel is ever put up. The
            // sink below delivers on the next run loop turn, by which time the
            // notch has already been shown on the default edge — so without
            // this, every launch on any other edge opens with a flash of the
            // right-hand one and then crossfades away from it.
            controller.model.edge = preferences.notchEdge

            let updater = Updater()
            self.updater = updater

            let settings = SettingsWindowController(
                preferences: preferences,
                // A closure so the sheet re-reads accounts each time it comes
                // forward; a snapshot here is what made a switched account keep
                // showing the old address until the app restarted.
                providers: { [weak store] in store?.providerSummaries ?? [] },
                updater: updater,
                signOut: { [weak store] in store?.signOut(providerID: $0) },
                signIn: { [weak store] in store?.signIn(providerID: $0) ?? false },
                switchAccount: { [weak store] in
                    store?.openAccountSource(providerID: $0) ?? false
                },
                retry: { [weak store] in store?.reauthorize(providerID: $0) }
            )
            controller.onOpenSettings = { [weak settings] in settings?.show() }
            self.settings = settings

            // What changed, once per version — including on a fresh install,
            // where it is the introduction.
            let whatsNew = WhatsNewWindowController(
                preferences: preferences, version: updater.currentVersion
            )
            self.whatsNew = whatsNew

            // An agent app has no dock icon and no window: installed and
            // launched, it shows four empty rings on a screen edge and no
            // reason to look at them. Once, on the very first run, it opens the
            // one place that explains what to connect.
            //
            // Sequenced behind What's New rather than beside it: two windows
            // arriving together is one to dismiss before you can read either.
            let introduce = { [weak settings] in
                guard preferences.isFirstLaunch else { return }
                settings?.show()
            }
            whatsNew.onDismiss = introduce
            if !whatsNew.showIfNeeded() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: introduce)
            }

            let statusItem = StatusItemController { [weak settings] in settings?.show() }
            self.statusItem = statusItem

            preferences.$appPresence
                .receive(on: RunLoop.main)
                .sink { presence in
                    NSApp.setActivationPolicy(presence.activationPolicy)
                    if presence.wantsStatusItem { statusItem.show() } else { statusItem.hide() }
                }
                .store(in: &cancellables)

            preferences.$notchVisibility
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.apply($0) }
                .store(in: &cancellables)

            preferences.$notchEdge
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.apply(edge: $0) }
                .store(in: &cancellables)

            preferences.$disconnectedProviders
                .receive(on: RunLoop.main)
                .sink { [weak store] in store?.disconnected = $0 }
                .store(in: &cancellables)

            // The store reports what each provider puts on its ring; the user's
            // choices are laid over it here, so a change in Settings or the
            // menu re-points the ring without a fetch.
            store.$snapshots
                .combineLatest(preferences.$ringWindows, preferences.$secondaryWindows,
                               preferences.$cellLabels.combineLatest(preferences.$providerIcons))
                .receive(on: RunLoop.main)
                .sink { [weak controller] snapshots, rings, seconds, looks in
                    let (labels, icons) = looks
                    let chosen = snapshots.map {
                        $0.choosingHeadline(rings[$0.id])
                            .choosingSecondary(seconds[$0.id])
                            .choosingLabel(labels[$0.id].flatMap(CellLabel.init(rawValue:)))
                            .choosingIcon(icons[$0.id])
                    }
                    // Room for the bar is made before the cells are handed
                    // the readings, so both arrive in one layout.
                    controller?.apply(reservesSecondaryBar: chosen.contains { $0.secondary != nil })
                    withAnimation(NotchMotion.unfold) {
                        controller?.model.snapshots = chosen
                    }
                    controller?.model.now = Date()
                }
                .store(in: &cancellables)
            controller.onChooseRingWindow = { providerID, windowID in
                preferences.setRingWindow(windowID, for: providerID)
            }
            controller.onChooseSecondaryWindow = { providerID, windowID in
                preferences.setSecondaryWindow(windowID, for: providerID)
            }
            controller.onChooseLabel = { providerID, label in
                preferences.setCellLabel(label, for: providerID)
            }
            preferences.$thresholds
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.model.thresholds = $0 }
                .store(in: &cancellables)

            // Measurements behind the layout. Applied synchronously, on the
            // thread the settings change on, so the first layout already has
            // them — and a slider drag redraws as it goes.
            preferences.$notchScale
                .removeDuplicates()
                .sink { [weak controller] in controller?.apply(scale: $0) }
                .store(in: &cancellables)
            store.start()
            controller.onRefresh = { [weak store] in store?.refreshNow() }
            controller.onRefreshProvider = { [weak store] id in store?.refresh(providerID: id) }
            // Two minutes: older than that and the number is from before the
            // last thing the agent did.
            controller.onHoverProvider = { [weak store] id in
                store?.refreshIfStale(providerID: id, olderThan: 2 * 60)
            }
            controller.onFocusSession = { SessionFocus.focus($0) }

            // A note beside the notch when an agent finishes or stops to
            // wait: its name and the start of what it last said. Its own
            // panel, so it shows whether the notch is open, folded or hidden.
            let noticeCenter = SessionNoticeCenter()
            let notices = NoticeWindowController(center: noticeCenter)
            notices.anchor = { [weak controller] in
                (controller?.currentScreen ?? NSScreen.main,
                 controller?.model.edge ?? .right,
                 controller?.noticeInset ?? 0)
            }
            // The glyph at the end of a session's row on the notch's card
            // opens the same conversation the notice would.
            controller.onOpenConversation = { [weak notices] session in
                notices?.show(conversation: Conversation(session: session))
            }
            // Reading or typing beside the notch is attention it counts as
            // its own: it does not settle while you are there.
            controller.attentionElsewhere = { [weak notices] in notices?.isEngaged ?? false }
            self.noticeCenter = noticeCenter
            self.notices = notices
            controller.model.$sessions
                .receive(on: RunLoop.main)
                .sink { [weak noticeCenter, weak notices] sessions in
                    noticeCenter?.observe(sessions)
                    // The open conversation follows its session's state, so
                    // the card can say the agent is at it.
                    if let conversation = notices?.conversation,
                       let live = sessions.values.flatMap({ $0 }).first(where: { $0.id == conversation.session.id }) {
                        conversation.state = live.state
                    }
                }
                .store(in: &cancellables)
            preferences.$noticesEnabled
                .sink { [weak noticeCenter] in noticeCenter?.enabled = $0 }
                .store(in: &cancellables)
            preferences.$noticeSeconds
                .sink { [weak notices] in notices?.lifetime = $0 }
                .store(in: &cancellables)
            controller.rememberedPin = preferences.notchPinned
            controller.onPinChanged = { preferences.notchPinned = $0 }
            preferences.$restAfterSeconds
                .sink { [weak controller] in controller?.restAfter = $0 }
                .store(in: &cancellables)
            preferences.$autoScope
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.autoScope = $0 }
                .store(in: &cancellables)
            preferences.$notchShadow
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.model.showsShadow = $0 }
                .store(in: &cancellables)
            preferences.$hideInFullscreen
                .removeDuplicates()
                .sink { [weak controller] in controller?.apply(hidesInFullscreen: $0) }
                .store(in: &cancellables)
            store.$refreshing
                .receive(on: RunLoop.main)
                .sink { [weak controller] ids in controller?.model.refreshing = ids }
                .store(in: &cancellables)

            // Caffeine, but only while something is actually running: the
            // moment the last busy session goes idle, the Mac may sleep again.
            // Fed from the same sessions the rings show, so what the notch says
            // is working and what holds the Mac awake can never disagree.
            let keepAwake = KeepAwake()
            self.keepAwake = keepAwake
            Publishers.CombineLatest3(
                preferences.$keepAwakeMode,
                preferences.$keepDisplayAwake,
                controller.model.$sessions
            )
            .map { KeepAwake.wanted(mode: $0, display: $1, sessions: $2) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { keepAwake.hold($0) }
            .store(in: &cancellables)

            // The handle above the notch: the same setting Settings has, in
            // reach without opening anything, stepped round a position per
            // click, and a cup that says which position it is in.
            controller.onToggleKeepAwake = { preferences.keepAwakeMode = preferences.keepAwakeMode.next }
            preferences.$keepAwakeMode
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.model.keepAwakeMode = $0 }
                .store(in: &cancellables)
            keepAwake.$held
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.model.isHoldingAwake = $0 != nil }
                .store(in: &cancellables)

            // CODENOTCH_DISCOVER=<url> loads that page in the signed-in WebView
            // and logs the API calls it makes — for finding an undocumented
            // endpoint by watching the site rather than guessing at path names.
            if let target = ProcessInfo.processInfo.environment["CODENOTCH_DISCOVER"],
               let url = URL(string: target),
               let provider = webProviders.first(where: { url.host?.contains($0.id) == true })
                   ?? webProviders.first {
                Task {
                    let calls = await provider.recordCalls(on: url)
                    Log.usage.notice("discovered: \(calls.joined(separator: "  "), privacy: .public)")
                }
            }
            self.store = store
        }

        // What each agent is doing right now, so the notch can say whether it is
        // still working without you switching to it.
        let monitors: [String: any AgentActivityMonitor] = [
            "claude": ClaudeSessionMonitor(),
            "cursor": CursorActivityMonitor(),
            "codex": CodexActivityMonitor(),
            "gemini": AntigravityActivityMonitor()
        ]
        for (id, monitor) in monitors {
            monitor.sessionsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak controller] live in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        controller?.model.sessions[id] = live
                    }
                    controller?.model.now = Date()
                }
                .store(in: &cancellables)
            monitor.start()
        }
        // Poll usage hard only while something is actually running.
        store?.isBusy = { monitors.values.contains { m in m.sessions.contains { $0.state == .busy } } }
        self.monitors = monitors

        controller.show()
        notchController = controller
    }

    /// Closing the settings window must not take the app with it.
    ///
    /// The default for a Dock app is to quit once its last window closes, which
    /// here would kill the notch — the part that is actually the product —
    /// every time someone shut the settings they had just opened.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The way back in when the notch is hidden.
    ///
    /// With no dock icon, no menu bar item and no notch on screen, there is
    /// otherwise nothing left to click — choosing Hide would be a one-way door.
    /// Launching the app again while it is already running lands here, so
    /// opening it from Applications or Spotlight reopens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        settings?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        monitors.values.forEach { $0.stop() }
        notchController?.stop()
    }
}
