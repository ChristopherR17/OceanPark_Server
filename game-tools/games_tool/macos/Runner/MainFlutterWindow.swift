import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var activeSecurityScopedURLs: [String: URL] = [:]

  private func createSecurityScopedBookmark(path: String) throws -> String {
    let normalizedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    let bookmarkData = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return bookmarkData.base64EncodedString()
  }

  private func resolveSecurityScopedBookmark(bookmarkBase64: String) throws -> [String: String] {
    guard let bookmarkData = Data(base64Encoded: bookmarkBase64) else {
      throw NSError(
        domain: "games_tool.security_bookmarks",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid bookmark payload"]
      )
    }

    var isStale = false
    let resolvedURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    let resolvedPath = resolvedURL.path
    let pathKey = (resolvedPath as NSString).standardizingPath

    if activeSecurityScopedURLs[pathKey] == nil {
      let started = resolvedURL.startAccessingSecurityScopedResource()
      if started {
        activeSecurityScopedURLs[pathKey] = resolvedURL
      } else {
        throw NSError(
          domain: "games_tool.security_bookmarks",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped resource"]
        )
      }
    }

    var refreshedBookmark = bookmarkBase64
    if isStale {
      let refreshedData = try resolvedURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      refreshedBookmark = refreshedData.base64EncodedString()
    }

    return [
      "path": pathKey,
      "bookmark": refreshedBookmark,
    ]
  }

  deinit {
    for (_, url) in activeSecurityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let securityBookmarksChannel = FlutterMethodChannel(
      name: "games_tool/security_bookmarks",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    securityBookmarksChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "disposed",
            message: "Window has been disposed",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "createBookmark":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          result(
            FlutterError(
              code: "invalid_args",
              message: "Missing or invalid path",
              details: nil
            )
          )
          return
        }

        do {
          let bookmark = try self.createSecurityScopedBookmark(path: path)
          result(bookmark)
        } catch {
          result(
            FlutterError(
              code: "create_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }

      case "resolveBookmark":
        guard
          let args = call.arguments as? [String: Any],
          let bookmark = args["bookmark"] as? String,
          !bookmark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          result(
            FlutterError(
              code: "invalid_args",
              message: "Missing or invalid bookmark",
              details: nil
            )
          )
          return
        }

        do {
          let payload = try self.resolveSecurityScopedBookmark(bookmarkBase64: bookmark)
          result(payload)
        } catch {
          result(
            FlutterError(
              code: "resolve_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
