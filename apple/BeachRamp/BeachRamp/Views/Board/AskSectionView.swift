import SwiftUI
import BeachStatus

/// "Ask": a question box over the prediction engine, inline on the board.
/// Not a chat — one input line, three suggested questions as text links,
/// and the answer in the board's own voice (kicker · headline · detail)
/// with only the rows that carry news. Mirrors `web/js/ask.js`.
struct AskSectionView: View {
    @Bindable var session: ChatSession
    /// The board's selected city (GIS key); questions that name no place
    /// are about it, and the suggestions are written for it.
    let city: String?
    @Environment(\.ground) private var ground
    @FocusState private var inputFocused: Bool
    @State private var keyDraft = ""

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ask".uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                Spacer()
                Text("The outlook, in its own words")
                    .font(.archivo(11))
                    .foregroundStyle(t.ink2)
            }

            if session.featureOff {
                Text(session.errorText ?? "Ask is switched off right now.")
                    .font(.archivo(14))
                    .foregroundStyle(t.ink2)
            } else {
                askRow
                tryLine
                if session.needsKey { keyEntry }
                answer
                links
            }
        }
        .onAppear { session.contextCity = city }
        .onChange(of: city) { _, new in session.contextCity = new }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("askSection")
    }

    // MARK: - Input

    private var askRow: some View {
        let t = ground.tokens
        return HStack(spacing: 8) {
            TextField("Can I get on the beach this afternoon?", text: $session.draft)
                .font(.archivo(15))
                .foregroundStyle(t.ink)
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit(sendDraft)
                .disabled(session.isPending)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(Rectangle().strokeBorder(t.rule, lineWidth: 2))
                .accessibilityIdentifier("ask.input")
            Button(action: sendDraft) {
                Text("Ask".uppercased())
                    .font(.archivo(12, weight: .bold))
                    .tracking(12 * ArchivoTracking.kicker)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Rectangle().fill(canSend ? t.accent : t.rule2))
            }
            .buttonStyle(PressTintButtonStyle())
            .disabled(!canSend)
            .accessibilityIdentifier("ask.send")
        }
    }

    private var tryLine: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 4) {
            Text("Try".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, question in
                Button {
                    session.draft = question
                    Task { await session.send(question) }
                } label: {
                    Text(question)
                        .font(.archivo(13))
                        .underline(true, color: t.rule2)
                        .foregroundStyle(t.ink)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressTintButtonStyle())
                .disabled(session.isPending)
                .accessibilityIdentifier("ask.try.\(index)")
            }
        }
    }

    private var keyEntry: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 8) {
            Text(session.errorText ?? "Ask is locked. Enter the chat key once; it is kept in the Keychain.")
                .font(.archivo(13))
                .foregroundStyle(t.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("Chat key", text: $keyDraft)
                    .font(.archivo(15))
                    .foregroundStyle(t.ink)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit(saveKey)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().strokeBorder(t.rule, lineWidth: 2))
                    .accessibilityIdentifier("ask.key.field")
                Button(action: saveKey) {
                    Text("Save".uppercased())
                        .font(.archivo(12, weight: .bold))
                        .tracking(12 * ArchivoTracking.kicker)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Rectangle().fill(t.accent))
                }
                .buttonStyle(PressTintButtonStyle())
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("ask.key.save")
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Answer

    @ViewBuilder private var answer: some View {
        let t = ground.tokens
        if session.isPending {
            Text("Checking the outlook…")
                .font(.archivo(14, weight: .bold))
                .foregroundStyle(t.ink2)
                .padding(.top, 8)
        } else if let error = session.errorText, !session.needsKey {
            Text(error)
                .font(.archivo(14, weight: .bold))
                .foregroundStyle(t.accent)
                .padding(.top, 8)
        } else if let reply = session.latestReply {
            AskAnswerBlock(reply: reply, sources: session.sources)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private var links: some View {
        let t = ground.tokens
        if session.latestReply != nil || session.hasKey {
            HStack(spacing: 6) {
                if session.latestReply != nil, !session.isPending {
                    Button("Ask a follow-up ›") {
                        session.draft = ""
                        inputFocused = true
                    }
                    .font(.archivo(13, weight: .bold))
                    .foregroundStyle(t.accent)
                    Text("·").foregroundStyle(t.ink2)
                    Button("Clear") { session.reset() }
                        .font(.archivo(13))
                        .foregroundStyle(t.ink2)
                }
                if session.hasKey {
                    if session.latestReply != nil { Text("·").foregroundStyle(t.ink2) }
                    Button("Forget key") { session.forgetKey() }
                        .font(.archivo(13))
                        .foregroundStyle(t.ink2)
                }
            }
            .buttonStyle(PressTintButtonStyle())
            .padding(.top, 4)
        }
    }

    private var canSend: Bool {
        !session.isPending && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = session.draft
        Task { await session.send(text) }
    }

    private func saveKey() {
        session.saveKey(keyDraft)
        keyDraft = ""
        if !session.draft.isEmpty {
            let text = session.draft
            Task { await session.send(text) }
        } else {
            inputFocused = true
        }
    }
}

/// The answer in the board's voice: kicker from the facts, the reply's
/// first sentence as the headline, the rest as detail, only the rows that
/// carry news, and the days for a weekend question.
struct AskAnswerBlock: View {
    let reply: String
    let sources: [ChatSource]
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        let (lead, rest) = AskPresentation.splitLead(reply)
        let rows = AskPresentation.newsRows(sources)
        let days = AskPresentation.days(sources)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(t.rule).frame(height: 2)
            if let kicker = AskPresentation.kicker(for: sources) {
                Text(kicker.uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                    .padding(.top, 6)
            }
            Text(lead)
                .font(.archivo(19, weight: .extraBold))
                .foregroundStyle(t.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !rest.isEmpty {
                Text(rest)
                    .font(.archivo(14))
                    .foregroundStyle(t.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.name)
                                    .font(.archivo(13, weight: .bold))
                                    .foregroundStyle(t.ink)
                                Text(row.state)
                                    .font(.archivo(13, weight: row.isClosed ? .bold : .regular))
                                    .foregroundStyle(row.isClosed ? t.accent : t.ink2)
                                Spacer(minLength: 0)
                            }
                            if !row.note.isEmpty {
                                Text(row.note)
                                    .font(.archivo(12))
                                    .foregroundStyle(t.ink2)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Rectangle().fill(t.rule2).frame(height: 1) }
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(t.rule2).frame(height: 1) }
                .padding(.top, 6)
            }
            if !days.isEmpty {
                VStack(spacing: 0) {
                    ForEach(days) { d in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String((d.weekday ?? d.date ?? "").prefix(3)).uppercased())
                                .font(.archivo(11, weight: .bold))
                                .tracking(11 * ArchivoTracking.kicker)
                                .foregroundStyle(t.ink)
                                .frame(width: 40, alignment: .leading)
                            Text((d.verdict ?? "").replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(.archivo(10, weight: .bold))
                                .tracking(10 * ArchivoTracking.kicker)
                                .foregroundStyle(t.ink2)
                                .frame(width: 58, alignment: .leading)
                            Text(d.headline ?? "")
                                .font(.archivo(12))
                                .foregroundStyle(t.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .top) { Rectangle().fill(t.rule2).frame(height: 1) }
                    }
                }
                .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.answer")
    }
}

// MARK: - Previews

#if DEBUG
/// A transport for previews: one canned city answer, after a short pause.
struct PreviewChatTransport: ChatTransport {
    func send(_ request: ChatRequest, key: String) async throws -> ChatResponse {
        try? await Task.sleep(for: .seconds(1))
        return ChatResponse(reply: PreviewAsk.reply, sources: PreviewAsk.sources)
    }
}

enum PreviewAsk {
    static let reply = "Beach driving in New Smyrna Beach closes for the day around 6:30pm. That's the end of the driving day, not the tide, and they often start clearing a bit early. Right now it's four of five open: Crawford Rd has been closed for the tide since 7:46am, and the rest look clear until 6:30pm."
    static let sources: [ChatSource] = [
        ChatSource(kind: "city_now", city: "New Smyrna Beach",
                   headline: "Four of five open",
                   detail: "Crawford Rd closed for the tide since 7:46am · the rest look clear until 6:30pm",
                   openCount: 4, rampCount: 5,
                   ramps: [
                    ChatSourceRamp(accessID: "NS-141", name: "27th Av", status: "OPEN", risk: "scheduled", headline: "Beach driving closes for the day around 6:30pm"),
                    ChatSourceRamp(accessID: "NS-108", name: "Crawford Rd", status: "CLOSED FOR HIGH TIDE", risk: "closed_now", headline: "Closed for high tide"),
                    ChatSourceRamp(accessID: "NS-110", name: "Flagler Av", status: "OPEN", risk: "possible", headline: "Could close around the 3pm high tide"),
                   ]),
    ]

    @MainActor static func session(answered: Bool, key: String? = "k") -> ChatSession {
        let s = ChatSession(
            transport: PreviewChatTransport(),
            keyStore: InMemoryChatKeyStore(key),
            seed: answered ? [ChatTurn(role: .user, text: "what time will NSB close today?"), ChatTurn(role: .assistant, text: reply)] : [],
            sources: answered ? sources : []
        )
        s.contextCity = "NEW SMYRNA BEACH"
        if answered { s.draft = "what time will NSB close today?" }
        return s
    }
}

#Preview("Answered · day") {
    ScrollView {
        AskSectionView(session: PreviewAsk.session(answered: true), city: "NEW SMYRNA BEACH")
            .padding(18)
    }
    .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!).state)
}

#Preview("Empty · night") {
    AskSectionView(session: PreviewAsk.session(answered: false), city: "DAYTONA BEACH")
        .padding(18)
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!).state)
}

#Preview("Needs key") {
    AskSectionView(session: PreviewAsk.session(answered: false, key: nil), city: "NEW SMYRNA BEACH")
        .padding(18)
        .environment(\.ground, GroundModel(overrideDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!).state)
}
#endif
