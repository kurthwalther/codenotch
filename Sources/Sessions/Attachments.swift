import AppKit
import UniformTypeIdentifiers

/// Files and images handed to a conversation, by drop or paste. Everything
/// ends up as a path, because a path is how the line carries it: Claude
/// Code opens what it is pointed at, images included.
enum Attachments {
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

    static func isImage(_ url: URL) -> Bool {
        imageTypes.contains(url.pathExtension.lowercased())
    }

    /// Where pasted images and dropped image data are written.
    static var dropsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let bundle = Bundle.main.bundleIdentifier ?? "com.vinz.codenotch"
        return caches.appendingPathComponent("\(bundle)/attachments", isDirectory: true)
    }

    /// Turns what was dropped or pasted into files, and hands back their
    /// URLs on the main thread. File URLs are used as they are; image data
    /// is written out as a PNG first.
    static func accept(_ providers: [NSItemProvider], _ deliver: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    add(url)
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? NSImage, let url = save(image) else { return }
                    add(url)
                }
            }
        }
        group.notify(queue: .main) { deliver(urls) }
    }

    /// An image written out as a PNG with a name that says where it came
    /// from and when.
    static func save(_ image: NSImage, now: Date = Date()) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let directory = dropsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("pasted-\(stamp).png")
        do { try png.write(to: url) } catch { return nil }
        return url
    }

    /// The line as sent: your words, then each path on a line of its own.
    static func compose(_ text: String, with attachments: [URL]) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return line }
        let paths = attachments.map(\.path).joined(separator: "\n")
        return line.isEmpty ? paths : line + "\n\n" + paths
    }
}
