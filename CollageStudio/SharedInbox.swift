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

    /// Loads the pending shared images (oldest first), skipping files already
    /// loaded and still waiting to be added. Files are kept until `remove`
    /// is called once the photos are in the collage (or discarded), so a
    /// crash before then doesn't lose them; files that don't decode go now.
    /// Off the main thread: decoding up to 30 photos takes a while.
    nonisolated static func pendingImages(skipping known: Set<URL> = []) -> [(url: URL, image: CollageImage)] {
        guard let dir = inboxDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.creationDateKey]
              ), !files.isEmpty else { return [] }

        // Preserve the order in which the images were shared
        let sorted = files.filter { !known.contains($0.standardizedFileURL) }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }

        var images: [(url: URL, image: CollageImage)] = []
        for url in sorted {
            autoreleasepool {
                // Kept compressed, the working copies made from the data.
                if let data = try? Data(contentsOf: url), let img = CollageImage(data: data) {
                    images.append((url.standardizedFileURL, img))
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        return images
    }

    /// Deletes inbox files whose photos have been added (or discarded).
    nonisolated static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}
