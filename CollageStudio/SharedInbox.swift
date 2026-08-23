import Foundation
import SwiftUI

/// Reads images that the Share Extension has dropped into the App Group
/// container, so they can be added to the collage as if the user had picked
/// them via the "Add Images" button.
enum SharedInbox {

    static let appGroupId = "group.com.collagestudio.app"

    static var inboxDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("SharedImages", isDirectory: true)
    }

    /// Loads all pending shared images (oldest first) and clears the inbox.
    static func drainPendingImages() -> [PlatformImage] {
        guard let dir = inboxDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.creationDateKey]
              ), !files.isEmpty else { return [] }

        // Preserve the order in which the images were shared
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }

        var images: [PlatformImage] = []
        for url in sorted {
            if let data = try? Data(contentsOf: url),
               let img = PlatformImage(data: data) {
                images.append(img)
            }
            try? FileManager.default.removeItem(at: url)
        }
        return images
    }
}
