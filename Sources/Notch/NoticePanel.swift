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
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The hosting view, which takes the first click: on a window that is never
/// key, the first click would otherwise only be an attempt to make it so.
final class NoticeHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One notice as drawn.
struct NoticeCardView: View {
    let notice: SessionNotice
    let open: () -> Void

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
}

/// The notices, newest at the bottom, each arriving from the bezel's side.
struct NoticeStackView: View {
    @ObservedObject var center: SessionNoticeCenter
    let edge: NotchEdge
    let open: (SessionNotice) -> Void

    var body: some View {
        VStack(spacing: Design.px(12)) {
            ForEach(center.notices) { notice in
                NoticeCardView(notice: notice) { open(notice) }
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

/// Puts the notices on screen beside the notch and takes them down again.
@MainActor
final class NoticeWindowController {
    static let width = Design.px(520)

    let center: SessionNoticeCenter
    /// How long a notice stays, unless the pointer is on the card.
    var lifetime: TimeInterval = 12
    /// Where the cards go: the screen and how far in from the bezel, asked
    /// each time because the notch may have opened or folded meanwhile.
    var anchor: () -> (screen: NSScreen?, edge: NotchEdge, inset: CGFloat) = { (NSScreen.main, .right, 0) }
    /// What a click on a card does.
    var open: (SessionNotice) -> Void = { _ in }

    private var panel: NoticePanel?
    private var hosting: NoticeHostingView<NoticeStackView>?
    private var cancellables = Set<AnyCancellable>()
    private var tick: Timer?

    init(center: SessionNoticeCenter) {
        self.center = center
        center.$notices
            .receive(on: RunLoop.main)
            .sink { [weak self] notices in
                MainActor.assumeIsolated { self?.present(notices) }
            }
            .store(in: &cancellables)
    }

    private func present(_ notices: [SessionNotice]) {
        if notices.isEmpty {
            // Let the last card slide out before the panel goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.center.notices.isEmpty else { return }
                    self.panel?.orderOut(nil)
                    self.tick?.invalidate()
                    self.tick = nil
                }
            }
            return
        }
        let where_ = anchor()
        guard let screen = where_.screen else { return }
        let panel = self.panel ?? makePanel(edge: where_.edge)
        // Sized to what the stack wants, placed beside the notch, centred
        // along the bezel where the notch is.
        hosting?.rootView = NoticeStackView(center: center, edge: where_.edge) { [weak self] in
            self?.open($0)
        }
        let size = hosting?.fittingSize ?? .zero
        panel.setFrame(Self.frame(size: size, edge: where_.edge, inset: where_.inset,
                                  screen: screen.frame, usable: screen.visibleFrame),
                       display: true)
        panel.orderFrontRegardless()
        startTicking()
    }

    private func makePanel(edge: NotchEdge) -> NoticePanel {
        let panel = NoticePanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 100))
        let hosting = NoticeHostingView(
            rootView: NoticeStackView(center: center, edge: edge) { [weak self] in self?.open($0) }
        )
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
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

    /// Half a second at a time: is the pointer on the cards, and has any
    /// card been up long enough to go.
    private func startTicking() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let holding = panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
                self.center.expire(after: self.lifetime, holding: holding)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }
}
