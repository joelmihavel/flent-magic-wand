import AppKit
import Foundation

/// LRU in-memory image cache to avoid reprocessing identical inputs.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()

    init(countLimit: Int = 20) {
        cache.countLimit = countLimit
    }

    func image(forKey key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key as NSString)
    }

    /// Generate a cache key from image data via a fast hash.
    static func key(for image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation else { return nil }
        // Simple hash — not cryptographic, just for dedup
        var hasher = Hasher()
        hasher.combine(tiff)
        return String(hasher.finalize())
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
}
