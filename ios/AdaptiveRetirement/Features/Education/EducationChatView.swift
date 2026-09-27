import Foundation
import SwiftUI

private struct EducationTurn: Encodable {
    let role: String
    let content: String
}

private struct EducationRequest: Encodable {
    let message: String
    let history: [EducationTurn]
}

struct EducationSource: Decodable, Hashable {
    let title: String
    let url: String
}

struct EducationReply: Decodable {
    let answer: String
    let mode: String
    let topic: String
    let sources: [EducationSource]
}

struct EducationMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let reply: EducationReply?
}

private enum EducationChatFailure: Error {
    case server(String)
}

/// Sends the question and recent chat through the backend. No app profile or account state is attached.
struct EducationChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var messages: [EducationMessage]
    @Binding var draft: String
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var requestTask: Task<Void, Never>?

    private let starters = [
        "What is a target-date fund?",
        "Why does an employer match matter?",
        "How do fund fees affect savings?",
        "What does investment risk mean?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty {
                                introduction
                                starterQuestions
                            }
                            ForEach(messages) { message in
                                messageBubble(message)
                            }
                            if isSending {
                                HStack(spacing: 9) {
                                    ProgressView().tint(Palette.accent)
                                    Text("Thinking about your question…")
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                        .padding(.horizontal, Space.gutter)
                        .padding(.vertical, Space.l)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    }
                    .onChange(of: isSending) { _, _ in
                        withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    }
                }
                composer
            }
            .background(Palette.page)
            .navigationTitle("Adaptive guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear { requestTask?.cancel() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s on your mind?")
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
            Text("Make sense of retirement, one question at a time. Explore matching, funds, fees, and risk.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.l)
    }

    private var starterQuestions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TRY A QUESTION")
                .font(TypeScale.eyebrow)
                .foregroundStyle(Palette.textCaption)
            ForEach(starters, id: \.self) { question in
                Button { ask(question) } label: {
                    HStack(spacing: 16) {
                        Text(question)
                            .font(TypeScale.label)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(Palette.accent)
                    }
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
                }
                .disabled(isSending)
            }
        }
    }

    private func messageBubble(_ message: EducationMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 9) {
                if message.role != "user" {
                Text("ADAPTIVE GUIDE")
                    .font(TypeScale.eyebrow)
                    .foregroundStyle(Palette.accent)
                }
                Text(message.content)
                    .font(TypeScale.bodyRegular)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityLabel(message.role == "user" ? "You: \(message.content)" : message.content)
                if let reply = message.reply {
                    let links = reply.sources.filter { URL(string: $0.url)?.scheme == "https" }
                    if links.isEmpty {
                        Text(originLabel(reply))
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textCaption)
                    } else {
                        DisclosureGroup {
                            ForEach(links, id: \.self) { source in
                                if let url = URL(string: source.url) {
                                    Link(source.title, destination: url)
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Palette.accent)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        } label: {
                            Text("\(originLabel(reply)) · References")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.textCaption)
                        }
                    }
                }
            }
            .padding(message.role == "user" ? 16 : 0)
            .background(message.role == "user" ? Palette.accent.opacity(0.09) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.vertical, 8)
            if message.role != "user" { Spacer(minLength: 36) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(TypeScale.caption)
                    .foregroundStyle(Color(hex: 0xE8A297))
            }
            HStack(spacing: 10) {
                TextField("Ask a retirement question…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .font(TypeScale.bodyRegular)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(12)
                    .disabled(isSending)
                    .onChange(of: draft) { _, value in
                        if value.count > 500 { draft = String(value.prefix(500)) }
                    }
                Button { ask(draft) } label: {
                    Image(systemName: "arrow.up")
                    .font(TypeScale.labelMedium)
                    .foregroundStyle(Palette.page)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent, in: Circle())
                }
                    .accessibilityLabel("Send question")
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(6)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text("Questions and recent chat are sent to Google Gemini. Educational guidance. Keep personal details private.")
                .font(TypeScale.caption)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.page)
    }

    private func originLabel(_ reply: EducationReply) -> String {
        if reply.mode == "ai" { return "AI-generated explanation" }
        if reply.topic == "out_of_scope" { return "Built-in answer" }
        return "Built-in answer · Gemini unavailable or question restricted"
    }

    @MainActor
    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 500, !isSending else { return }
        guard let base = URL(string: store.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme == "https" else {
            errorMessage = "Connect to the backend to ask a question."
            return
        }
        let history = messages.suffix(4).map {
            EducationTurn(role: $0.role, content: String($0.content.prefix(500)))
        }
        let userMessage = EducationMessage(role: "user", content: question, reply: nil)
        messages.append(userMessage)
        draft = ""
        errorMessage = nil
        isSending = true
        requestTask = Task { @MainActor in
            do {
                var request = URLRequest(url: base.appendingPathComponent("v1/education/chat"),
                                         timeoutInterval: 16)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
                if !AppStore.defaultDemoKey.isEmpty {
                    request.setValue(AppStore.defaultDemoKey, forHTTPHeaderField: "X-Demo-Key")
                }
                request.httpBody = try JSONEncoder().encode(EducationRequest(message: question, history: history))
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(http.statusCode) else {
                    if let envelope = try? JSONDecoder().decode(API.ErrorEnvelope.self, from: data) {
                        throw EducationChatFailure.server(envelope.error.message)
                    }
                    throw URLError(.badServerResponse)
                }
                let reply = try JSONDecoder().decode(EducationReply.self, from: data)
                try Task.checkCancellation()
                messages.append(EducationMessage(role: "assistant", content: reply.answer, reply: reply))
            } catch {
                let wasCancelled = Task.isCancelled
                messages.removeAll { $0.id == userMessage.id }
                draft = question
                if !wasCancelled {
                    if let chatError = error as? EducationChatFailure,
                       case .server(let message) = chatError {
                        errorMessage = message
                    } else {
                        errorMessage = "Could not reach the learning assistant. Check the backend and try again."
                    }
                }
            }
            isSending = false
            requestTask = nil
        }
    }
}
