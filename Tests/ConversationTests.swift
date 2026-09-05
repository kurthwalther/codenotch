import XCTest
@testable import Codenotch

/// The conversation card's plumbing: which road a reply takes, which agent
/// super.engineering is told to send to, and what the card reads.
@MainActor
final class ConversationTests: XCTestCase {
    private func session(locator: SessionLocator?) -> AgentSession {
        AgentSession(id: "claude.1", name: "s", detail: "Terminal · p", state: .idle,
                     waitingFor: nil, since: Date(), locator: locator)
    }

    func testTheRoadFollowsTheHost() {
        let sc = SessionFocusTests.Fake(tree: [1: (2, "/dev/ttys001", nil), 2: (1, nil, SessionFocus.superconductorID)])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: sc),
                       .superconductor(cwd: "/p"))
        let term = SessionFocusTests.Fake(tree: [1: (2, "/dev/ttys001", nil), 2: (1, nil, "com.apple.Terminal")])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: term),
                       .terminal(bundleID: "com.apple.Terminal", tty: "/dev/ttys001"))
        let code = SessionFocusTests.Fake(tree: [1: (2, nil, nil), 2: (1, nil, "com.microsoft.VSCode")])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: code), .clipboard)
        XCTAssertEqual(SessionReply.route(for: SessionLocator(), processes: SessionFocusTests.Fake()), .clipboard)
    }

    /// One Claude agent that can take a send: that one. Two, or none: no
    /// guessing.
    func testTheOneClaudeAgentIsTheTarget() {
        func listing(_ agents: [[String: Any]]) -> Data {
            try! JSONSerialization.data(withJSONObject: ["kind": "agents", "response": ["agents": agents]])
        }
        let claude: [String: Any] = ["stable_target_id": "terminal:abc", "provider_key": "claude",
                                     "capabilities": ["send": true]]
        let codex: [String: Any] = ["stable_target_id": "terminal:def", "provider_key": "codex",
                                    "capabilities": ["send": true]]
        let mute: [String: Any] = ["stable_target_id": "terminal:ghi", "provider_key": "claude",
                                   "capabilities": ["send": false]]
        XCTAssertEqual(SessionReply.pickTarget(fromAgentsJSON: listing([claude, codex, mute])), "terminal:abc")
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: listing([claude, claude])), "two: ambiguous")
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: listing([codex])))
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: Data("nonsense".utf8)))
    }

    func testTypedTextIsEscapedForAppleScript() {
        let script = SessionReply.typeIntoTerminalScript(
            bundleID: "com.apple.Terminal", tty: "/dev/ttys002", text: #"say "hi" \ bye"#)
        XCTAssertTrue(script.contains(#"do script "say \"hi\" \\ bye" in t"#))
        let iterm = SessionReply.typeIntoTerminalScript(bundleID: "com.googlecode.iterm2", tty: "/dev/ttys002", text: "x")
        XCTAssertTrue(iterm.contains(#"tell s to write text "x""#))
    }

    func testTheCardReadsAndRefreshes() {
        let conversation = Conversation(session: session(locator: SessionLocator(transcriptID: "t")))
        var turns = [TranscriptTurn(role: .user, text: "hi", at: nil)]
        conversation.reader = { _ in turns }
        conversation.load()
        XCTAssertEqual(conversation.turns.count, 1)
        turns.append(TranscriptTurn(role: .assistant, text: "hello", at: nil))
        conversation.load()
        XCTAssertEqual(conversation.turns.map(\.role), [.user, .assistant])
        XCTAssertFalse(conversation.isEmpty)
    }

    func testASessionWithoutATranscriptReadsNothing() {
        let conversation = Conversation(session: session(locator: nil))
        conversation.load()
        XCTAssertTrue(conversation.isEmpty)
    }

    func testAnEmptyDraftIsNotSent() async {
        let state = await SessionReply.send("   ", to: session(locator: SessionLocator(cwd: "/p")))
        XCTAssertEqual(state, .idle)
    }
}

/// What the tool's refusals are turned into.
final class ReplyErrorTests: XCTestCase {
    func testAFeatureSwitchedOffIsSaidPlainly() {
        let output = Data(#"{"kind":"cli_error","error":{"code":"feature_disabled","message":"agent orchestration is disabled in super.engineering settings; …"}}"#.utf8)
        XCTAssertEqual(SessionReply.explain(output),
                       "Turn on Agent orchestration in super.engineering: Settings › Experimental.")
    }

    func testOtherRefusalsKeepTheirOwnWords() {
        let output = Data(#"{"kind":"cli_error","error":{"code":"target_busy","message":"the agent is mid-turn"}}"#.utf8)
        XCTAssertEqual(SessionReply.explain(output), "the agent is mid-turn")
        XCTAssertNil(SessionReply.explain(Data(#"{"kind":"agents"}"#.utf8)))
        XCTAssertNil(SessionReply.explain(Data("not json".utf8)))
    }
}

/// The visibility that decides by itself, and the rest that waits as long as
/// you say.
@MainActor
final class AutoVisibilityTests: XCTestCase {
    func testAutoIsOfferedBetweenAlwaysAndHover() {
        XCTAssertEqual(NotchVisibility.allCases, [.alwaysShow, .auto, .onHover, .hidden])
        XCTAssertEqual(NotchVisibility.auto.title, "Auto")
        XCTAssertEqual(NotchVisibility(rawValue: "auto"), .auto)
    }

    func testTheRestDelayIsRememberedAndBounded() {
        let name = "rest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.restAfterSeconds, 10, accuracy: 0.001)
        first.restAfterSeconds = 25
        XCTAssertEqual(Preferences(defaults: defaults).restAfterSeconds, 25, accuracy: 0.001)
        defaults.set(999, forKey: "restAfterSeconds")
        XCTAssertEqual(Preferences(defaults: defaults).restAfterSeconds, 60, accuracy: 0.001)
    }
}

/// What Auto counts, and what a waiting card can answer.
@MainActor
final class AutoScopeTests: XCTestCase {
    private func session(_ state: AgentSession.State) -> AgentSession {
        AgentSession(id: UUID().uuidString, name: "s", detail: "d", state: state, waitingFor: nil, since: Date())
    }

    func testBySessionAnySessionOpensTheNotch() {
        XCTAssertTrue(NotchVisibility.AutoScope.session.opens(["claude": [session(.idle)]]))
        XCTAssertTrue(NotchVisibility.AutoScope.session.opens(["claude": [session(.waiting)]]))
        XCTAssertFalse(NotchVisibility.AutoScope.session.opens(["claude": []]))
        XCTAssertFalse(NotchVisibility.AutoScope.session.opens([:]))
    }

    func testByWorkOnlyABusyAgentOpensTheNotch() {
        XCTAssertFalse(NotchVisibility.AutoScope.working.opens(["claude": [session(.idle), session(.waiting)]]))
        XCTAssertTrue(NotchVisibility.AutoScope.working.opens(["claude": [session(.idle)], "codex": [session(.busy)]]))
    }

    func testTheScopeIsRemembered() {
        let name = "auto-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.autoScope, .session)
        first.autoScope = .working
        XCTAssertEqual(Preferences(defaults: defaults).autoScope, .working)
    }

    /// A quick answer needs a road that can press a key; a session with no
    /// locator, or one only reachable by clipboard, gets no buttons.
    func testOnlyReachableSessionsGetQuickAnswers() {
        XCTAssertFalse(SessionReply.canAnswerQuickly(session(.waiting)))
        var reachable = session(.waiting)
        reachable.locator = SessionLocator(appBundleID: "com.example.editor")
        XCTAssertFalse(SessionReply.canAnswerQuickly(reachable))
    }

    func testTheConversationStartsInTheSessionsState() {
        let conversation = Conversation(session: session(.busy))
        XCTAssertEqual(conversation.state, .busy)
        conversation.state = .idle
        XCTAssertEqual(conversation.state, .idle)
    }
}

/// The closing touches: rows in the notch's order, a line that carries its
/// files, and a rest that can be immediate.
@MainActor
final class NotchOrderTests: XCTestCase {
    private func window(_ id: String) -> LimitWindow {
        LimitWindow(id: id, label: id, usedFraction: 0.3)
    }

    func testTheCardListsTheBarThenTheRingThenTheRest() {
        let s = ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                                 fidelity: .official, status: .ok,
                                 windows: [window("session"), window("weekly_all"), window("weekly_scoped")],
                                 headlineID: "session")
        XCTAssertEqual(s.orderedWindows.map(\.id), ["session", "weekly_all", "weekly_scoped"],
                       "nothing chosen: the ring's window leads, the rest follow in order")
        let chosen = s.choosingHeadline("weekly_scoped").choosingSecondary("session")
        XCTAssertEqual(chosen.orderedWindows.map(\.id), ["session", "weekly_scoped", "weekly_all"],
                       "the bar's window on top, then the ring's, then the one not on the notch")
        XCTAssertEqual(chosen.windows.map(\.id), ["session", "weekly_all", "weekly_scoped"],
                       "the reading itself keeps the provider's order")
    }

    func testTheLineCarriesItsFilesByPath() {
        let a = URL(fileURLWithPath: "/tmp/one.png"), b = URL(fileURLWithPath: "/tmp/two.md")
        XCTAssertEqual(Attachments.compose("look at these", with: [a, b]), "look at these\n\n/tmp/one.png\n/tmp/two.md")
        XCTAssertEqual(Attachments.compose("  ", with: [a]), "/tmp/one.png", "files alone are a line too")
        XCTAssertEqual(Attachments.compose("just words", with: []), "just words")
        XCTAssertTrue(Attachments.isImage(a))
        XCTAssertFalse(Attachments.isImage(b))
    }

    func testAPastedImageBecomesAFile() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let url = try XCTUnwrap(Attachments.save(image, now: Date(timeIntervalSince1970: 1_700_000_000)))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("pasted-"))
    }

    func testTheRestCanBeImmediate() {
        XCTAssertEqual(Preferences.restAfterRange.lowerBound, 0)
        let name = "rest0-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let prefs = Preferences(defaults: defaults)
        prefs.restAfterSeconds = 0
        XCTAssertEqual(Preferences(defaults: defaults).restAfterSeconds, 0, accuracy: 0.001)
    }

    func testACancelledWaitIsNotAFailure() async {
        let dispatch = SessionReply.Dispatch()
        dispatch.cancel()
        XCTAssertTrue(dispatch.cancelled)
    }
}

/// The captions under the numbers.
final class CaptionTests: XCTestCase {
    func testShortNamesForTheCaptions() {
        XCTAssertEqual(LimitWindow(id: "s", label: "Current session", usedFraction: 0.1).shortLabel, "Session")
        XCTAssertEqual(LimitWindow(id: "a", label: "All models", usedFraction: 0.1).shortLabel, "All")
        XCTAssertEqual(LimitWindow(id: "f", label: "Fable", usedFraction: 0.1).shortLabel, "Fable")
        XCTAssertEqual(LimitWindow(id: "i", label: "Included usage", usedFraction: 0.1).shortLabel, "Included")
    }

    func testTheShortResetIsJustTheTimeWhenItIsToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 10:00 on a Monday.
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10))!
        let later = ResetCopy.short(for: now.addingTimeInterval(6 * 3600), now: now, calendar: calendar)
        XCTAssertNotNil(later.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression),
                        "today: the time alone, got \(later)")
        XCTAssertFalse(later.contains("Mon"))
        let tomorrow = ResetCopy.short(for: now.addingTimeInterval(20 * 3600), now: now, calendar: calendar)
        XCTAssertTrue(tomorrow.contains("Tue"), "another day carries its weekday, got \(tomorrow)")
        XCTAssertFalse(tomorrow.hasPrefix("Resets"))
        XCTAssertEqual(ResetCopy.short(for: now.addingTimeInterval(-5), now: now, calendar: calendar), "now")
    }

    func testEveryCellCarriesTheTwoCaptionLines() {
        XCTAssertEqual(NotchLayout.captionSpace,
                       NotchLayout.ringCaptionGap + NotchLayout.captionLineHeight + NotchLayout.nameToPercentGap
                           + NotchLayout.captionGap + NotchLayout.captionLineHeight - NotchLayout.ringLabelGap,
                       accuracy: 0.001)
        XCTAssertEqual(NotchLayout.cellExtent,
                       NotchLayout.secondaryBarSpace + NotchLayout.ringDiameter + NotchLayout.ringLabelGap
                           + NotchLayout.percentLineHeight + NotchLayout.captionSpace, accuracy: 0.001)
    }
}

/// The shadow lies flat until the pointer arrives.
@MainActor
final class ShadowTests: XCTestCase {
    func testTheShadowNeedsBothTheSettingAndThePointer() {
        let m = NotchViewModel()
        XCTAssertFalse(m.castsShadow)
        m.showsShadow = true
        XCTAssertFalse(m.castsShadow, "on, but nobody there")
        m.isPointerOn = true
        XCTAssertTrue(m.castsShadow)
        m.showsShadow = false
        XCTAssertFalse(m.castsShadow)
    }

    func testTheSliderReachesElevenTenths() {
        XCTAssertEqual(Preferences.notchScaleRange.upperBound, 1.1, accuracy: 0.0001)
    }
}
