//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Mario Poje on 18.07.2026..
//

import UIKit
import UniformTypeIdentifiers

/// Receives images shared from other apps (e.g. Photos) and saves them into
/// the App Group container. The main app picks them up the next time it
/// becomes active and adds them to the collage, exactly like images added
/// via the "Add Images" button.
class ShareViewController: UIViewController {

    private let appGroupId = "group.com.collagestudio.app"
    private let hudLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        showHUD()
        processAttachments()
    }

    // MARK: - Attachment processing

    private func processAttachments() {
        guard let inbox = Self.inboxURL(appGroupId: appGroupId),
              let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }

        let providers = items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard !providers.isEmpty else {
            complete()
            return
        }

        let group = DispatchGroup()
        var savedCount = 0
        let countLock = NSLock()
        for provider in providers {
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                // The temp file is deleted when this handler returns, so copy
                // it into the shared container synchronously.
                let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
                let dest = inbox.appendingPathComponent(UUID().uuidString + "." + ext)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    countLock.lock()
                    savedCount += 1
                    countLock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // Show a short confirmation, then hand off to the main app.
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            self.hudLabel.text = savedCount == 1
                ? "Added 1 photo ✓"
                : "Added \(savedCount) photos ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.openHostApp()
                self.complete()
            }
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens the main Collage Studio app via its custom URL scheme.
    /// `UIApplication.shared.open` is unavailable in extensions, so walk the
    /// responder chain to the application object and invoke the modern
    /// `openURL:options:completionHandler:` through its method pointer.
    /// (The old `openURL:` selector is deprecated and iOS force-returns NO.)
    private func openHostApp() {
        guard let url = URL(string: "collagestudio://import") else { return }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            // Only invoke on the actual UIApplication — UIWindowScene responds
            // to the same selector name but expects an options *object*
            // (UISceneOpenExternalURLOptions) instead of a dictionary, and
            // crashes if given one.
            if r is UIApplication, r.responds(to: selector) {
                typealias OpenURLFunction = @convention(c) (NSObject, Selector, NSURL, NSDictionary, UnsafeRawPointer?) -> Void
                let imp = r.method(for: selector)
                let open = unsafeBitCast(imp, to: OpenURLFunction.self)
                open(r as NSObject, selector, url as NSURL, [:] as NSDictionary, nil)
                return
            }
            responder = r.next
        }
    }

    // MARK: - Shared inbox

    static func inboxURL(appGroupId: String) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let dir = container.appendingPathComponent("SharedImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - HUD

    private func showHUD() {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false

        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        hudLabel.text = "Adding to Collage Studio…"
        hudLabel.font = .preferredFont(forTextStyle: .subheadline)
        hudLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(spinner)
        card.addSubview(hudLabel)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            hudLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 10),
            hudLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            hudLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            hudLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
    }
}
