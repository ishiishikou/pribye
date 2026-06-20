import SwiftUI
import UIKit

struct AIExperimentView: View {
  @State private var prompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
  @State private var ocrText = ""
  @State private var responseText = ""
  @State private var errorMessage: String?
  @State private var isSending = false

  private let chatService: AppleIntelligenceChatService

  init(chatService: AppleIntelligenceChatService = AppleIntelligenceChatService()) {
    self.chatService = chatService
  }

  private var canSend: Bool {
    !isSending &&
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    List {
      Section("プロンプト") {
        TextEditor(text: $prompt)
          .frame(minHeight: 220)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        HStack {
          Button {
            prompt = FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions
          } label: {
            Label("既定に戻す", systemImage: "arrow.counterclockwise")
          }
          .disabled(prompt == FoundationModelsDocumentAnalyzer.defaultTaskExtractionInstructions)

          Spacer()

          Button {
            UIPasteboard.general.string = prompt
          } label: {
            Label("コピー", systemImage: "doc.on.doc")
          }
          .disabled(prompt.isEmpty)
        }
      }

      Section("OCR文章") {
        TextEditor(text: $ocrText)
          .frame(minHeight: 180)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        HStack {
          Button {
            ocrText = ""
          } label: {
            Label("クリア", systemImage: "xmark.circle")
          }
          .disabled(ocrText.isEmpty)

          Spacer()

          Button {
            UIPasteboard.general.string = ocrText
          } label: {
            Label("コピー", systemImage: "doc.on.doc")
          }
          .disabled(ocrText.isEmpty)
        }
      }

      Section {
        Button {
          Task { await sendPrompt() }
        } label: {
          if isSending {
            ProgressView()
          } else {
            Label("送信", systemImage: "paperplane")
          }
        }
        .disabled(!canSend)

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      Section("回答") {
        if responseText.isEmpty {
          ContentUnavailableView("回答はまだありません", systemImage: "bubble.left")
        } else {
          Text(responseText)
            .textSelection(.enabled)

          HStack {
            Button {
              responseText = ""
            } label: {
              Label("クリア", systemImage: "xmark.circle")
            }

            Spacer()

            Button {
              UIPasteboard.general.string = responseText
            } label: {
              Label("コピー", systemImage: "doc.on.doc")
            }
          }
        }
      }
    }
    .navigationTitle("AI実験")
  }

  @MainActor
  private func sendPrompt() async {
    guard canSend else {
      return
    }

    isSending = true
    errorMessage = nil
    responseText = ""
    defer { isSending = false }

    do {
      responseText = try await chatService.respond(prompt: prompt, ocrText: ocrText)
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? "Apple Intelligenceの実行に失敗しました。"
    }
  }
}
