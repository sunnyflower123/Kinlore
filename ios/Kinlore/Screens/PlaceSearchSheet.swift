import SwiftUI

/// "Etsi nimellä": a place found by what somebody types, on the family's map.
///
/// A tap on the map is how somebody who has stood in the yard says where it
/// is. This is the way for everybody else — a road on an old envelope, a
/// village whose name somebody remembers — and it is the only way VoiceOver
/// has of placing a point at all: the map editor admits that placing a point
/// inside a landscape is visual work (`PlacesMapScreen`), and here the
/// answers are rows of words, choosing one is a button, and "Tallenna" under
/// the map is another.
///
/// A chosen answer is a proposal and not a save. The sheet closes on the map
/// with the point drawn where "Tallenna" would put it, at the precision the
/// answer carried — a municipality stays a circle and a province a larger
/// one (rule 5) — so that the answer is seen before it becomes the
/// archive's.
///
/// The field opens holding the place's name and the search runs at once,
/// because that name is the likeliest thing anybody would type; it is filled
/// but not focused, for `NameSheet`'s reason — a keyboard raised on appear
/// covers the rows at the largest text size. What leaves the phone is the
/// typed words and nothing else (`PlaceLookup`), and nothing here asks where
/// the phone is.
struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Takes the chosen answer; the sheet closes itself afterwards.
    let choose: (PlaceLookup.Found) -> Void

    @State private var query: String
    @State private var results: [PlaceLookup.Found] = []
    @State private var phase = Phase.idle
    @FocusState private var isTyping: Bool

    private enum Phase { case idle, searching, answered, failed }

    init(query: String, choose: @escaping (PlaceLookup.Found) -> Void) {
        _query = State(initialValue: query)
        self.choose = choose
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        // Wrapping, as `AskQuestionSheet`'s field does. On
                        // one line the audit called it clipped text at both
                        // sizes, 26 points tall or 60, and not once it
                        // wrapped; at the largest size the hint alone is
                        // about twice the field's width.
                        TextField("Etsi kylä, tila tai osoite", text: $query, axis: .vertical)
                            .font(.title3)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($isTyping)
                            .onSubmit { Task { await search() } }
                            // A field that wraps takes the return key as a
                            // new line, so a new line is read as "Hae".
                            .onChange(of: query) { _, typed in
                                guard typed.contains(where: \.isNewline) else { return }
                                query = typed.filter { !$0.isNewline }
                                isTyping = false
                                Task { await search() }
                            }
                            // On the field and not the row, as in
                            // `CorrectNameSheet`: the field is the target.
                            .elderTapTarget()
                        // The field opens full, and somebody who wants to type
                        // a road instead of the name should not have to take
                        // the name away a letter at a time.
                        if !query.isEmpty {
                            Button {
                                query = ""
                                isTyping = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Elder.supporting)
                                    .elderTapTarget()
                            }
                            // Borderless, because a form row with a plain
                            // button in it hands the whole row's tap to the
                            // button, the field's included.
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Tyhjennä haku")
                        }
                    }
                    Button {
                        Task { await search() }
                    } label: {
                        Text("Hae")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .elderTapTarget()
                    .disabled(trimmed.isEmpty || phase == .searching)
                }

                switch phase {
                case .idle:
                    EmptyView()
                case .searching:
                    Section {
                        ProgressView("Haetaan…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .elderTapTarget()
                    }
                case .failed:
                    // What stays possible, and not only what went wrong: the
                    // map under this sheet still takes a tap without a network.
                    Section { failure }
                case .answered where results.isEmpty:
                    Section {
                        Text("Tällä nimellä ei löytynyt paikkaa. Voit kokeilla toista nimeä tai napauttaa kohdan kartalta.")
                            .elderBody()
                    }
                case .answered:
                    Section {
                        ForEach(results) { found in
                            Button {
                                choose(found)
                                dismiss()
                            } label: {
                                row(found)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Näyttää kohdan kartalla ennen tallennusta.")
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Peruuta")
                            .frame(maxWidth: .infinity)
                    }
                    // Ink, for `NameSheet`'s reason: *Hae* keeps the accent.
                    .foregroundStyle(Color.primary)
                    .elderTapTarget()
                }
            }
            // Short, for the unplaced list's reason: a navigation title does
            // not grow with Dynamic Type and cannot wrap.
            .navigationTitle("Etsi nimellä")
            .navigationBarTitleDisplayMode(.inline)
            .elderSurface()
        }
        .task {
            if !trimmed.isEmpty { await search() }
        }
    }

    /// The sign beside the words, or above them once the words need the row's
    /// whole width. Not a `Label`: one here was the audit's "Text clipped" at
    /// both sizes (25 Sep 2026). The sign is decoration and the sentence is
    /// the content, as in the Tell screen's `FailureView`.
    private var failure: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text("Haku ei onnistunut. Voit napauttaa kohdan kartalta.")
                .elderBody()
        }
        .foregroundStyle(Elder.proposal)
    }

    /// An answer as the gazetteer names it, with the line under the name that
    /// tells two of the same name apart: the municipality under a road, the
    /// province under a municipality.
    private func row(_ found: PlaceLookup.Found) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: found.name)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = found.detail {
                Text(verbatim: detail)
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .elderTapTarget()
    }

    private func search() async {
        guard !trimmed.isEmpty, phase != .searching else { return }
        phase = .searching
        if let found = await PlaceLookup.search(trimmed) {
            results = found
            phase = .answered
        } else {
            results = []
            phase = .failed
        }
    }
}
