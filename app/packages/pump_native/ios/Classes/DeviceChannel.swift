import AVFoundation
import Flutter
import Network
import UIKit

/// 'fitapp/device': links, email, the phone's details, keeping the screen
/// on, and playing the rest sound.
final class DeviceChannel: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private let monitor = NWPathMonitor()

  override init() {
    super.init()
    monitor.start(queue: DispatchQueue(label: "pumpandplate.network"))
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "specs":
      result(specs())
    case "network":
      result(network())
    case "openUrl":
      open(args["url"] as? String ?? "", result)
    case "email":
      email(
        to: args["to"] as? String ?? "",
        subject: args["subject"] as? String ?? "",
        body: args["body"] as? String ?? "",
        result)
    case "model":
      result("\(deviceIdentifier()) - iOS \(UIDevice.current.systemVersion)")
    case "keepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = (args["on"] as? Bool) ?? false
      result(nil)
    case "playSound":
      result(play(args["path"] as? String ?? ""))
    case "stopSound":
      stopSound()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Phone details

  /// Memory, free space and the model code (for example "iPhone16,1"). The
  /// app turns the code into a name and chip.
  private func specs() -> [String: Any] {
    var free: Int64 = 0
    let home = URL(fileURLWithPath: NSHomeDirectory())
    if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let capacity = values.volumeAvailableCapacityForImportantUsage
    {
      free = capacity
    }
    return [
      "totalRam": Int64(ProcessInfo.processInfo.physicalMemory),
      "freeStorage": free,
      "soc": "",
      "socMaker": "Apple",
      "model": deviceIdentifier(),
      "brand": "Apple",
      "abis": ["arm64"],
    ]
  }

  private func network() -> String {
    let path = monitor.currentPath
    if path.status != .satisfied { return "none" }
    // Wi-Fi or a cable counts as Wi-Fi (also behind a VPN), like on Android.
    if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { return "unmetered" }
    if path.isExpensive || path.usesInterfaceType(.cellular) { return "metered" }
    return "unmetered"
  }

  // MARK: Links and email

  private func open(_ text: String, _ result: @escaping FlutterResult) {
    guard let url = URL(string: text) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { ok in pumpReply(result, ok) }
  }

  /// Opens a new email in the Mail app (or the person's default email app).
  /// Nothing is sent until they tap Send there.
  private func email(to: String, subject: String, body: String, _ result: @escaping FlutterResult) {
    var parts = URLComponents()
    parts.scheme = "mailto"
    parts.path = to
    parts.queryItems = [
      URLQueryItem(name: "subject", value: subject),
      URLQueryItem(name: "body", value: body),
    ]
    guard let url = parts.url else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { ok in pumpReply(result, ok) }
  }

  // MARK: Rest sound

  /// Plays a sound file once, over any music (which dips while it plays).
  private func play(_ path: String) -> Bool {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return false }
    stopSound()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
      try session.setActive(true)
      let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      p.delegate = self
      p.prepareToPlay()
      player = p
      return p.play()
    } catch {
      return false
    }
  }

  private func stopSound() {
    player?.stop()
    player = nil
    releaseAudio()
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    self.player = nil
    releaseAudio()
  }

  /// Lets music come back to full volume.
  private func releaseAudio() {
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}

/// The model code, for example "iPhone16,1" ("x86_64"/"arm64" become the
/// simulated model in the Simulator).
func deviceIdentifier() -> String {
  if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
    return simulated
  }
  var info = utsname()
  uname(&info)
  let mirror = Mirror(reflecting: info.machine)
  var text = ""
  for child in mirror.children {
    guard let value = child.value as? Int8, value != 0 else { break }
    text.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
  }
  return text
}
