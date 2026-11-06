import AVFoundation
import CallKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let calls = CallSystem()
  private let routes = AudioRoutes()
  private var push: Push?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Before anything else: a VoIP push may have launched the app in the background, with no Flutter to come (A5d-3).
    CoreLink.start(calls)
    push = Push(calls: calls)
    push?.registerForMessages()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// APNs' alert token, for message wakes (A5d-4).
  override func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    push?.alertToken(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // An unsigned build, or no network yet: asked again at the next launch.
    NSLog("DsipPush: no alert token: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `dsip/mobile`: what the app asks of the phone (lib/src/mobile/platform.dart). As Anvil's U4a.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DsipMobile") {
      let channel = FlutterMethodChannel(name: "dsip/mobile", binaryMessenger: registrar.messenger())
      calls.channel = channel
      routes.channel = channel
      let calls = self.calls
      let routes = self.routes
      let push = self.push
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
        case "audioRoutes": result(routes.current())
        case "setAudioRoute":
          do {
            try routes.set(args["route"] as? String ?? "")
            result(nil)
          } catch {
            result(FlutterError(code: "route", message: error.localizedDescription, details: nil))
          }
        case "setProximity":
          UIDevice.current.isProximityMonitoringEnabled = args["on"] as? Bool ?? false
          result(nil)
        // The calls CallKit is showing, for the app's tests.
        case "systemCalls": result(calls.shown.map { NSNumber(value: $0) })
        case "deliverPush":
          // A push as PushKit hands one (its `dsip-wake`), for the app's tests on a simulator, which PushKit does not
          // reach; debug builds only.
          #if DEBUG
            push?.handle(args) {}
            result(nil)
          #else
            result(FlutterMethodNotImplemented)
          #endif
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// A phone's audio: the microphone and the earpiece together, with the system's echo cancellation (cpal leaves the
  /// session as it finds it, and the default only plays). Where it goes: `AudioRoutes`.
  static func prepareAudio() throws {
    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
  }

  private static func startAudio(_ result: @escaping FlutterResult) {
    do {
      try prepareAudio()
      try AVAudioSession.sharedInstance().setActive(true)
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

/// The app's calls as CallKit knows them (app plan A5b, as Anvil's U4b): the Rust core tells of each call (`fromCore`,
/// through `CoreLink`; A5d-3), the system's call screen rings for a call coming in (on the lock screen too), shows a
/// call placed, and hands back what the user does there (answer, end, mute) to the core, and to Dart when it runs, as
/// `callEvent`s on `dsip/mobile` (lib/src/mobile/platform.dart). DSIP's calls have no hold and no keys.
///
/// A call a push told of (the Wake Profile, W§5.4) rings at once, before the app has started and bound; the app's call,
/// when the relay flushes its invite, takes its place: the one with the session the wake named.
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
  /// The DSIP session of a call ringing in, as a wake or the app named it.
  private var sessions: [Int64: String] = [:]
  /// Pushed calls answered at the screen before the app's call came.
  private var answerWhenReady: Set<Int64> = []

  /// A pushed call rings this long without the app's call, then stops (T-Establish's maximum, W§5.4).
  private static let pushedRing: TimeInterval = 60
  /// Ids for pushed calls: below zero, apart from the app's.
  private var nextPushed: Int64 = -1
  /// Sessions declined from a push before their invite came: when.
  private var declined: [String: Date] = [:]

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

  /// The calls CallKit is showing.
  var shown: [Int64] { Array(uuids.keys) }

  /// Dart hears what happened at the system, when it runs (its tests do).
  private func tell(_ action: String, _ id: Int64, _ extra: [String: Any] = [:]) {
    var event = extra
    event["action"] = action
    event["id"] = NSNumber(value: id)
    DispatchQueue.main.async { self.channel?.invokeMethod("callEvent", arguments: event) }
  }

  /// What the user or the system did with a call: for the core, and Dart. A pushed call's is not here yet: nothing to
  /// act on.
  private func emit(_ action: String, _ id: Int64, _ extra: [String: Any] = [:]) {
    tell(action, id, extra)
    if action != "shown" && id >= 0 { CoreLink.act(action, id, extra) }
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
    sessions.removeValue(forKey: id)
    answerWhenReady.remove(id)
  }

  /// The pushed call `from` becomes the app's call `id`; whether it was answered while it waited.
  private func adopt(_ from: Int64, as id: Int64) -> Bool {
    guard let uuid = uuids.removeValue(forKey: from) else { return false }
    uuids[id] = uuid
    ids[uuid] = id
    if incoming.remove(from) != nil { incoming.insert(id) }
    if answered.remove(from) != nil { answered.insert(id) }
    if let session = sessions.removeValue(forKey: from) { sessions[id] = session }
    return answerWhenReady.remove(from) != nil
  }

  private func decline(_ session: String) {
    let now = Date()
    declined = declined.filter { now.timeIntervalSince($0.value) < CallSystem.pushedRing }
    declined[session] = now
  }

  private func pushed(_ session: String) -> Int64? {
    sessions.first { $0.key < 0 && $0.value == session }?.key
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

  /// What the core says of its calls (`app/rust/src/system.rs`).
  func fromCore(_ event: [String: Any]) {
    let id = (event["id"] as? NSNumber)?.int64Value ?? -1
    let name = event["name"] as? String ?? ""
    let address = event["address"] as? String ?? ""
    switch event["kind"] as? String {
    case "incoming": coreRinging(id: id, name: name, address: address, session: event["session"] as? String ?? "")
    case "outgoing": if uuids[id] == nil { reportOutgoing(id: id, name: name, address: address) }
    case "connected": reportConnected(id: id)
    case "ended": reportEnded(id: id)
    // The app stopped: its calls are over; a pushed call waits on.
    case "reset":
      for id in uuids.keys where id >= 0 { reportEnded(id: id) }
    default: break
    }
  }

  /// The app's call ringing in: the pushed call it is, or a new one.
  private func coreRinging(id: Int64, name: String, address: String, session: String) {
    if uuids[id] != nil { return }
    if !session.isEmpty, declined.removeValue(forKey: session) != nil {
      CoreLink.act("end", id)
      return
    }
    guard let from = session.isEmpty ? nil : pushed(session), let uuid = uuids[from] else {
      reportIncoming(id: id, name: name, address: address)
      if !session.isEmpty { sessions[id] = session }
      return
    }
    let answer = adopt(from, as: id)
    // Who calls, as the verified invite says, in place of the unknown caller (W§6).
    provider.reportCall(with: uuid, updated: update(name: name, address: address))
    if answer { CoreLink.act("answer", id) }
  }

  func reportIncoming(id: Int64, name: String, address: String, completion: (() -> Void)? = nil) {
    let uuid = remember(id)
    incoming.insert(id)
    provider.reportNewIncomingCall(with: uuid, update: update(name: name, address: address)) { error in
      DispatchQueue.main.async {
        defer { completion?() }
        guard let error = error else {
          self.emit("shown", id)
          return
        }
        var reason = "unavailable"
        if let error = error as? CXErrorCodeIncomingCallError,
          error.code == .filteredByDoNotDisturb || error.code == .filteredByBlockList
        {
          reason = "filtered"
        }
        // Do Not Disturb or a blocked caller: a pushed call is declined when its invite comes.
        if reason == "filtered", id < 0, let session = self.sessions[id] { self.decline(session) }
        self.forget(id)
        self.emit("failed", id, ["reason": reason])
      }
    }
  }

  /// A wake says a call is coming (`session`): it rings now, while the app starts and binds; `completion` once CallKit
  /// has it.
  func reportPushed(session: String, name: String, completion: @escaping () -> Void) {
    // Pushed again, or ringing already: told to CallKit as the same call, as every VoIP push must tell one.
    if let known = sessions.first(where: { $0.value == session })?.key, let uuid = uuids[known] {
      provider.reportNewIncomingCall(with: uuid, update: CXCallUpdate()) { _ in
        DispatchQueue.main.async { completion() }
      }
      return
    }
    if declined[session] != nil {
      reportAndEnd(name: name, completion: completion)
      return
    }
    let id = nextPushed
    nextPushed -= 1
    sessions[id] = session
    reportIncoming(id: id, name: name, address: "", completion: completion)
    DispatchQueue.main.asyncAfter(deadline: .now() + CallSystem.pushedRing) {
      if self.uuids[id] != nil {
        NSLog("DsipCalls: the call %@ never came", session)
        self.reportEnded(id: id, reason: .unanswered)
      }
    }
  }

  /// A `call-ended` wake: the call a push told of is over before the app bound (W§5.1). The push still reports a call,
  /// as every VoIP push must: the one it names, or one ended at once (W§5.4).
  func cancelPushed(session: String, completion: @escaping () -> Void) {
    guard let id = sessions.first(where: { $0.value == session })?.key, let uuid = uuids[id] else {
      reportAndEnd(name: "", completion: completion)
      return
    }
    provider.reportNewIncomingCall(with: uuid, update: CXCallUpdate()) { _ in
      DispatchQueue.main.async {
        // The app's own call ends when the app hears it has.
        if id < 0 { self.reportEnded(id: id) }
        completion()
      }
    }
  }

  /// The app could not start: the pushed call cannot reach it.
  func wakeFailed(session: String) {
    guard let id = pushed(session) else { return }
    reportEnded(id: id, reason: .failed)
  }

  /// A push that rings nothing still reports a call to CallKit (Apple's rule), ended at once.
  func reportAndEnd(name: String, completion: @escaping () -> Void) {
    let uuid = UUID()
    provider.reportNewIncomingCall(with: uuid, update: update(name: name, address: "")) { error in
      DispatchQueue.main.async {
        if error == nil { self.provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded) }
        completion()
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

  func reportEnded(id: Int64, reason: CXCallEndedReason = .remoteEnded) {
    guard let uuid = uuids[id] else { return }
    forget(id)
    provider.reportCall(with: uuid, endedAt: nil, reason: reason)
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
    try? AppDelegate.prepareAudio()
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
    // CallKit activates the session for the call once this is fulfilled: it must be a call's session by then (the app
    // may not be in front, or Dart running).
    try? AppDelegate.prepareAudio()
    let fromSystem = !answered.contains(id)
    answered.insert(id)
    if id < 0 { answerWhenReady.insert(id) }
    action.fulfill()
    if fromSystem { emit("answer", id) }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let id = ids[action.callUUID] else {
      action.fail()
      return
    }
    // A pushed call declined before its invite came: declined when it does.
    if id < 0, let session = sessions[id] { decline(session) }
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

/// Where a call's audio goes on iOS (app plan A5c, as Anvil's U4c): the session's route (the earpiece, the speaker, a
/// Bluetooth headset or car, a wired headset), told to Dart at every change as `{current, available, bluetoothName}`
/// (lib/src/mobile/platform.dart), and changed by overriding the output or choosing the input whose port carries the
/// output with it.
final class AudioRoutes: NSObject {
  var channel: FlutterMethodChannel?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(changed), name: AVAudioSession.routeChangeNotification, object: nil)
  }

  @objc private func changed(_ note: Notification) {
    DispatchQueue.main.async { self.channel?.invokeMethod("audioRoutes", arguments: self.current()) }
  }

  private static let bluetooth: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothLE]

  func current() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let output = session.currentRoute.outputs.first
    let inputs = session.availableInputs ?? []
    let current: String
    switch output?.portType {
    case .builtInSpeaker?: current = "speaker"
    case .bluetoothHFP?, .bluetoothA2DP?, .bluetoothLE?, .carAudio?: current = "bluetooth"
    case .headphones?, .usbAudio?: current = "wired"
    default: current = "earpiece"
    }
    let headset = inputs.first { AudioRoutes.bluetooth.contains($0.portType) }
    let wired = inputs.contains { $0.portType == .headsetMic } || current == "wired"
    var available: [String] = []
    // A wired headset takes the earpiece's place; an iPad has none.
    if UIDevice.current.userInterfaceIdiom == .phone && !wired { available.append("earpiece") }
    available.append("speaker")
    if headset != nil || current == "bluetooth" { available.append("bluetooth") }
    if wired { available.append("wired") }
    var routes: [String: Any] = ["current": current, "available": available]
    if let name = headset?.portName ?? (current == "bluetooth" ? output?.portName : nil) {
      routes["bluetoothName"] = name
    }
    return routes
  }

  func set(_ route: String) throws {
    let session = AVAudioSession.sharedInstance()
    let inputs = session.availableInputs ?? []
    switch route {
    case "speaker":
      try session.overrideOutputAudioPort(.speaker)
    case "earpiece":
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(inputs.first { $0.portType == .builtInMic })
    case "bluetooth":
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(inputs.first { AudioRoutes.bluetooth.contains($0.portType) })
    case "wired":
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(inputs.first { $0.portType == .headsetMic })
    default:
      break
    }
  }
}
