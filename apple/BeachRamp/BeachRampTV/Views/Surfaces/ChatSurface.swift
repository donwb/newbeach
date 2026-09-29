import SwiftUI
import BeachStatus

/// The Ask pull surface: a question box over the prediction engine, in the
/// board's voice. Left, the latest answer — kicker · headline · detail and
/// only the rows that carry news — under the question that produced it.
/// Right, the controls: three suggested questions for the board's city (so
/// most asks need no typing), then the text field (the system keyboard
/// brings Siri Remote dictation and the iPhone keyboard prompt), or the key
/// field when the server wants a chat key. Not a chat: follow-ups keep
/// their context server-side, but only the newest answer is shown.
struct ChatSurface: View {
    @Bindable var session: ChatSession
    let focus: FocusState<RootFocus?>.Binding

    @State private var keyDraft = ""

    private let leftWidth: CGFloat = 1080
    private let gap: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 40) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    Text("Ask")
                        .tv(52, .extraBold, tracking: -0.03)
                        .foregroundStyle(TVInk.type)
                    Text(session.contextCity.map { "\($0) · the outlook, in its own words" } ?? "The outlook, in its own words")
                        .tvLabel()
                }
                Spacer(minLength: 0)
                SurfaceBackHint()
            }

            HStack(alignment: .top, spacing: gap) {
                answerColumn
                    .frame(width: leftWidth, alignment: .topLeading)
                    .focusSection()
                controls
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .focusSection()
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(TVInk.rule).frame(height: 2)
            }

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 24, leading: TVMetrics.sidePad,
                            bottom: 36, trailing: TVMetrics.sidePad))
    }

    // MARK: - Answer

    @ViewBuilder private var answerColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.isPending {
                Text("Checking the outlook…")
                    .tv(28, .semiBold)
                    .foregroundStyle(TVInk.inactive)
                    .padding(.top, 14)
            } else if let error = session.errorText, !session.needsKey {
                Text(error)
                    .tv(28, .semiBold)
                    .foregroundStyle(TVInk.typeDim)
                    .lineLimit(2)
                    .padding(.top, 14)
            } else if let reply = session.latestReply {
                if let question = session.latestQuestion {
                    Text(question)
                        .tv(24)
                        .foregroundStyle(TVInk.typeDim)
                        .lineLimit(1)
                        .padding(.top, 14)
                }
                answerBlock(reply: reply, sources: session.sources)
            } else {
                Text("Ask whether you can get on the beach in a city, whether the ramps will be open at a time this week, or which day looks best. Answers are the board's own outlook, in its own words.")
                    .tv(28)
                    .foregroundStyle(TVInk.typeDim)
                    .lineLimit(3)
                    .padding(.top, 14)
            }
        }
        .accessibilityIdentifier("chat.transcript")
    }

    private func answerBlock(reply: String, sources: [ChatSource]) -> some View {
        let (lead, rest) = AskPresentation.splitLead(reply)
        let rows = AskPresentation.newsRows(sources)
        let days = AskPresentation.days(sources)
        return VStack(alignment: .leading, spacing: 8) {
            if let kicker = AskPresentation.kicker(for: sources) {
                Text(kicker).tvLabel()
            }
            Text(lead)
                .tv(40, .extraBold, tracking: -0.02)
                .foregroundStyle(TVInk.type)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if !rest.isEmpty {
                Text(rest)
                    .tv(26)
                    .foregroundStyle(TVInk.typeMuted)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rows.prefix(4)) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            Text(row.name)
                                .tv(26, .semiBold)
                                .foregroundStyle(TVInk.type)
                                .frame(width: 260, alignment: .leading)
                            Text(row.state)
                                .tv(26, row.isClosed ? .bold : .regular)
                                .foregroundStyle(row.isClosed ? TVInk.closed : TVInk.typeDim)
                                .frame(width: 260, alignment: .leading)
                            Text(row.note)
                                .tv(24)
                                .foregroundStyle(TVInk.typeDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Rectangle().fill(TVInk.ruleHair).frame(height: 1) }
                    }
                }
                .padding(.top, 6)
            }
            if !days.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(days.prefix(4)) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String((d.weekday ?? d.date ?? "").prefix(3))).tvLabel(22)
                            Text((d.verdict ?? "").replacingOccurrences(of: "_", with: " "))
                                .tv(22, .semiBold)
                                .foregroundStyle(TVInk.typeDim)
                            Text(d.headline ?? "")
                                .tv(24, .semiBold)
                                .foregroundStyle(TVInk.type)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 6)
            }
        }
        .accessibilityIdentifier("chat.sourceCard")
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if session.needsKey {
            keyEntry
        } else if session.featureOff {
            Text(session.errorText ?? "Ask is switched off right now.")
                .tv(26)
                .foregroundStyle(TVInk.typeDim)
                .padding(.top, 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Try").tvLabel()
                    .padding(.top, 14)
                ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, question in
                    suggestionRow(index: index, question: question)
                }
                Text("Or ask").tvLabel()
                    .padding(.top, 10)
                TextField("Ask about a city, a ramp, or a time this week…", text: $session.draft)
                    .font(.archivo(26))
                    .foregroundStyle(TVInk.type)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .overlay(Rectangle().strokeBorder(
                        focus.wrappedValue == .chatInput ? TVInk.sand : TVInk.rule, lineWidth: 2))
                    .focused(focus, equals: .chatInput)
                    .onSubmit {
                        let text = session.draft
                        Task { await session.send(text) }
                    }
                    .disabled(session.isPending)
                    .accessibilityIdentifier("chat.input")
                Text("Select the field, then hold the mic button on the remote to speak.")
                    .tv(22)
                    .foregroundStyle(TVInk.inactive)
                    .lineLimit(2)
            }
        }
    }

    /// A suggested question as a focusable line: a sand bar and sand type
    /// on focus, no box.
    private func suggestionRow(index: Int, question: String) -> some View {
        let focused = focus.wrappedValue == .chatSuggestion(index)
        return Button {
            session.draft = question
            Task { await session.send(question) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(focused ? TVInk.sand : TVInk.rule)
                    .frame(width: 4)
                Text(question)
                    .tv(26, focused ? .semiBold : .regular)
                    .foregroundStyle(focused ? TVInk.sand : TVInk.type)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BareButtonStyle())
        .disabled(session.isPending)
        .focused(focus, equals: .chatSuggestion(index))
        .accessibilityIdentifier("chat.suggestion.\(index)")
    }

    /// Where the chat key goes — once per Apple TV (no iCloud Keychain here).
    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chat key").tvLabel()
                .padding(.top, 14)
            Text(session.errorText ?? "Ask is locked. Enter the chat key from the server once; it is kept on this Apple TV.")
                .tv(26)
                .foregroundStyle(TVInk.typeDim)
                .lineLimit(3)
            SecureField("Key", text: $keyDraft)
                .font(.archivo(26))
                .foregroundStyle(TVInk.type)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(Rectangle().strokeBorder(
                    focus.wrappedValue == .chatKeyField ? TVInk.sand : TVInk.rule, lineWidth: 2))
                .focused(focus, equals: .chatKeyField)
                .onSubmit(saveKey)
                .accessibilityIdentifier("chat.key.field")
            Button(action: saveKey) {
                Text("Save key")
                    .tv(26, .bold)
                    .foregroundStyle(focus.wrappedValue == .chatKeySave ? TVInk.onSand : TVInk.type)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(focus.wrappedValue == .chatKeySave ? TVInk.sand : .clear))
                    .overlay(Rectangle().strokeBorder(TVInk.sand, lineWidth: 2))
            }
            .buttonStyle(BareButtonStyle())
            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .focused(focus, equals: .chatKeySave)
            .accessibilityIdentifier("chat.key.save")
        }
    }

    private func saveKey() {
        session.saveKey(keyDraft)
        keyDraft = ""
        if !session.needsKey {
            DispatchQueue.main.async { focus.wrappedValue = .chatSuggestion(0) }
        }
    }
}

#if DEBUG
#Preview("Ask · answered", traits: .fixedLayout(width: 1920, height: 630)) {
    @Previewable @FocusState var focus: RootFocus?
    ChatSurface(session: PreviewFixtures.chatSession(answered: true), focus: $focus)
        .background(TVInk.ground)
}

#Preview("Ask · empty", traits: .fixedLayout(width: 1920, height: 630)) {
    @Previewable @FocusState var focus: RootFocus?
    ChatSurface(session: PreviewFixtures.chatSession(answered: false), focus: $focus)
        .background(TVInk.ground)
}

#Preview("Ask · needs key", traits: .fixedLayout(width: 1920, height: 630)) {
    @Previewable @FocusState var focus: RootFocus?
    ChatSurface(session: PreviewFixtures.chatSession(answered: false, key: nil), focus: $focus)
        .background(TVInk.ground)
}
#endif
