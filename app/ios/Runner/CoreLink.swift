import Foundation

/// Native code's way to the app in the Rust core, with or without Dart (app plan A5d-3, as Anvil's A3): a VoIP push
/// starts it in a process where Flutter may never run. The app's calls come here as events for CallKit
/// (`CallSystem.fromCore`); what the user does at CallKit goes back (`act`). The Rust side is `app/rust/src/ios.rs` and
/// `system.rs`.
enum CoreLink {
  /// The Rust calls block: one at a time, never on the main thread.
  private static let worker = DispatchQueue(label: "com.thevoiceguy.dsip.core")

  private static var following = false

  /// The app's folder, where Dart keeps `settings.json` (path_provider's application support directory).
  static var dir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  }

  /// Whether the app has been set up: there are settings to start from.
  static var configured: Bool {
    FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path)
  }

  /// The publisher's push gateway this build was given (`DSIP_PUSH_GATEWAY` when it was built, through Info.plist's
  /// `DsipPushGateway`); empty without one.
  static var gateway: String {
    let value = Bundle.main.object(forInfoDictionaryKey: "DsipPushGateway") as? String ?? ""
    return value.hasPrefix("$(") ? "" : value
  }

  /// A string the core answered with, freed; null is none.
  private static func take(_ answer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let answer = answer else { return nil }
    defer { dsip_string_free(answer) }
    return String(cString: answer)
  }

  /// Load the core and follow the app's calls for `calls`, once per process: at launch, before Flutter or a push.
  static func start(_ calls: CallSystem) {
    dispatchPrecondition(condition: .onQueue(.main))
    if following { return }
    following = true
    dsip_init(dir.path, gateway)
    let reader = Thread {
      while true {
        guard let json = take(dsip_next_call_event(60_000)) else { continue }
        guard let data = json.data(using: .utf8),
          let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
          NSLog("DsipCore: an unreadable call event: %@", json)
          continue
        }
        DispatchQueue.main.async { calls.fromCore(event) }
      }
    }
    reader.name = "dsip-calls"
    reader.start()
  }

  /// Woken by a push: start the app from its settings, unless it runs. `failed` hears why not, on the main thread.
  static func wake(failed: @escaping (String) -> Void) {
    worker.async {
      guard let error = take(dsip_wake()) else { return }
      NSLog("DsipCore: the app did not wake: %@", error)
      DispatchQueue.main.async { failed(error) }
    }
  }

  /// Where this install is woken from now on; an empty token is nowhere.
  static func setPush(provider: String, app: String, token: String, environment: String?) {
    worker.async {
      if let error = take(dsip_set_push(provider, app, token, environment ?? "")) {
        NSLog("DsipCore: the push token was not taken: %@", error)
      }
    }
  }

  /// What the user did at the system's call screen, for the app.
  static func act(_ action: String, _ id: Int64, _ extra: [String: Any] = [:]) {
    var body = extra
    body["action"] = action
    body["id"] = NSNumber(value: id)
    guard let data = try? JSONSerialization.data(withJSONObject: body),
      let json = String(data: data, encoding: .utf8)
    else { return }
    worker.async {
      if let error = take(dsip_act(json)) {
        NSLog("DsipCore: %@ on call %lld: %@", action, id, error)
      }
    }
  }
}
