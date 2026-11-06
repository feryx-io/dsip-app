import Foundation
import PushKit

/// The app woken while it sleeps through PushKit (app plan A5d-3, as Anvil's A3; the Wake Profile, W§5): the core
/// enrols the VoIP token at the publisher's push gateway and registers with its relay; a relay holding a call for the
/// app wakes it. Apple's rule: every VoIP push reports a call to CallKit, or iOS stops delivering them. A call wake rings
/// at once while the app starts and binds, and the call's invite, flushed to it then, takes the ringing call's place
/// (`CallSystem`); a `call-ended` wake ends the call it names, or reports one ended at once (W§5.4).
///
/// The topic is the bundle ID with `.voip`; the gateway is the publisher's, given at build time (`DSIP_PUSH_GATEWAY`,
/// through Info.plist's `DsipPushGateway`). A build without a gateway, or unsigned (PushKit gives it no token), is never
/// woken.
final class Push: NSObject, PKPushRegistryDelegate {
  private let calls: CallSystem
  private let registry = PKPushRegistry(queue: .main)

  /// Made at launch, as PushKit requires, so a push that launched the app in the background is delivered.
  init(calls: CallSystem) {
    self.calls = calls
    super.init()
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
  }

  /// The APNs topic of the app's VoIP pushes (W§3's `app`).
  static var topic: String? { Bundle.main.bundleIdentifier.map { "\($0).voip" } }

  /// APNs' environment for this build's token: `sandbox` when its provisioning profile grants the development one
  /// (a build run from Xcode, or ad hoc for development); none, production, for a build from the App Store, which
  /// carries no profile.
  static var environment: String? {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      // The profile is a signed message around a property list.
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
      let plist = try? PropertyListSerialization.propertyList(
        from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any]
    else { return nil }
    return entitlements["aps-environment"] as? String == "development" ? "sandbox" : nil
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP, !CoreLink.gateway.isEmpty, let topic = Push.topic else { return }
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    CoreLink.setPush(provider: "apns", app: topic, token: token, environment: Push.environment)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP, !CoreLink.gateway.isEmpty else { return }
    CoreLink.setPush(provider: "apns", app: Push.topic ?? "", token: "", environment: nil)
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    handle(payload.dictionaryPayload, completion: completion)
  }

  /// A push's data: `dsip-wake`, the wake (W§5.3; beside `aps`, or as a JSON string as the app's tests hand it in);
  /// `completion` once CallKit has been told. Its `sealed` hint is not opened here: the app knows no names for DIDs,
  /// and what the hint says is the relay's claim (W§6), so the call rings as from an unknown caller until its verified
  /// invite says who.
  func handle(_ data: [AnyHashable: Any], completion: @escaping () -> Void) {
    let unknown = NSLocalizedString("Unknown caller", comment: "A call a wake told of, before its invite says who calls")
    var wake = data["dsip-wake"] as? [String: Any]
    if wake == nil, let text = data["dsip-wake"] as? String, let json = text.data(using: .utf8) {
      wake = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
    }
    guard let wake = wake else {
      NSLog("DsipPush: a push that is not a wake")
      calls.reportAndEnd(name: unknown, completion: completion)
      return
    }
    // Not set up since the token was given: nothing to wake.
    guard CoreLink.configured else {
      NSLog("DsipPush: a wake for an app not set up")
      calls.reportAndEnd(name: unknown, completion: completion)
      return
    }
    let session = wake["session"] as? String ?? ""
    switch wake["kind"] as? String {
    case "call" where !session.isEmpty:
      calls.reportPushed(session: session, name: unknown, completion: completion)
      CoreLink.wake { [calls] _ in calls.wakeFailed(session: session) }
    // The invite stopped being held before the app bound (W§5.1).
    case "call-ended":
      calls.cancelPushed(session: session, completion: completion)
    // A `message` comes as an alert push, never through PushKit (W§5.3): a kind this app does not know is shown and
    // gone, and the app starts all the same.
    default:
      NSLog("DsipPush: a wake of a kind this app does not ring for: %@", "\(wake["kind"] ?? "")")
      calls.reportAndEnd(name: unknown, completion: completion)
      CoreLink.wake { _ in }
    }
  }
}
