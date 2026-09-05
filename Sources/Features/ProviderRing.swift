import SwiftUI

/// The ring around a provider glyph: a grey track with a coloured arc that
/// starts at 12 o'clock and sweeps clockwise by the fraction *left*.
///
/// What is left, not what is gone: a full ring is an untouched limit, and it
/// empties as you spend it, the way a battery does. Drawn the other way round
/// a nearly-full ring meant nearly out, which is the opposite of what a full
/// shape says to the eye. The colour still keys on how much has gone — green
/// with plenty left, red with little — so the two readings agree.
///
/// When that provider is doing something right now, a second, much thinner arc
/// appears *inside* the ring, in the gap between the glyph and the track. It is
/// deliberately a different radius, a different weight and a neutral colour, so
/// it reads as a separate fact rather than as the usage number moving.
struct ProviderRing: View {
    /// Nil when the provider reports what is left but never says out of what —
    /// there is no arc to draw, and inventing one would be a lie in a shape.
    let usedFraction: Double?
    let glyph: ProviderGlyph
    var isStale: Bool = false
    /// Blocked right now. Shown as spent whatever the arc says, because that is
    /// what it means for you — a ring reading 16% while the account is paused
    /// is technically true and practically a lie.
    var isBlocked: Bool = false
    var activity: ActivitySummary?
    /// A fetch this cell asked for, in flight.
    var isRefreshing: Bool = false
    /// A second window, drawn inside the ring in one of two ways; the third
    /// way, the bar, lives in the cell rather than the ring.
    var secondary: SecondaryReading?
    var secondaryStyle: SecondaryStyle = .innerRing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    /// The inner ring takes the room the glyph and the activity arc had.
    private var isCompact: Bool { secondary != nil && secondaryStyle == .innerRing }

    private var band: UsageBand {
        isBlocked ? .exhausted : UsageBand.band(for: usedFraction ?? 0)
    }
    /// How much of the circle the arc covers: what is left. Blocked keeps the
    /// arc — the number under it is still true — and says "paused" with the
    /// colour and the dimmed glyph instead, so the two never contradict.
    private var sweep: CGFloat { 1 - CGFloat(min(max(usedFraction ?? 0, 0), 1)) }
    /// The track turns faintly red once nothing is left, so an empty ring still
    /// reads as an alarm rather than as no reading at all.
    private var trackColor: Color {
        band == .exhausted ? Palette.critical.opacity(0.35) : Palette.ringTrack
    }

    var body: some View {
        ZStack {
            // Dimming applies to the usage reading only. Whether Claude is
            // working right now is known first-hand and stays at full strength
            // even when the percentage behind it has gone stale.
            ZStack {
                // The level: a tint rising inside the track, under everything.
                if let secondary, secondaryStyle == .level {
                    let inside = NotchLayout.ringDiameter - 2 * NotchLayout.trackStroke
                    Circle()
                        .fill(secondary.band.color.opacity(0.22))
                        .frame(width: inside, height: inside)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: inside * CGFloat(secondary.remaining))
                        }
                        .animation(NotchMotion.reading, value: secondary)
                }

                Circle()
                    .strokeBorder(trackColor, lineWidth: NotchLayout.trackStroke)
                    .animation(NotchMotion.reading, value: band)

                if usedFraction != nil {
                    Circle()
                        .inset(by: NotchLayout.trackStroke / 2)
                        .trim(from: 0, to: sweep)
                        .stroke(
                            band.color,
                            style: StrokeStyle(lineWidth: NotchLayout.progressStroke, lineCap: .round)
                        )
                        // Refreshing spins the reading itself rather than
                        // overlaying a separate spinner: the thing being
                        // refetched is the thing that should move, and a second
                        // arc on the same track only competes with it.
                        .rotationEffect(.degrees(-90 + spin))
                        // A ring that snaps to a new value reads as a glitch; one
                        // that sweeps reads as a measurement being taken.
                        .animation(NotchMotion.reading, value: sweep)
                        .animation(NotchMotion.reading, value: band)
                }

                // The inner ring: a second gauge on the same axis, thinner so
                // the eye reads it second.
                if let secondary, secondaryStyle == .innerRing {
                    Circle()
                        .stroke(Palette.ringTrack, lineWidth: NotchLayout.innerRingStroke)
                        .frame(width: NotchLayout.innerRingDiameter, height: NotchLayout.innerRingDiameter)
                    Circle()
                        .trim(from: 0, to: CGFloat(secondary.remaining))
                        .stroke(
                            secondary.band.color,
                            style: StrokeStyle(lineWidth: NotchLayout.innerRingStroke, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: NotchLayout.innerRingDiameter, height: NotchLayout.innerRingDiameter)
                        .animation(NotchMotion.reading, value: secondary)
                }

                ProviderGlyphView(
                    glyph: glyph,
                    size: isCompact ? NotchLayout.compactGlyphSize : NotchLayout.glyphSize
                )
                    .foregroundStyle(Palette.textPrimary)
                    // A spent limit dims its glyph so the ring reads as "waiting".
                    .opacity(band == .exhausted ? 0.35 : 1)
            }
            .opacity(isStale ? 0.45 : 1)

            if let activity, activity.state != .idle {
                ActivityArc(summary: activity, compact: isCompact)
            }
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
        // Pressed in while it works, and released when the answer lands. The
        // ring is the button, so the ring is what should feel pressed.
        .scaleEffect(isRefreshing ? 0.93 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isRefreshing)
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            // Exactly one turn, and it stops by itself.
            //
            // The obvious spelling is a `repeatForever` linear spin started on
            // the way in and cancelled on the way out — but `repeatForever` does
            // not stop when you set the value back, and if the value you set is
            // the one it is already animating toward, nothing changes and it
            // simply keeps going. The ring then spins for ever after a refresh
            // that finished half a second in.
            //
            // A single finite turn has no cancellation problem at all: 360° is
            // the same angle as 0°, so it lands exactly where the reading
            // belongs. It eases out, so it settles rather than stopping dead.
            withAnimation(.timingCurve(0.32, 0, 0.14, 1, duration: 0.95)) {
                spin += 360
            }
        }
    }
}

/// The inner indicator: a short arc that spins while work is happening, and a
/// full pulsing ring when something is blocked waiting on you.
private struct ActivityArc: View {
    let summary: ActivitySummary
    /// Drawn smaller and finer when an inner ring has taken its room.
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var pulsing = false

    /// How much of the circle the moving arc covers.
    private let arcFraction: CGFloat = 0.25

    private var diameter: CGFloat {
        compact ? NotchLayout.compactActivityDiameter : NotchLayout.activityDiameter
    }
    private var stroke: CGFloat {
        compact ? NotchLayout.compactActivityStroke : NotchLayout.activityStroke
    }
    private var inset: CGFloat { (NotchLayout.ringDiameter - diameter) / 2 }

    var body: some View {
        Group {
            switch summary.state {
            case .working: spinner
            case .waiting: pulse
            case .idle:    EmptyView()
            }
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
    }

    private var spinner: some View {
        Circle()
            .inset(by: inset)
            .trim(from: 0, to: arcFraction)
            .stroke(
                summary.color,
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
            .onDisappear { spinning = false }
    }

    private var pulse: some View {
        Circle()
            .inset(by: inset)
            .stroke(summary.color, lineWidth: stroke)
            .opacity(pulsing ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .onDisappear { pulsing = false }
    }
}

/// A ring and the percent *left* underneath it — with, between the two, the
/// second window's bar when that is the style and every cell holds room for
/// it. Above the number rather than below, so the number stays the ring's.
struct ProviderCell: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    var isRefreshing: Bool = false
    var secondaryStyle: SecondaryStyle = .innerRing

    private var secondary: SecondaryReading? { snapshot.secondaryReading }

    /// The bar's slot is held whether or not this cell fills it.
    private var reservesBar: Bool { NotchLayout.reservesSecondaryBar }

    /// A dash, not "0%": nothing read is not the same as nothing used.
    private var percentText: String {
        snapshot.hasReading ? snapshot.headlineText : "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            ProviderRing(
                usedFraction: snapshot.hasReading ? snapshot.ringFraction : nil,
                glyph: snapshot.glyph,
                isStale: snapshot.status.isStale || !snapshot.hasReading,
                isBlocked: snapshot.block != nil,
                activity: activity,
                isRefreshing: isRefreshing,
                secondary: secondaryStyle == .bar ? nil : secondary,
                secondaryStyle: secondaryStyle
            )
            if reservesBar {
                // The bar sits in the gap the label already keeps, which
                // grows by exactly the bar's height — see `cellExtent`.
                secondaryBar
                    .frame(width: NotchLayout.secondaryBarWidth, height: NotchLayout.secondaryBarHeight)
                    .padding(.top, NotchLayout.ringLabelGap * 0.45)
            }
            Text(percentText)
                .font(Typography.percent)
                .foregroundStyle(Palette.textPrimary)
                // Never squeezed: across a horizontal edge the cell is only as
                // wide as the ring, and a label wider than that would be
                // truncated rather than allowed to overhang into the spacing
                // that is already there for it.
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: NotchLayout.percentLineHeight)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: percentText)
                .padding(.top, reservesBar ? NotchLayout.ringLabelGap * 0.55 : NotchLayout.ringLabelGap)
        }
        .frame(height: NotchLayout.cellExtent)
    }

    /// Filled when this cell has a second window in the bar style, an empty
    /// slot otherwise — never an empty *track*, which would read as a reading
    /// of nothing.
    @ViewBuilder
    private var secondaryBar: some View {
        if secondaryStyle == .bar, let secondary {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.barTrack)
                    Capsule()
                        .fill(secondary.band.color)
                        .frame(width: max(proxy.size.height, proxy.size.width * CGFloat(secondary.remaining)))
                        .animation(NotchMotion.reading, value: secondary)
                }
            }
        } else {
            Color.clear
        }
    }
}
