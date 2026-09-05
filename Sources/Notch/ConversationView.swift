import SwiftUI
import UniformTypeIdentifiers

/// A session's last turns, and a line to send back.
struct ConversationView: View {
    @ObservedObject var conversation: Conversation
    let close: () -> Void
    let open: () -> Void
    let send: () -> Void
    var cancel: () -> Void = {}

    @FocusState private var typing: Bool
    @State private var dropping = false

    private var session: AgentSession { conversation.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, NotchLayout.headerToBlock)

            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)

            turns
                .padding(.vertical, NotchLayout.blockSpacing)

            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)

            reply
                .padding(.top, NotchLayout.blockSpacing)
        }
        .padding(NotchLayout.cardPadding)
        .frame(width: NoticeWindowController.width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            // A drop about to land: the card's edge lights up in your blue.
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .continuous)
                .stroke(Palette.you, lineWidth: Design.px(4))
                .opacity(dropping ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: dropping)
        )
        // Files and images dropped anywhere on the card go with the line, by
        // path — the way a drop into the terminal does.
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            Attachments.accept(providers) { urls in
                conversation.attachments.append(contentsOf: urls)
            }
            return true
        }
        .onExitCommand(perform: close)
        .onAppear { typing = true }
    }

    private var header: some View {
        HStack(spacing: NotchLayout.statusDotGap) {
            Circle()
                .fill(stateColor)
                .frame(width: NotchLayout.statusDot * 0.6, height: NotchLayout.statusDot * 0.6)
            Text(session.name)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Design.px(20))
            Text(session.detail)
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: Design.px(18), weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Design.px(40), height: Design.px(40))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .busy:    return Palette.ample
        case .waiting: return Palette.watch
        case .idle:    return Palette.textSecondary
        }
    }

    private var turns: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: NotchLayout.blockSpacing) {
                    if conversation.isEmpty {
                        Text("Nothing readable yet.")
                            .font(Typography.cardBody)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(Array(conversation.turns.enumerated()), id: \.offset) { index, turn in
                        TurnView(turn: turn, providerName: providerName)
                            .id(index)
                    }
                    if conversation.state == .busy {
                        WorkingRow(providerName: providerName)
                            .id(conversation.turns.count)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Design.px(760))
            .onChange(of: conversation.turns.count, initial: true) { _, count in
                guard count > 0 else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
            .onChange(of: conversation.state) { _, state in
                guard state == .busy else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(conversation.turns.count, anchor: .bottom) }
            }
        }
    }

    private var providerName: String {
        session.id.split(separator: ".").first.map { String($0).capitalized } ?? "Agent"
    }

    private var reply: some View {
        VStack(alignment: .leading, spacing: Design.px(12)) {
            if !conversation.attachments.isEmpty {
                attachments
            }
            HStack(alignment: .bottom, spacing: NotchLayout.statusDotGap) {
                TextField("Reply…", text: $conversation.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.you)
                    .lineLimit(1...5)
                    .focused($typing)
                    .onSubmit(send)
                    // An image pasted from the clipboard is saved as a file
                    // and goes along like a dropped one.
                    .onPasteCommand(of: [.png, .tiff, .image]) { providers in
                        Attachments.accept(providers) { urls in
                            conversation.attachments.append(contentsOf: urls)
                        }
                    }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: Design.px(30)))
                        .foregroundStyle(conversation.draft.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Palette.textSecondary : Palette.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(conversation.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Send — Enter. Option-Enter for a new line.")
            }
            HStack(spacing: Design.px(20)) {
                // A refusal is the one thing here that must not be missed:
                // it says why the line did not go, and often what to do.
                Text(status)
                    .font(Typography.cardBody)
                    .foregroundStyle(failed ? Palette.watch : Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if conversation.sendState == .waiting {
                    Button("Cancel", action: cancel)
                        .buttonStyle(.plain)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer(minLength: 0)
                Button(action: open) {
                    Text("Open")
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Design.px(16))
                        .padding(.vertical, Design.px(6))
                        .background(Capsule().fill(Palette.ringTrack))
                }
                .buttonStyle(.plain)
                .help("Bring the session's window forward")
            }
        }
    }

    private var failed: Bool {
        if case .failed = conversation.sendState { return true }
        return false
    }

    /// What goes with the line, each with a way to take it back.
    private var attachments: some View {
        FlowRow(spacing: Design.px(8)) {
            ForEach(conversation.attachments, id: \.self) { url in
                HStack(spacing: Design.px(6)) {
                    Image(systemName: Attachments.isImage(url) ? "photo" : "doc")
                        .font(.system(size: Design.px(14)))
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        conversation.attachments.removeAll { $0 == url }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: Design.px(11), weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Design.px(12))
                .padding(.vertical, Design.px(5))
                .background(Capsule().fill(Palette.ringTrack))
                .frame(maxWidth: Design.px(260))
            }
        }
    }

    private var status: String {
        switch conversation.sendState {
        case .idle:          return ""
        case .waiting:       return "The agent is mid-turn — it goes the moment it is free."
        case .sent(let at):  return "Sent \(ElapsedCopy.ago(since: at))"
        case .failed(let w): return w
        case .copied:        return "Copied — paste it into the session"
        }
    }
}

/// The agent is writing: three dots that breathe, where its turn will be.
/// Driven by a slow clock rather than three endless animations.
private struct WorkingRow: View {
    let providerName: String

    var body: some View {
        HStack(spacing: Design.px(12)) {
            Text(providerName)
                .font(Typography.cardBody.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: Design.px(6)) {
                    ForEach(0..<3, id: \.self) { i in
                        let phase = ((t / 1.2) - Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .fill(Palette.textSecondary)
                            .frame(width: Design.px(9), height: Design.px(9))
                            .opacity(0.25 + 0.75 * (0.5 - 0.5 * cos(phase * 2 * .pi)))
                    }
                }
            }
        }
    }
}

/// One turn: who, then what, with the markdown's inline marks honoured.
private struct TurnView: View {
    let turn: TranscriptTurn
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.px(6)) {
            HStack(spacing: Design.px(12)) {
                Text(turn.role == .user ? "You" : providerName)
                    .font(Typography.cardBody.weight(.semibold))
                    .foregroundStyle(turn.role == .user ? Palette.you : Palette.textPrimary)
                if let at = turn.at {
                    Text(ElapsedCopy.ago(since: at))
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Text(rendered)
                .font(Typography.cardBody)
                .foregroundStyle(turn.role == .user ? Palette.you : Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: turn.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(turn.text)
    }
}


/// Chips laid out left to right, wrapping to a new line when the row is full.
private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // SwiftUI's own flow container, sized to the card's width.
        _FlowLayout(spacing: spacing) { content }
    }
}

private struct _FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
