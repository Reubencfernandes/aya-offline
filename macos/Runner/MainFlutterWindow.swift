import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerStorageChannel(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerStorageChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "aya/storage_info",
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "getAvailableBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing path argument.",
            details: nil
          )
        )
        return
      }

      do {
        let resolvedPath = self.resolveExistingPath(path)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: resolvedPath)
        if let freeBytes = attributes[.systemFreeSize] as? NSNumber {
          result(freeBytes.int64Value)
        } else {
          result(nil)
        }
      } catch {
        result(
          FlutterError(
            code: "storage_error",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func resolveExistingPath(_ path: String) -> String {
    var url = URL(fileURLWithPath: path)
    let fileManager = FileManager.default

    while !fileManager.fileExists(atPath: url.path) && url.path != "/" {
      url.deleteLastPathComponent()
    }

    if fileManager.fileExists(atPath: url.path) {
      return url.path
    }

    return NSHomeDirectory()
  }
}
