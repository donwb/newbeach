import SwiftUI
import BeachStatus

/// "Ask": a chat sheet over the prediction engine. Every answer is the
/// server's words; under the last reply sits a fact card built from the
/// engine `sources` the reply rested on, so the card is right whatever the
/// prose says. Sits on the veiled ground like the rest of the board — zero
/// radius, 2pt rules, Archivo.
struct ChatView: View {
    @Bindable var session: ChatSession
    @Environment(\.ground) private var ground
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    @State private var keyDraft = ""

    var body: some View {
        let t = ground.tokens
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Rectangle().fill(t.rule).frame(height: 2)

            transcript

            Rectangle().fill(t.rule2).frame(height: 1)

            if session.needsKey {
                KeyEntryView(draft: $keyDraft, errorText: session.errorText) {
                    session.saveKey(keyDraft)
                    keyDraft = ""
                    if !session.draft.isEmpty { inputFocused = true }
                }
                .padding(18)
            } else if session.featureOff {
                Text(session.errorText ?? "Ask is switched off right now.")
                    .font(.archivo(14))
                    .foregroundStyle(t.ink2)
                    .padding(18)
            } else {
                composer
            }
        }
        .background {
            ZStack {
                ground.skyGradient
                ground.veil
            }
            .ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("chat.sheet")
    }

    // MARK: - Header

    private var header: some View {
        let t = ground.tokens
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask about the beach".uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                Text(session.contextRamp.map { "About \($0.shortDisplayName)" } ?? "Any ramp, any time this week")
                    .font(.archivo(17, weight: .extraBold))
                    .foregroundStyle(t.ink)
            }
            Spacer()
            if !session.turns.isEmpty {
                Button("Clear") { session.reset() }
                    .font(.archivo(13, weight: .bold))
                    .foregroundStyle(t.ink2)
                    .buttonStyle(PressTintButtonStyle())
                    .accessibilityIdentifier("chat.clear")
            }
            Button("Done") { dismiss() }
                .font(.archivo(13, weight: .bold))
                .foregroundStyle(t.accent)
                .buttonStyle(PressTintButtonStyle())
                .accessibilityIdentifier("chat.done")
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        let t = ground.tokens
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.turns.isEmpty {
                        Text("Ask whether a ramp will be open at a time this week, or which day looks best. Answers are the board's own outlook, in its own words.")
                            .font(.archivo(14))
                            .foregroundStyle(t.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    ForEach(session.turns) { turn in
                        ChatBubble(turn: turn)
                            .id(turn.id)
                    }
                    if let last = session.turns.last, last.role == .assistant, !session.sources.isEmpty {
                        ChatSourceCard(sources: session.sources)
                    }
                    if session.isPending {
                        HStack(spacing: 8) {
                            ProgressView().tint(t.ink2)
                            Text("Checking the outlook…")
                                .font(.archivo(13))
                                .foregroundStyle(t.ink2)
                        }
                        .id("pending")
                    }
                    if let error = session.errorText, !session.needsKey {
                        Text(error)
                            .font(.archivo(13, weight: .semiBold))
                            .foregroundStyle(t.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            .onChange(of: session.turns.count) {
                withAnimation { proxy.scrollTo(session.turns.last?.id, anchor: .bottom) }
            }
            .onChange(of: session.isPending) { _, pending in
                if pending { withAnimation { proxy.scrollTo("pending", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, question in
                        Button {
                            Task { await session.send(question) }
                        } label: {
                            Text(question)
                                .font(.archivo(12, weight: .semiBold))
                                .foregroundStyle(t.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .overlay(Rectangle().strokeBorder(t.rule2, lineWidth: 1))
                        }
                        .buttonStyle(PressTintButtonStyle())
                        .disabled(session.isPending)
                        .accessibilityIdentifier("chat.suggestion.\(index)")
                    }
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 10) {
                TextField("Ask about a ramp…", text: $session.draft)
                    .font(.archivo(15))
                    .foregroundStyle(t.ink)
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .onSubmit(sendDraft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().strokeBorder(t.rule, lineWidth: 2))
                    .accessibilityIdentifier("chat.input")
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? .white : t.ink2)
                        .frame(width: 44, height: 44)
                        .background(Rectangle().fill(canSend ? t.accent : t.rule2))
                }
                .buttonStyle(PressTintButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat.send")
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !session.isPending && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = session.draft
        Task { await session.send(text) }
    }
}

/// One transcript turn: the user's question right-aligned in secondary ink,
/// the answer left-aligned in primary ink.
struct ChatBubble: View {
    let turn: ChatTurn
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.archivo(turn.role == .user ? 14 : 15, weight: turn.role == .user ? .semiBold : .regular))
                .foregroundStyle(turn.role == .user ? t.ink2 : t.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(turn.role == .user ? .trailing : .leading)
            if turn.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The engine facts behind the last reply. A ramp fact shows name · when ·
/// headline · detail; weekend facts list the days. The accent bar appears
/// only for a live closure — red means closed and nothing else.
struct ChatSourceCard: View {
    let sources: [ChatSource]
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        let ramps = sources.filter { $0.kind == "ramp_outlook" }
        let days = sources.filter { $0.kind == "weekend_day" }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ramps) { s in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(s.isClosedNow ? t.accent : t.rule)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text([s.name, s.atLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.archivo(10, weight: .bold))
                            .tracking(10 * ArchivoTracking.kicker)
                            .textCase(.uppercase)
                            .foregroundStyle(t.ink2)
                        if let headline = s.headline {
                            Text(headline)
                                .font(.archivo(14, weight: .extraBold))
                                .foregroundStyle(t.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let detail = s.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.archivo(12))
                                .foregroundStyle(t.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(days) { d in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(d.weekday ?? d.date ?? "")
                                .font(.archivo(12, weight: .bold))
                                .foregroundStyle(t.ink)
                                .frame(width: 84, alignment: .leading)
                            Text(d.headline ?? "")
                                .font(.archivo(12))
                                .foregroundStyle(t.ink2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let verdict = d.verdict {
                                Text(verdict.uppercased())
                                    .font(.archivo(9, weight: .bold))
                                    .tracking(9 * ArchivoTracking.kicker)
                                    .foregroundStyle(t.ink2)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(t.rule2).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .overlay(Rectangle().strokeBorder(t.rule2, lineWidth: 1))
        .accessibilityIdentifier("chat.sourceCard")
    }
}

/// Where the chat key goes. Shown when the server answers 401 or 503; the
/// unsent question waits in the composer meanwhile.
struct KeyEntryView: View {
    @Binding var draft: String
    let errorText: String?
    let onSave: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat key".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            Text(errorText ?? "Ask is locked. Enter the chat key from the server once; it is kept in the Keychain.")
                .font(.archivo(13))
                .foregroundStyle(t.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                SecureField("Key", text: $draft)
                    .font(.archivo(15))
                    .foregroundStyle(t.ink)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit(onSave)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().strokeBorder(t.rule, lineWidth: 2))
                    .accessibilityIdentifier("chat.key.field")
                Button(action: onSave) {
                    Text("Save")
                        .font(.archivo(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Rectangle().fill(t.accent))
                }
                .buttonStyle(PressTintButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("chat.key.save")
            }
        }
    }
}

/// The board's entry point: one bordered row that reads as pressable.
struct AskRowView: View {
    let title: String
    let action: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.archivo(14, weight: .bold))
                    .foregroundStyle(t.ink)
                Spacer()
                Text("›")
                    .font(.archivo(16, weight: .bold))
                    .foregroundStyle(t.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .overlay(Rectangle().strokeBorder(t.rule, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressTintButtonStyle())
        .accessibilityIdentifier("askRow")
    }
}

// MARK: - Previews

#if DEBUG
/// A transport for previews: one canned answer, after a short pause.
struct PreviewChatTransport: ChatTransport {
    func send(_ request: ChatRequest, key: String) async throws -> ChatResponse {
        try? await Task.sleep(for: .seconds(1))
        return ChatResponse(
            reply: "Flagler Av could close around the 2:30pm high tide on Friday. Closure possible around 2:30pm, often back open by ~4:30pm.",
            sources: [ChatSource(kind: "ramp_outlook", accessID: "NS-110", name: "Flagler Av", atLabel: "Friday ~2pm",
                                 risk: "possible", reason: "high_tide",
                                 headline: "Could close around the 2:30pm high tide",
                                 detail: "Closure possible around 2:30pm · often back open by ~4:30pm",
                                 windowLabel: "11:30am–5pm", relation: "inside")]
        )
    }
}

private let previewRamp = Ramp(
    id: 3, rampName: "FLAGLER AV", accessStatus: "OPEN", statusCategory: "open",
    objectID: 3, city: "NEW SMYRNA BEACH", accessID: "NS-110", location: "NEW SMYRNA BEACH",
    lastUpdated: Date(), statusSince: nil
)

@MainActor private func previewSession(answered: Bool, key: String? = "k") -> ChatSession {
    let session = ChatSession(
        transport: PreviewChatTransport(),
        keyStore: InMemoryChatKeyStore(key),
        seed: answered ? [
            ChatTurn(role: .user, text: "Will Flagler be open Friday at 2pm?"),
            ChatTurn(role: .assistant, text: "Flagler Av could close around the 2:30pm high tide on Friday. Closure possible around 2:30pm, often back open by ~4:30pm."),
        ] : [],
        sources: answered ? [ChatSource(kind: "ramp_outlook", accessID: "NS-110", name: "Flagler Av", atLabel: "Friday ~2pm",
                                        risk: "possible", headline: "Could close around the 2:30pm high tide",
                                        detail: "Closure possible around 2:30pm · often back open by ~4:30pm")] : []
    )
    session.contextRamp = previewRamp
    return session
}

#Preview("Empty · day") {
    ChatView(session: previewSession(answered: false))
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!).state)
}

#Preview("Answered · night") {
    ChatView(session: previewSession(answered: true))
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!).state)
}

#Preview("Needs key") {
    ChatView(session: previewSession(answered: false, key: nil))
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!).state)
}
#endif
