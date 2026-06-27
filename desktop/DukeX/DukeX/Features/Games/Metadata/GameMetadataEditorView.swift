import SwiftUI

struct GameMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let game: LibraryFile
    let save: (GameListMetadata) -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var year: String
    @State private var studio: String
    @State private var esrbRating: ESRBRating
    @State private var description: String

    init(game: LibraryFile,
         metadata: GameListMetadata?,
         save: @escaping (GameListMetadata) -> Void) {
        self.game = game
        self.save = save

        let metadata = metadata ?? .empty
        _title = State(initialValue: metadata.title)
        _subtitle = State(initialValue: metadata.subtitle)
        _year = State(initialValue: metadata.year)
        _studio = State(initialValue: metadata.studio)
        _esrbRating = State(initialValue: metadata.esrbRating)
        _description = State(initialValue: metadata.description)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full Title", text: $title)
                        .textInputAutocapitalization(.words)

                    TextField("Subtitle", text: $subtitle)
                        .textInputAutocapitalization(.words)

                    TextField("Year of Release", text: $year)
                        .keyboardType(.numberPad)

                    TextField("Studio Name", text: $studio)
                        .textInputAutocapitalization(.words)

                    Picker("ESRB Rating", selection: $esrbRating) {
                        ForEach(ESRBRating.allCases) { rating in
                            Text(rating.title).tag(rating)
                        }
                    }
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle(game.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(metadata)
                        dismiss()
                    }
                }
            }
        }
    }

    private var metadata: GameListMetadata {
        GameListMetadata(
            title: title,
            subtitle: subtitle,
            year: year,
            studio: studio,
            esrbRating: esrbRating,
            description: description
        )
    }
}
