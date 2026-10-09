import Flutter
import UIKit
import UniformTypeIdentifiers

/// 'fitapp/backup': a folder the person picks once in the Files app (on the
/// iPhone, iCloud Drive or another storage app), which automatic backups are
/// written to. The folder is remembered as a security-scoped bookmark; the
/// "uri" the app stores is that bookmark in base64.
final class BackupChannel: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  private let queue = DispatchQueue(label: "pumpandplate.backup")

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let tree = args["tree"] as? String ?? ""
    switch call.method {
    case "pick":
      pick(result)
    case "check":
      queue.async { pumpReply(result, self.check(tree)) }
    case "write":
      let name = args["name"] as? String ?? ""
      let path = args["path"] as? String ?? ""
      queue.async {
        do {
          pumpReply(result, try self.write(tree: tree, name: name, path: path))
        } catch {
          pumpReply(result, FlutterError(code: "write", message: error.localizedDescription, details: nil))
        }
      }
    case "list":
      queue.async {
        do {
          pumpReply(result, try self.list(tree))
        } catch {
          pumpReply(result, FlutterError(code: "list", message: error.localizedDescription, details: nil))
        }
      }
    case "delete":
      let id = args["id"] as? String ?? ""
      queue.async {
        do {
          try self.delete(tree: tree, id: id)
          pumpReply(result, nil)
        } catch {
          pumpReply(result, FlutterError(code: "delete", message: error.localizedDescription, details: nil))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Picking

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil, let top = pumpTopViewController() else {
      result(nil)
      return
    }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let allowed = url.startAccessingSecurityScopedResource()
    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result(["uri": bookmark.base64EncodedString(), "name": url.lastPathComponent])
    } catch {
      result(FlutterError(code: "pick", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending
    pending = nil
    result?(nil)
  }

  // MARK: Using the folder

  private func resolve(_ tree: String) -> URL? {
    guard let data = Data(base64Encoded: tree) else { return nil }
    var stale = false
    return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
  }

  /// Runs [body] with permission to use the folder.
  private func withFolder<T>(_ tree: String, _ body: (URL) throws -> T) throws -> T {
    guard let folder = resolve(tree) else {
      throw NSError(
        domain: "PumpAndPlate", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The backup folder can't be found. Pick it again in Settings."])
    }
    let allowed = folder.startAccessingSecurityScopedResource()
    defer { if allowed { folder.stopAccessingSecurityScopedResource() } }
    return try body(folder)
  }

  private func check(_ tree: String) -> Bool {
    (try? withFolder(tree) { folder -> Bool in
      var isDir: ObjCBool = false
      return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue
    }) ?? false
  }

  private func write(tree: String, name: String, path: String) throws -> Int {
    try withFolder(tree) { folder -> Int in
      let source = URL(fileURLWithPath: path)
      let target = folder.appendingPathComponent(name)
      var coordinatorError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinatorError) { url in
        do {
          if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
          }
          try FileManager.default.copyItem(at: source, to: url)
        } catch {
          writeError = error
        }
      }
      if let e = coordinatorError { throw e }
      if let e = writeError { throw e }
      let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
      return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
  }

  private func list(_ tree: String) throws -> [[String: String]] {
    try withFolder(tree) { folder -> [[String: String]] in
      let items = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
      return items.compactMap { url in
        let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
        return regular ? ["id": url.lastPathComponent, "name": url.lastPathComponent] : nil
      }
    }
  }

  private func delete(tree: String, id: String) throws {
    // Only plain file names: never anything outside the folder.
    guard !id.isEmpty, !id.contains("/"), id != "..", id != "." else { return }
    try withFolder(tree) { folder -> Void in
      let target = folder.appendingPathComponent(id)
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
    }
  }
}
