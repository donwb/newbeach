import SwiftUI
import BeachStatus

/// The Ask pull surface: a question box over the prediction engine. Left,
/// the conversation — the last few turns and, under the newest answer, the
/// engine fact it rested on. Right, the controls: three suggested questions
/// for the focused ramp (so most asks need no typing), then the text field
/// (the system keyboard brings Siri Remote dictation and the iPhone keyboard
/// prompt), or the key field when the server wants a chat key. Every answer
/// is server copy rendered verbatim; the one red thing is a live closure.
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
                    Text(session.contextRamp.map { "About \($0.rampDisplayName)" } ?? "Any ramp · this week")
                        .tvLabel()
                }
                Spacer(minLength: 0)
                SurfaceBackHint()
            }

            HStack(alignment: .top, spacing: gap) {
                conversation
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

    // MARK: - Conversation

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 18) {
            if session.turns.isEmpty {
                Text("Ask whether a ramp will be open at a time this week, or which day looks best. Answers are the board's own outlook, in its own words.")
                    .tv(28)
                    .foregroundStyle(TVInk.typeDim)
                    .lineLimit(3)
                    .padding(.top, 14)
            }
            ForEach(session.turns.suffix(4)) { turn in
                turnRow(turn)
            }
            if let last = session.turns.last, last.role == .assistant, !session.sources.isEmpty {
                sourceCard
            }
            if session.isPending {
                Text("Checking the outlook…")
                    .tv(26, .semiBold)
                    .foregroundStyle(TVInk.inactive)
            }
            if let error = session.errorText, !session.needsKey {
                Text(error)
                    .tv(26, .semiBold)
                    .foregroundStyle(TVInk.typeDim)
                    .lineLimit(2)
            }
        }
        .padding(.top, 10)
        .accessibilityIdentifier("chat.transcript")
    }

    private func turnRow(_ turn: ChatTurn) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(turn.role == .user ? "You" : "Outlook")
                .tvLabel(22)
                .frame(width: 120, alignment: .leading)
                .padding(.top, 6)
            Text(turn.text)
                .tv(turn.role == .user ? 28 : 30, turn.role == .user ? .regular : .semiBold)
                .foregroundStyle(turn.role == .user ? TVInk.typeDim : TVInk.type)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The engine fact under the newest answer: a ramp read, or the days.
    private var sourceCard: some View {
        let ramps = session.sources.filter { $0.kind == "ramp_outlook" }
        let days = session.sources.filter { $0.kind == "weekend_day" }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(ramps.prefix(2)) { s in
                HStack(alignment: .top, spacing: 16) {
                    Rectangle()
                        .fill(s.isClosedNow ? TVInk.closed : TVInk.sand)
                        .frame(width: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text([s.name, s.atLabel].compactMap { $0 }.joined(separator: " · "))
                            .tvLabel(22)
                        if let headline = s.headline {
                            Text(headline)
                                .tv(28, .semiBold)
                                .foregroundStyle(TVInk.type)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if let detail = s.detail, !detail.isEmpty {
                            Text(detail)
                                .tv(24)
                                .foregroundStyle(TVInk.typeDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            if !days.isEmpty {
                HStack(spacing: 24) {
                    ForEach(days.prefix(4)) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.weekday ?? d.date ?? "").tvLabel(22)
                            Text(d.headline ?? "")
                                .tv(24, .semiBold)
                                .foregroundStyle(TVInk.type)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.leading, 138)
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
            VStack(alignment: .leading, spacing: 14) {
                Text("Try one").tvLabel()
                    .padding(.top, 14)
                ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, question in
                    suggestionButton(index: index, question: question)
                }
                Text("Or ask").tvLabel()
                    .padding(.top, 10)
                TextField("Ask about a ramp…", text: $session.draft)
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
            }
        }
    }

    private func suggestionButton(index: Int, question: String) -> some View {
        let focused = focus.wrappedValue == .chatSuggestion(index)
        return Button {
            Task { await session.send(question) }
        } label: {
            HStack(spacing: 14) {
                Text(question)
                    .tv(26, .semiBold)
                    .foregroundStyle(focused ? TVInk.onSand : TVInk.type)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("›")
                    .tv(26, .bold)
                    .foregroundStyle(focused ? TVInk.onSand : TVInk.sand)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Rectangle().fill(focused ? TVInk.sand : .clear))
            .overlay(Rectangle().strokeBorder(focused ? TVInk.sand : TVInk.rule, lineWidth: 2))
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
