import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Social

/// Точка входа Share Extension (см. NSExtensionPrincipalClass в Info.plist).
/// Расширение — отдельный процесс от основного приложения, поэтому здесь
/// НЕТ доступа к APIClient/SessionStore/Keychain основного таргета напрямую.
/// Единственный канал наружу — App Group (см. SharedContainer.swift,
/// продублирован здесь как отдельный файл таргета, см. ниже).
final class ShareViewController: UIViewController {
    private var extractedText: String = ""
    private var isLoadingContent = true

    override func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(rootView: ShareRootView(
            isLoading: true,
            onCancel: { [weak self] in self?.finish(canceled: true) },
            onPost: { [weak self] text in self?.savedAndFinish(text: text) }
        ))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hostingController = hosting

        Task { await extractSharedContent() }
    }

    private var hostingController: UIHostingController<ShareRootView>?

    /// Достаёт текст/URL из NSExtensionItem. Приоритет: сначала public.url
    /// (ссылка — это самый частый кейс "поделиться из Safari/другого
    /// приложения"), затем public.plain-text, затем комбинируем оба, если
    /// пришли одновременно (например текст + ссылка из Safari "Поделиться").
    private func extractSharedContent() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            updateContent(text: "", loading: false)
            return
        }

        var collectedURL: String?
        var collectedText: String?

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadItem(provider, type: UTType.url.identifier) as? URL {
                        collectedURL = url.absoluteString
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await loadItem(provider, type: UTType.plainText.identifier) as? String {
                        collectedText = text
                    }
                }
            }
        }

        let combined = [collectedText, collectedURL].compactMap { $0 }.joined(separator: "\n\n")
        updateContent(text: combined, loading: false)
    }

    private func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item) }
            }
        }
    }

    private func updateContent(text: String, loading: Bool) {
        extractedText = text
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hostingController?.rootView = ShareRootView(
                isLoading: loading,
                prefillText: text,
                onCancel: { [weak self] in self?.finish(canceled: true) },
                onPost: { [weak self] finalText in self?.savedAndFinish(text: finalText) }
            )
        }
    }

    private func savedAndFinish(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { finish(canceled: true); return }
        SharedContainer.savePendingShare(text: trimmed)
        finish(canceled: false)
    }

    private func finish(canceled: Bool) {
        if canceled {
            extensionContext?.cancelRequest(withError: NSError(domain: "ru.bleyzos.itdo.share", code: 0))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

/// Минимальный UI расширения: показывает, что будет опубликовано, даёт
/// поправить текст и подтвердить. Публикация фактически произойдёт не
/// здесь, а в основном приложении (см. ITDOApp.swift → consumePendingShare),
/// потому что у расширения нет собственной авторизованной сессии/APIClient.
private struct ShareRootView: View {
    let isLoading: Bool
    var prefillText: String = ""
    let onCancel: () -> Void
    let onPost: (String) -> Void

    @State private var text: String = ""
    @State private var didPrefill = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Поделиться в ITDO")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))

                    Spacer()
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") { onPost(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onChange(of: prefillText) { newValue in
            guard !didPrefill, !newValue.isEmpty else { return }
            text = newValue
            didPrefill = true
        }
    }
}
