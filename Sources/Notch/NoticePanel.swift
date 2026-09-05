import AppKit
import Combine
import SwiftUI

/// A small card beside the notch with an agent's last words. Its own panel,
/// so it can appear whether the notch is open, folded or hidden — and, in a
/// later round, become the place to read the whole conversation and reply.
final class NoticePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Dragged by any part of the card that does not take the click
        // itself — the header, the padding — while a conversation is open.
        isMovable = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    /// Key only while there is something to type into: a conversation's
    /// reply line. Non-activating, so becoming key never brings the app
    /// forward or takes focus from what was being worked on.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// The hosting view, which takes the first click: on a window that is not
/// key, the first click would otherwise only be an attempt to make it so.
final class NoticeHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Either the notices or, once one is opened, the conversation behind it.
struct NoticeRootView: View {
    @ObservedObject var controller: NoticeWindowController
    @ObservedObject var center: SessionNoticeCenter

    var body: some View {
        Group {
            if let conversation = controller.conversation {
                ConversationView(
                    conversation: conversation,
                    close: { controller.closeConversation() },
                    open: { SessionFocus.focus(conversation.session) },
                    send: { controller.send() },
                    cancel: { controller.cancelSend() }
                )
                .padding(Design.px(16))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                NoticeStackView(center: center, edge: controller.edge,
                                open: { controller.open($0) },
                                answer: { controller.answer($0, with: $1) })
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: controller.conversation?.session.id)
    }
}

/// One notice as drawn.
struct NoticeCardView: View {
    let notice: SessionNotice
    let open: () -> Void
    /// For a session waiting on you: the two answers a card can give
    /// without opening the conversation. Nil where there is no road.
    var answer: ((SessionAnswer) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Design.px(8)) {
            HStack(spacing: NotchLayout.statusDotGap) {
                Circle()
                    .fill(notice.kind == .waiting ? Palette.watch : Palette.ample)
                    .frame(width: NotchLayout.statusDot * 0.6, height: NotchLayout.statusDot * 0.6)
                Text(notice.title)
                    .font(Typography.cardBody.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(notice.session.detail)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(notice.preview)
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if notice.kind == .waiting, let answer {
                HStack(spacing: Design.px(12)) {
                    quick("Approve", .approve, answer)
                    quick("Deny", .deny, answer)
                    Spacer(minLength: 0)
                }
                .padding(.top, Design.px(4))
            }
        }
        .padding(NotchLayout.cardPadding * 0.8)
        .frame(width: NoticeWindowController.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner * 0.7, style: .continuous)
                .fill(Palette.card)
        )
        .contentShape(RoundedRectangle(cornerRadius: NotchLayout.cardCorner * 0.7, style: .continuous))
        .onTapGesture(perform: open)
    }

    private func quick(_ title: String, _ kind: SessionAnswer,
                       _ answer: @escaping (SessionAnswer) -> Void) -> some View {
        Button { answer(kind) } label: {
            Text(title)
                .font(Typography.cardBody.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Design.px(18))
                .padding(.vertical, Design.px(7))
                .background(Capsule().fill(kind == .approve ? Palette.ample.opacity(0.28) : Palette.ringTrack))
        }
        .buttonStyle(.plain)
    }
}

/// The two things a waiting agent is usually waiting for.
enum SessionAnswer {
    case approve
    case deny
}

/// The notices, newest at the bottom, each arriving from the bezel's side.
struct NoticeStackView: View {
    @ObservedObject var center: SessionNoticeCenter
    let edge: NotchEdge
    let open: (SessionNotice) -> Void
    var answer: ((SessionNotice, SessionAnswer) -> Void)? = nil

    var body: some View {
        VStack(spacing: Design.px(12)) {
            ForEach(center.notices) { notice in
                NoticeCardView(notice: notice, open: { open(notice) },
                               answer: SessionReply.canAnswerQuickly(notice.session)
                                   ? { answer?(notice, $0) } : nil)
                    .transition(
                        .move(edge: arrivesFrom)
                            .combined(with: .opacity)
                    )
            }
        }
        .padding(Design.px(16))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: center.notices)
    }

    /// The side the notch is on, so a card slides out from it.
    private var arrivesFrom: Edge {
        switch edge {
        case .right:  return .trailing
        case .left:   return .leading
        case .top:    return .top
        case .bottom: return .bottom
        }
    }
}

/// Puts the notices on screen beside the notch and takes them down again —
/// and, when one is opened, the conversation behind it, with a line to reply.
@MainActor
final class NoticeWindowController: ObservableObject {
    static let width = Design.px(560)

    let center: SessionNoticeCenter
    /// How long a notice stays, unless the pointer is on the card.
    var lifetime: TimeInterval = 12
    /// And how long an open conversation stays after the pointer has left it.
    static let conversationLingers: TimeInterval = 60
    /// Where the cards go: the screen and how far in from the bezel, asked
    /// each time because the notch may have opened or folded meanwhile.
    var anchor: () -> (screen: NSScreen?, edge: NotchEdge, inset: CGFloat) = { (NSScreen.main, .right, 0) }

    /// The conversation on show, if one is.
    @Published private(set) var conversation: Conversation?

    /// The pointer is on the cards, or a conversation is open and being
    /// typed into — attention the notch should count as its own, so it does
    /// not settle into rest while you are reading beside it.
    var isEngaged: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation) || (conversation != nil && panel.isKeyWindow)
    }
    private(set) var edge: NotchEdge = .right

    private var panel: NoticePanel?
    private var hosting: NoticeHostingView<NoticeRootView>?
    private var cancellables = Set<AnyCancellable>()
    private var conversationWatch: AnyCancellable?
    private var tick: Timer?
    private var pointerLeftAt: Date?
    /// Where the card was dragged to, if it was: kept for as long as the
    /// conversation is open, so a turn arriving does not snap it back.
    private var draggedTopLeft: CGPoint?
    private var placing = false

    init(center: SessionNoticeCenter) {
        self.center = center
        center.$notices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.present() }
            }
            .store(in: &cancellables)
    }

    /// A click on a notice opens its conversation in place of the notices.
    func open(_ notice: SessionNotice) {
        center.dismiss(notice.id)
        show(conversation: Conversation(session: notice.session))
    }

    /// The conversation for a session, asked for from the notch's card.
    func show(conversation: Conversation) {
        self.conversation?.stopFollowing()
        self.conversation = conversation
        conversation.startFollowing()
        // Re-place the panel as turns arrive and the draft grows.
        conversationWatch = conversation.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.present() } }
            }
        pointerLeftAt = nil
        draggedTopLeft = nil
        present()
        panel?.allowsKey = true
        panel?.makeKey()
    }

    func closeConversation() {
        conversation?.stopFollowing()
        conversationWatch = nil
        conversation = nil
        draggedTopLeft = nil
        if let panel {
            if panel.isKeyWindow { panel.resignKey() }
            panel.allowsKey = false
        }
        present()
    }

    /// A quick answer from a "needs you" card: approve or deny, by the same
    /// road a reply takes. The card goes once the answer is on its way.
    func answer(_ notice: SessionNotice, with answer: SessionAnswer) {
        center.dismiss(notice.id)
        Task { @MainActor in
            _ = await SessionReply.answer(answer, to: notice.session)
        }
    }

    /// Sends the draft — and what goes with it — and, when it went, clears
    /// both; the transcript will show it as a turn a moment later. An agent
    /// mid-turn is waited for, and the card says so meanwhile.
    func send() {
        guard let conversation, conversation.dispatch == nil else { return }
        let text = Attachments.compose(conversation.draft, with: conversation.attachments)
        guard !text.isEmpty else { return }
        let dispatch = SessionReply.Dispatch()
        conversation.dispatch = dispatch
        if conversation.state == .busy { conversation.sendState = .waiting }
        Task { @MainActor in
            let state = await SessionReply.send(text, to: conversation.session, dispatch: dispatch)
            conversation.dispatch = nil
            conversation.sendState = state
            switch state {
            case .sent, .copied:
                conversation.draft = ""
                conversation.attachments = []
            default:
                break
            }
        }
    }

    /// Calls off a send that is waiting for the agent; the draft stays.
    func cancelSend() {
        conversation?.dispatch?.cancel()
    }

    private func present() {
        let showing = conversation != nil || !center.notices.isEmpty
        if !showing {
            // Let the last card slide out before the panel goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.conversation == nil, self.center.notices.isEmpty else { return }
                    self.panel?.orderOut(nil)
                    self.tick?.invalidate()
                    self.tick = nil
                }
            }
            return
        }
        let where_ = anchor()
        guard let screen = where_.screen else { return }
        edge = where_.edge
        let panel = self.panel ?? makePanel()
        // Sized to what the content wants, placed beside the notch, centred
        // along the bezel where the notch is.
        let size = hosting?.fittingSize ?? .zero
        var frame = Self.frame(size: size, edge: where_.edge, inset: where_.inset,
                               screen: screen.frame, usable: screen.visibleFrame)
        if let topLeft = draggedTopLeft {
            // Grown or shrunk in place, hanging from where it was left.
            frame.origin = CGPoint(x: topLeft.x, y: topLeft.y - frame.height)
        }
        placing = true
        panel.setFrame(frame, display: true)
        placing = false
        panel.orderFrontRegardless()
        startTicking()
    }

    private func makePanel() -> NoticePanel {
        let panel = NoticePanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 100))
        let hosting = NoticeHostingView(rootView: NoticeRootView(controller: self, center: center))
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        // A move that was not ours is a drag: remember the top-left corner,
        // which is the edge a growing card should hang from.
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.placing, self.conversation != nil, let frame = self.panel?.frame else { return }
                    self.draggedTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
                }
            }
            .store(in: &cancellables)
        return panel
    }

    /// The card's frame in screen coordinates: `inset` from the bezel on the
    /// notch's edge, centred along it.
    static func frame(size: CGSize, edge: NotchEdge, inset: CGFloat,
                      screen: CGRect, usable: CGRect) -> CGRect {
        let w = size.width.rounded(.up), h = size.height.rounded(.up)
        switch edge {
        case .right:
            return CGRect(x: usable.maxX - inset - w, y: screen.midY - h / 2, width: w, height: h)
        case .left:
            return CGRect(x: usable.minX + inset, y: screen.midY - h / 2, width: w, height: h)
        case .top:
            return CGRect(x: screen.midX - w / 2, y: usable.maxY - inset - h, width: w, height: h)
        case .bottom:
            return CGRect(x: screen.midX - w / 2, y: usable.minY + inset, width: w, height: h)
        }
    }

    /// Half a second at a time: is the pointer on the cards, has any card
    /// been up long enough to go, and has an open conversation been left
    /// alone long enough to close on its own.
    private func startTicking() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let holding = panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
                self.center.expire(after: self.lifetime, holding: holding)
                guard self.conversation != nil else { return }
                if holding || panel.isKeyWindow {
                    self.pointerLeftAt = nil
                } else if let left = self.pointerLeftAt {
                    if Date().timeIntervalSince(left) > Self.conversationLingers { self.closeConversation() }
                } else {
                    self.pointerLeftAt = Date()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }
}
