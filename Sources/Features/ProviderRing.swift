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
    /// A symbol in place of the logo, when one was chosen.
    var symbol: String? = nil
    var isStale: Bool = false
    /// Blocked right now. Shown as spent whatever the arc says, because that is
    /// what it means for you — a ring reading 16% while the account is paused
    /// is technically true and practically a lie.
    var isBlocked: Bool = false
    var activity: ActivitySummary?
    /// A fetch this cell asked for, in flight.
    var isRefreshing: Bool = false
    /// The notch's scale, carried as a value: every size here is read from
    /// `NotchLayout` at render time, and SwiftUI only renders again when
    /// something it was *given* has changed.
    var scale: CGFloat = Design.notchFactor
    /// Left alone for a while under Always show: the activity arc fades
    /// further than the rest, to a whisper.
    var isResting: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageThresholds) private var thresholds
    @State private var spin: Double = 0

    private var band: UsageBand {
        isBlocked ? .exhausted : UsageBand.band(for: usedFraction ?? 0, thresholds: thresholds)
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
                Circle()
                    .strokeBorder(trackColor, lineWidth: NotchLayout.trackStroke)
                    .animation(NotchMotion.reading, value: band)
                    // The track is already quiet; only the coloured arc and
                    // the glyph below take the resting fade.

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
                        .opacity(isResting ? NotchViewModel.restingOpacity : 1)
                }

                ProviderGlyphView(glyph: glyph, symbol: symbol, size: NotchLayout.glyphSize)
                    .foregroundStyle(Palette.textPrimary)
                    // A spent limit dims its glyph so the ring reads as "waiting".
                    .opacity(band == .exhausted ? 0.35 : 1)
                    .opacity(isResting ? NotchViewModel.restingOpacity : 1)
            }
            .opacity(isStale ? 0.45 : 1)

            if let activity, activity.state != .idle {
                ActivityArc(summary: activity, scale: scale, isResting: isResting)
                    .opacity(isResting ? 0.3 : 1)
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

/// The inner indicator: a short arc that turns while work is happening, and a
/// full ring that breathes when something is blocked waiting on you.
///
/// A Core Animation layer underneath, so the turning costs the app nothing
/// per frame — see `ActivityArcLayer`. At rest it turns slowly; with motion
/// reduced it is drawn once and left.
private struct ActivityArc: View {
    let summary: ActivitySummary
    /// See `ProviderRing.scale`.
    var scale: CGFloat = Design.notchFactor
    var isResting: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn, and one breath, in seconds — and at rest, a slower turn.
    private static let turn: Double = 1.1
    private static let restingTurn: Double = 3.0
    private static let breath: Double = 1.8

    var body: some View {
        Group {
            switch summary.state {
            case .working:
                ActivityArcLayer(mode: .spin, color: summary.color,
                                 diameter: NotchLayout.activityDiameter,
                                 lineWidth: NotchLayout.activityStroke,
                                 period: isResting ? Self.restingTurn : Self.turn,
                                 still: reduceMotion)
            case .waiting:
                ActivityArcLayer(mode: .pulse, color: summary.color,
                                 diameter: NotchLayout.activityDiameter,
                                 lineWidth: NotchLayout.activityStroke,
                                 period: Self.breath,
                                 still: reduceMotion || isResting)
            case .idle:
                EmptyView()
            }
        }
        .frame(width: NotchLayout.activityDiameter, height: NotchLayout.activityDiameter)
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
    }
}

/// A ring and the percent *left* underneath it — and, above the ring, the
/// second window's bar while any provider has one. Above rather than between
/// ring and number, so the number stays unmistakably the ring's and the bar
/// reads as the lesser gauge.
struct ProviderCell: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    var isRefreshing: Bool = false
    /// The bar's slot is held whether or not this cell fills it.
    var reservesBar: Bool = NotchLayout.reservesSecondaryBar
    /// See `ProviderRing.scale`.
    var scale: CGFloat = Design.notchFactor
    /// See `ProviderRing.isResting`.
    var isResting: Bool = false
    /// For a number that counts down to the reset.
    var now: Date = Date()

    @Environment(\.usageThresholds) private var thresholds

    private var secondary: SecondaryReading? { snapshot.secondaryReading }

    /// A dash, not "0%": nothing read is not the same as nothing used.
    private var percentText: String {
        snapshot.hasReading ? snapshot.cellText(now: now) : "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            if reservesBar {
                VStack(spacing: 0) {
                    // Its own number above it, smaller than the ring's and a
                    // shade quieter; its name below, given the larger gap so
                    // the two look evenly spaced about the bar.
                    Text(secondary.map { "\(Int(($0.remaining * 100).rounded()))%" } ?? " ")
                        .font(Typography.barPercent)
                        .foregroundStyle(Palette.textBright)
                        .fixedSize()
                        .frame(height: NotchLayout.secondaryBarLabelHeight)
                    secondaryBar
                        .frame(width: NotchLayout.secondaryBarWidth, height: NotchLayout.secondaryBarHeight)
                        .padding(.top, NotchLayout.secondaryBarLabelGap)
                    Text(snapshot.secondary?.shortLabel ?? " ")
                        .font(Typography.barName)
                        .foregroundStyle(Palette.textMid)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: NotchLayout.secondaryBarNameHeight)
                        .padding(.top, NotchLayout.secondaryBarNameGap)
                }
                .padding(.bottom, NotchLayout.secondaryBarGap)
            }
            ProviderRing(
                usedFraction: snapshot.hasReading ? snapshot.ringFraction : nil,
                glyph: snapshot.glyph,
                symbol: snapshot.iconSymbol,
                isStale: snapshot.status.isStale || !snapshot.hasReading,
                isBlocked: snapshot.block != nil,
                activity: activity,
                isRefreshing: isRefreshing,
                scale: scale,
                isResting: isResting
            )
            // Which window the number is, between the ring and the number;
            // then the number; then when it comes back. Small lines, there
            // to be found rather than read first.
            caption(snapshot.headline?.shortLabel ?? " ")
                .padding(.top, NotchLayout.ringCaptionGap)
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
                .opacity(isResting ? NotchViewModel.restingOpacity : 1)
                .padding(.top, NotchLayout.nameToPercentGap)
            resetCaption
                .padding(.top, NotchLayout.captionGap)
        }
        .frame(height: NotchLayout.cellExtent)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .frame(height: NotchLayout.captionLineHeight)
    }

    /// The reset time — or nothing, for a provider that never says.
    @ViewBuilder
    private var resetCaption: some View {
        if snapshot.hasReading, let resetsAt = snapshot.headline?.resetsAt {
            // The time alone: under the window's name and its number, a
            // time can only mean when it comes back.
            Text(ResetCopy.short(for: resetsAt, now: now))
                .font(Typography.barName)
                .foregroundStyle(Palette.textBright)
                .lineLimit(1)
                .fixedSize()
                .frame(height: NotchLayout.resetLineHeight)
        } else {
            Color.clear.frame(height: NotchLayout.resetLineHeight)
        }
    }

    /// Filled when this cell has a second window, an empty slot otherwise —
    /// never an empty *track*, which would read as a reading of nothing.
    @ViewBuilder
    private var secondaryBar: some View {
        if let secondary {
            // Sized outright: the bar's width is a layout constant, so there
            // is nothing to measure — and a measuring container here left
            // the number under it undrawn.
            let width = NotchLayout.secondaryBarWidth
            let height = NotchLayout.secondaryBarHeight
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.barTrack)
                Capsule()
                    .fill(secondary.band(thresholds).color)
                    .frame(width: max(height, width * CGFloat(secondary.remaining)))
                    .animation(NotchMotion.reading, value: secondary)
                    .opacity(isResting ? NotchViewModel.restingOpacity : 1)
            }
        } else {
            Color.clear
        }
    }
}
