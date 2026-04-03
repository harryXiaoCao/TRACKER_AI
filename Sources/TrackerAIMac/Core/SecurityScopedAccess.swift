import Foundation

final class SecurityScopedURLLease {
    let url: URL

    private let accessedURL: URL
    private let didStartAccessing: Bool

    init(url: URL, accessedURL: URL, didStartAccessing: Bool) {
        self.url = url
        self.accessedURL = accessedURL
        self.didStartAccessing = didStartAccessing
    }

    deinit {
        guard didStartAccessing else { return }
        accessedURL.stopAccessingSecurityScopedResource()
    }
}

enum SecurityScopedBookmarks {
    static func makeBookmark(for url: URL) -> String? {
        guard url.isFileURL else { return nil }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data.base64EncodedString()
        } catch {
            return nil
        }
    }

    static func makeDirectoryBookmark(for url: URL) -> String? {
        let directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        return makeBookmark(for: directoryURL)
    }

    static func access(url: URL, bookmark: String? = nil) -> SecurityScopedURLLease? {
        guard url.isFileURL else { return nil }
        let scopedURL = resolvedBookmarkURL(from: bookmark) ?? url
        let didStartAccessing = scopedURL.startAccessingSecurityScopedResource()
        return SecurityScopedURLLease(
            url: url,
            accessedURL: scopedURL,
            didStartAccessing: didStartAccessing
        )
    }

    static func resolvedFileURL(path: String, bookmark: String? = nil) -> URL {
        if let bookmarkedURL = resolvedBookmarkURL(from: bookmark), bookmarkedURL.path == path {
            return bookmarkedURL
        }
        return URL(fileURLWithPath: path)
    }

    private static func resolvedBookmarkURL(from bookmark: String?) -> URL? {
        guard
            let bookmark,
            let data = Data(base64Encoded: bookmark)
        else {
            return nil
        }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
