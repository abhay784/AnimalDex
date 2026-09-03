import UIKit
import os

/// Catch photos on disk, addressed by filename.
///
/// Application Support rather than Caches: the system may evict Caches under
/// pressure, and a dex entry whose photo vanished is a broken entry.
struct PhotoStore {
    static let shared = PhotoStore()

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "photos")

    private var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "CatchPhotos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    func save(_ image: UIImage, id: UUID = UUID()) throws -> String {
        let filename = "\(id.uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: directory.appending(path: filename), options: .atomic)
        return filename
    }

    func load(_ filename: String) -> UIImage? {
        guard !filename.isEmpty else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: filename).path(percentEncoded: false))
    }

    func delete(_ filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }
}
