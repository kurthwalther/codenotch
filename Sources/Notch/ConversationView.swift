import SwiftUI

/// A session's last turns, and a line to send back.
struct ConversationView: View {
    @ObservedObject var conversation: Conversation
    let close: () -> Void
    let open: () -> Void
    let send: () -> Void

    @FocusState private var typing: Bool

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
            HStack(alignment: .bottom, spacing: NotchLayout.statusDotGap) {
                TextField("Reply…", text: $conversation.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...5)
                    .focused($typing)
                    .onSubmit(send)
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

    private var status: String {
        switch conversation.sendState {
        case .idle:          return ""
        case .sent(let at):  return "Sent \(ElapsedCopy.ago(since: at))"
        case .failed(let w): return w
        case .copied:        return "Copied — paste it into the session"
        }
    }
}

/// The agent is writing: three dots that breathe, where its turn will be.
private struct WorkingRow: View {
    let providerName: String
    @State private var on = false

    var body: some View {
        HStack(spacing: Design.px(12)) {
            Text(providerName)
                .font(Typography.cardBody.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            HStack(spacing: Design.px(6)) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Palette.textSecondary)
                        .frame(width: Design.px(9), height: Design.px(9))
                        .opacity(on ? 1 : 0.25)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2), value: on)
                }
            }
            .onAppear { on = true }
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
                    .foregroundStyle(turn.role == .user ? Palette.textSecondary : Palette.textPrimary)
                if let at = turn.at {
                    Text(ElapsedCopy.ago(since: at))
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Text(rendered)
                .font(Typography.cardBody)
                .foregroundStyle(turn.role == .user ? Palette.textSecondary : Palette.textPrimary)
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
