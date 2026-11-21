import BookBrainCore
import SwiftUI

struct APISettings: View {
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var provider: APIProvider
  @State private var modelID: String
  @State private var key = ""
  @State private var catalog: [APIModel] = []
  @State private var error: String?
  @State private var confirmRemoval = false

  init(model: AppModel) {
    self.model = model
    _provider = State(initialValue: model.apiModel?.provider ?? .anthropic)
    _modelID = State(initialValue: model.apiModel?.id ?? "")
  }

  private var choice: APIModel? {
    catalog.first { $0.provider == provider && $0.id == modelID }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("API settings").font(.headline)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Picker("Provider", selection: $provider) {
            ForEach(APIProvider.allCases, id: \.self) { Text($0.name).tag($0) }
          }
          .disabled(!model.canChangeProvider)
          .onChange(of: provider) { _, _ in
            modelID = ""
            key = ""
            error = nil
          }
          Picker("Model", selection: $modelID) {
            Text("Choose a model").tag("")
            ForEach(catalog.filter { $0.provider == provider }, id: \.id) { item in
              Text(item.name == item.id ? item.id : "\(item.name) · \(item.id)").tag(item.id)
            }
          }.disabled(!model.canChangeProvider)
          if let choice, !choice.vision {
            Text("This model accepts text only.").font(.caption)
          }
          SecureField("API key", text: $key)
          Text("Leave blank to use your saved key. Keys are stored in this Mac’s Keychain.")
            .font(.caption)
          Button("Remove saved key…") { confirmRemoval = true }.buttonStyle(.link)
          Text(
            "This chat sends questions and attachments directly to \(provider.name). API usage is billed by the provider."
          )
          .font(.caption)
          if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          guard let choice else { return }
          do {
            try model.configureAPI(
              choice, newKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.keyboardShortcut(.defaultAction).disabled(choice == nil)
      }
    }
    .padding()
    .onAppear {
      do {
        guard let url = Bundle.main.url(forResource: "PiModels", withExtension: "json") else {
          throw BookBrainError.message("Build and open Book Brain.app to use API mode.")
        }
        catalog = try JSONDecoder().decode([APIModel].self, from: Data(contentsOf: url))
        if let saved = model.apiModel,
          !catalog.contains(where: { $0.provider == saved.provider && $0.id == saved.id })
        {
          error =
            "This model is no longer in the catalog. Start a new chat to select another model."
        }
      } catch { self.error = error.localizedDescription }
    }
    .confirmationDialog(
      "Remove the saved \(provider.name) key for all chats?", isPresented: $confirmRemoval
    ) {
      Button("Remove key", role: .destructive) {
        do {
          try APIKeyStore.remove(for: provider)
          key = ""
          error = "Saved key removed."
        } catch { self.error = error.localizedDescription }
      }
    }
  }
}
