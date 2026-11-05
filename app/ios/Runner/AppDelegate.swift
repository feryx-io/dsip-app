import AVFoundation
import CallKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let calls = CallSystem()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `dsip/mobile`: what the app asks of the phone (lib/src/mobile/platform.dart). As Anvil's U4a.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DsipMobile") {
      let channel = FlutterMethodChannel(name: "dsip/mobile", binaryMessenger: registrar.messenger())
      calls.channel = channel
      let calls = self.calls
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        let id = (args["id"] as? NSNumber)?.int64Value ?? -1
        let name = args["name"] as? String ?? ""
        let address = args["address"] as? String ?? ""
        switch call.method {
        case "requestMicrophone": AppDelegate.requestMicrophone(result)
        case "startAudio": AppDelegate.startAudio(result)
        case "reportIncoming":
          calls.reportIncoming(id: id, name: name, address: address)
          result(nil)
        case "reportOutgoing":
          calls.reportOutgoing(id: id, name: name, address: address)
          result(nil)
        case "reportConnected":
          calls.reportConnected(id: id)
          result(nil)
        case "reportEnded":
          calls.reportEnded(id: id)
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// A phone's audio: the microphone and the earpiece together, with the system's echo cancellation (cpal leaves the
  /// session as it finds it, and the default only plays). The call's routing comes with A5b and A5c.
  private static func startAudio(_ result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
      try session.setActive(true)
      result(nil)
    } catch {
      result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
    }
  }

  /// Asks once (the system remembers the answer); whether the app may use the microphone.
  private static func requestMicrophone(_ result: @escaping FlutterResult) {
    let answer: (Bool) -> Void = { granted in DispatchQueue.main.async { result(granted) } }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: answer)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(answer)
    }
  }
}

/// The app's calls as CallKit knows them (app plan A5b, as Anvil's U4b): the system's call screen rings for a call coming
/// in (on the lock screen too), shows a call placed, and hands back what the user does there (answer, end, mute) as
/// `callEvent`s on `dsip/mobile` (lib/src/mobile/platform.dart). DSIP's calls have no hold and no keys.
final class CallSystem: NSObject, CXProviderDelegate {
  var channel: FlutterMethodChannel?
  private let provider: CXProvider
  private let controller = CXCallController()
  private var uuids: [Int64: UUID] = [:]
  private var ids: [UUID: Int64] = [:]
  private var incoming: Set<Int64> = []
  /// Calls answered at the system's screen (not to be answered again).
  private var answered: Set<Int64> = []
  /// Calls the system took as placed.
  private var started: [Int64: (name: String, address: String)] = [:]

  override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = false
    config.maximumCallGroups = 2
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    // The app keeps its own list of calls, so the system's Recents would show each call twice.
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  private func emit(_ action: String, _ id: Int64, _ extra: [String: Any] = [:]) {
    var event = extra
    event["action"] = action
    event["id"] = NSNumber(value: id)
    DispatchQueue.main.async { self.channel?.invokeMethod("callEvent", arguments: event) }
  }

  private func remember(_ id: Int64) -> UUID {
    let uuid = UUID()
    uuids[id] = uuid
    ids[uuid] = id
    return uuid
  }

  private func forget(_ id: Int64) {
    if let uuid = uuids.removeValue(forKey: id) { ids.removeValue(forKey: uuid) }
    incoming.remove(id)
    answered.remove(id)
    started.removeValue(forKey: id)
  }

  private func update(name: String, address: String) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: address)
    update.localizedCallerName = name.isEmpty ? address : name
    update.hasVideo = false
    update.supportsHolding = false
    update.supportsDTMF = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    return update
  }

  func reportIncoming(id: Int64, name: String, address: String) {
    let uuid = remember(id)
    incoming.insert(id)
    provider.reportNewIncomingCall(with: uuid, update: update(name: name, address: address)) { error in
      DispatchQueue.main.async {
        guard let error = error else {
          self.emit("shown", id)
          return
        }
        self.forget(id)
        var reason = "unavailable"
        if let error = error as? CXErrorCodeIncomingCallError,
          error.code == .filteredByDoNotDisturb || error.code == .filteredByBlockList
        {
          reason = "filtered"
        }
        self.emit("failed", id, ["reason": reason])
      }
    }
  }

  func reportOutgoing(id: Int64, name: String, address: String) {
    let uuid = remember(id)
    started[id] = (name, address)
    let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: address))
    controller.request(CXTransaction(action: action)) { error in
      guard error != nil else { return }
      DispatchQueue.main.async {
        self.forget(id)
        self.emit("failed", id, ["reason": "unavailable"])
      }
    }
  }

  func reportConnected(id: Int64) {
    guard let uuid = uuids[id] else { return }
    if incoming.contains(id) {
      // Answered in the app: the system's screen is told too.
      if !answered.contains(id) {
        answered.insert(id)
        controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
      }
    } else {
      provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }
  }

  func reportEnded(id: Int64) {
    guard let uuid = uuids[id] else { return }
    forget(id)
    provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
  }

  // MARK: CXProviderDelegate

  /// The system dropped every call it had (its call service restarted; a simulator has none and resets at the first
  /// call ringing in). The user ended nothing: the calls go on in the app, without the system's screen.
  func providerDidReset(_ provider: CXProvider) {
    for id in Array(uuids.keys) {
      forget(id)
      emit("failed", id, ["reason": "reset"])
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard let id = ids[action.callUUID], let call = started[id] else {
      action.fail()
      return
    }
    provider.reportCall(with: action.callUUID, updated: update(name: call.name, address: call.address))
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
    action.fulfill()
    emit("shown", id)
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let id = ids[action.callUUID] else {
      action.fail()
      return
    }
    let fromSystem = !answered.contains(id)
    answered.insert(id)
    action.fulfill()
    if fromSystem { emit("answer", id) }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let id = ids[action.callUUID] else {
      action.fail()
      return
    }
    forget(id)
    action.fulfill()
    emit("end", id)
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let id = ids[action.callUUID] else {
      action.fail()
      return
    }
    action.fulfill()
    emit("mute", id, ["on": action.isMuted])
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
