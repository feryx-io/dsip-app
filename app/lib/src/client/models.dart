/// The app's state as `dsip-app` sends it (its `State`, `CallView`, … as JSON): read only, never applied to here.
/// `test/fixtures/state.json` is made by `dsip-app`'s own test, so these readers and the Rust types cannot drift.
library;

/// Who this app is.
class Me {
  const Me({required this.identity, required this.device, required this.displayName});
  final String identity;
  final String device;
  final String displayName;

  factory Me.fromJson(Map<String, dynamic> j) =>
      Me(identity: j['identity'] as String, device: j['device'] as String, displayName: j['display_name'] as String);
}

enum Direction { outgoing, incoming }

/// Where a call is: `calling`, `ringing`, `answered` (with `answeredBy`), `ended` (with `reason`).
class CallState {
  const CallState(this.name, {this.answeredBy, this.reason});
  final String name;
  final String? answeredBy;
  final String? reason;

  bool get ended => name == 'ended';
  bool get answered => name == 'answered';

  factory CallState.fromJson(Map<String, dynamic> j) =>
      CallState(j['state'] as String, answeredBy: j['answered_by'] as String?, reason: j['reason'] as String?);
}

class CallView {
  const CallView({
    required this.id,
    required this.session,
    required this.peer,
    this.peerName,
    required this.direction,
    required this.state,
    required this.muted,
    required this.media,
    this.via,
    this.error,
  });
  final int id;
  final String session;
  final String peer;
  final String? peerName;
  final Direction direction;
  final CallState state;
  final bool muted;
  final bool media;
  final String? via;
  final String? error;

  /// Ringing here: waiting on the user to answer or decline.
  bool get ringingHere => direction == Direction.incoming && state.name == 'ringing';

  factory CallView.fromJson(Map<String, dynamic> j) => CallView(
    id: j['id'] as int,
    session: j['session'] as String,
    peer: j['peer'] as String,
    peerName: j['peer_name'] as String?,
    direction: Direction.values.byName(j['direction'] as String),
    state: CallState.fromJson(j['state'] as Map<String, dynamic>),
    muted: j['muted'] as bool,
    media: j['media'] as bool,
    via: j['via'] as String?,
    error: j['error'] as String?,
  );
}

class AudioDevice {
  const AudioDevice({required this.id, required this.name, required this.kind, required this.isDefault});
  final String id;
  final String name;
  final String kind;
  final bool isDefault;

  factory AudioDevice.fromJson(Map<String, dynamic> j) => AudioDevice(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: j['kind'] as String,
    isDefault: j['default'] as bool,
  );
}

class AudioState {
  const AudioState({required this.host, required this.devices, this.input, this.output});

  /// `system`, `tone` or `none`.
  final String host;
  final List<AudioDevice> devices;

  /// The microphone and speaker chosen (device ids); null: the system's default.
  final String? input;
  final String? output;

  factory AudioState.fromJson(Map<String, dynamic> j) => AudioState(
    host: j['host'] as String,
    devices: [for (final d in j['devices'] as List) AudioDevice.fromJson(d as Map<String, dynamic>)],
    input: j['input'] as String?,
    output: j['output'] as String?,
  );
}

class ConversationView {
  const ConversationView({
    required this.group,
    required this.conversation,
    required this.kind,
    this.peer,
    required this.members,
    required this.pending,
  });
  final String group;
  final String conversation;
  final String kind;
  final String? peer;
  final List<String> members;
  final int pending;

  factory ConversationView.fromJson(Map<String, dynamic> j) => ConversationView(
    group: j['group'] as String,
    conversation: j['conversation'] as String,
    kind: j['kind'] as String,
    peer: j['peer'] as String?,
    members: [for (final m in j['members'] as List) m as String],
    pending: j['pending'] as int,
  );
}

class RequestView {
  const RequestView({required this.id, required this.from, this.name});
  final String id;
  final String from;
  final String? name;

  factory RequestView.fromJson(Map<String, dynamic> j) =>
      RequestView(id: j['id'] as String, from: j['from'] as String, name: j['name'] as String?);
}

class Messaging {
  const Messaging({this.mailbox, required this.connected, required this.conversations, required this.requests});
  final String? mailbox;
  final bool connected;
  final List<ConversationView> conversations;
  final List<RequestView> requests;

  factory Messaging.fromJson(Map<String, dynamic> j) => Messaging(
    mailbox: j['mailbox'] as String?,
    connected: j['connected'] as bool? ?? false,
    conversations: [
      for (final c in j['conversations'] as List? ?? const []) ConversationView.fromJson(c as Map<String, dynamic>),
    ],
    requests: [for (final r in j['requests'] as List? ?? const []) RequestView.fromJson(r as Map<String, dynamic>)],
  );
}

class PresenceView {
  const PresenceView({required this.identity, this.state, this.token, this.source, this.unreadable = 0});
  final String identity;
  final String? state;
  final String? token;
  final String? source;
  final int unreadable;

  factory PresenceView.fromJson(Map<String, dynamic> j) => PresenceView(
    identity: j['identity'] as String,
    state: j['state'] as String?,
    token: j['token'] as String?,
    source: j['source'] as String?,
    unreadable: j['unreadable'] as int? ?? 0,
  );
}

class PresenceState {
  const PresenceState({this.mine, required this.following});
  final String? mine;
  final List<PresenceView> following;

  factory PresenceState.fromJson(Map<String, dynamic> j) => PresenceState(
    mine: j['mine'] as String?,
    following: [for (final p in j['following'] as List? ?? const []) PresenceView.fromJson(p as Map<String, dynamic>)],
  );
}

/// The whole state.
class AppState {
  const AppState({
    required this.me,
    required this.relay,
    required this.calls,
    required this.audio,
    required this.messaging,
    required this.presence,
    this.names = const {},
  });
  final Me me;
  final String relay;

  /// In id order: the latest last.
  final List<CallView> calls;
  final AudioState audio;
  final Messaging messaging;
  final PresenceState presence;

  /// The names this device's user gave identities, by identity (`set_name`): the app's own address book.
  final Map<String, String> names;

  /// What to call [did]: the name the user gave it, else the name it [offered] (a caller's own, unchecked), else the
  /// identity, shortened.
  String nameOf(String did, {String? offered}) => names[did] ?? offered ?? shortDid(did);

  /// Whether [did] has a name of the user's, or [offered] one, so that the identity is worth showing beside it.
  bool named(String did, {String? offered}) => names.containsKey(did) || offered != null;

  /// Calls not ended, the latest first.
  List<CallView> get live => calls.where((c) => !c.state.ended).toList().reversed.toList();

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
    me: Me.fromJson(j['me'] as Map<String, dynamic>),
    relay: j['relay'] as String,
    calls: [for (final c in j['calls'] as List) CallView.fromJson(c as Map<String, dynamic>)],
    audio: AudioState.fromJson(j['audio'] as Map<String, dynamic>),
    messaging: Messaging.fromJson(j['messaging'] as Map<String, dynamic>),
    presence: PresenceState.fromJson(j['presence'] as Map<String, dynamic>? ?? const {}),
    names: (j['names'] as Map<String, dynamic>? ?? const {}).cast<String, String>(),
  );
}

/// One update from the app: the state, after the change it names (none for the first).
class Update {
  const Update(this.state, this.change);
  final AppState state;

  /// The change's JSON (`{"change": "call_added", …}`), or null.
  final Map<String, dynamic>? change;

  String? get kind => change?['change'] as String?;

  factory Update.fromJson(Map<String, dynamic> j) =>
      Update(AppState.fromJson(j['state'] as Map<String, dynamic>), j['change'] as Map<String, dynamic>?);
}

/// A message in a conversation.
class MessageView {
  const MessageView({
    required this.conversation,
    required this.id,
    required this.from,
    required this.mine,
    required this.kind,
    this.text,
    required this.sentAt,
  });

  /// The conversation's group id.
  final String conversation;
  final String id;
  final String from;
  final bool mine;

  /// `text`, `audio`, …
  final String kind;
  final String? text;

  /// Unix seconds, the sender's clock.
  final int sentAt;

  factory MessageView.fromJson(Map<String, dynamic> j) => MessageView(
    conversation: j['conversation'] as String,
    id: j['id'] as String,
    from: j['from'] as String,
    mine: j['mine'] as bool,
    kind: j['kind'] as String,
    text: j['text'] as String?,
    sentAt: j['sent_at'] as int,
  );
}

/// A DID short enough for a list: its method and the start and end of its key.
String shortDid(String did) {
  final i = did.lastIndexOf(':');
  final key = i < 0 ? did : did.substring(i + 1);
  final method = i < 0 ? '' : did.substring(0, i + 1);
  return key.length <= 14 ? did : '$method${key.substring(0, 8)}…${key.substring(key.length - 4)}';
}

/// A newer release than this copy (`dsip_app_bridge`'s `check_for_update`).
class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, required this.canInstall, this.reason, this.download});
  final String version;

  /// The release's page.
  final String notes;

  /// This copy can install it itself.
  final bool canInstall;

  /// Why not, when it cannot.
  final String? reason;

  /// The file to install by hand, when it cannot.
  final String? download;

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
    version: j['version'] as String,
    notes: j['notes'] as String,
    canInstall: j['can_install'] as bool,
    reason: j['reason'] as String?,
    download: j['download'] as String?,
  );
}
