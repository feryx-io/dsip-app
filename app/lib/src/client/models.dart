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
    this.sound,
    this.video = false,
    this.camera = false,
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

  /// What its sound did on this device, while it rings back or has the devices.
  final CallSound? sound;

  /// It carries video: offered with it, and the answer took it.
  final bool video;

  /// This side's camera sends to it.
  final bool camera;

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
    video: j['video'] as bool? ?? false,
    camera: j['camera'] as bool? ?? false,
    error: j['error'] as String?,
    sound: j['sound'] == null ? null : CallSound.fromJson(j['sound'] as Map<String, dynamic>),
  );
}

/// A call's sound on this device, counted (`dsip-app`'s `CallSound`): each stage feeds the next, so the first that
/// stays at 0, or an error, is where the sound stops.
class CallSound {
  const CallSound({
    required this.mic,
    required this.sent,
    required this.heard,
    required this.decoded,
    required this.played,
    required this.ringback,
    this.micError,
    this.speakerError,
    this.stalled,
  });
  final int mic;
  final int sent;
  final int heard;
  final int decoded;
  final int played;
  final int ringback;
  final String? micError;
  final String? speakerError;
  /// The stage that stopped counting while the call went on: where its sound stops.
  final String? stalled;

  /// Whether anything went wrong: only then is the sound shown.
  bool get troubled => stalled != null || micError != null || speakerError != null;

  factory CallSound.fromJson(Map<String, dynamic> j) => CallSound(
    mic: j['mic'] as int,
    sent: j['sent'] as int,
    heard: j['heard'] as int,
    decoded: j['decoded'] as int,
    played: j['played'] as int,
    ringback: j['ringback'] as int,
    micError: j['mic_error'] as String?,
    speakerError: j['speaker_error'] as String?,
    stalled: j['stalled'] as String?,
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
  const RequestView({required this.id, required this.from, this.name, this.purpose});
  final String id;
  final String from;

  /// The name it gives (a claim, not verified).
  final String? name;

  /// What it says: why it asks.
  final String? purpose;

  factory RequestView.fromJson(Map<String, dynamic> j) => RequestView(
    id: j['id'] as String,
    from: j['from'] as String,
    name: j['name'] as String?,
    purpose: j['purpose'] as String?,
  );
}

/// An introduction this identity sent.
class Introduced {
  const Introduced({required this.to, this.name, required this.purpose, required this.sentAt, required this.accepted});
  final String to;

  /// What the user calls them: their contact's name once they accept.
  final String? name;
  final String purpose;

  /// Unix seconds.
  final int sentAt;
  final bool accepted;

  factory Introduced.fromJson(Map<String, dynamic> j) => Introduced(
    to: j['to'] as String,
    name: j['name'] as String?,
    purpose: j['purpose'] as String,
    sentAt: j['sent_at'] as int,
    accepted: j['accepted'] as bool,
  );
}

class Messaging {
  const Messaging({
    this.mailbox,
    required this.connected,
    required this.conversations,
    required this.requests,
    this.introduced = const [],
  });
  final String? mailbox;
  final bool connected;
  final List<ConversationView> conversations;
  final List<RequestView> requests;

  /// The introductions sent, oldest first.
  final List<Introduced> introduced;

  factory Messaging.fromJson(Map<String, dynamic> j) => Messaging(
    mailbox: j['mailbox'] as String?,
    connected: j['connected'] as bool? ?? false,
    conversations: [
      for (final c in j['conversations'] as List? ?? const []) ConversationView.fromJson(c as Map<String, dynamic>),
    ],
    requests: [for (final r in j['requests'] as List? ?? const []) RequestView.fromJson(r as Map<String, dynamic>)],
    introduced: [for (final i in j['introduced'] as List? ?? const []) Introduced.fromJson(i as Map<String, dynamic>)],
  );
}

/// A call that ended, as the call history keeps it.
class CallRecord {
  const CallRecord({
    required this.session,
    required this.peer,
    this.peerName,
    required this.direction,
    required this.answered,
    required this.reason,
    required this.endedAt,
  });

  /// The call's session id: what `forget_call` names.
  final String session;
  final String peer;
  final String? peerName;
  final Direction direction;
  final bool answered;
  final String reason;

  /// Unix seconds.
  final int endedAt;

  /// A call that came in and was not answered: not declined here, nor answered on another device.
  bool get missed =>
      direction == Direction.incoming &&
      !answered &&
      !const {'user.declined', 'session.answered-elsewhere', 'session.already-answered'}.contains(reason);

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
    session: j['session'] as String,
    peer: j['peer'] as String,
    peerName: j['peer_name'] as String?,
    direction: Direction.values.byName(j['direction'] as String),
    answered: j['answered'] as bool,
    reason: j['reason'] as String,
    endedAt: j['ended_at'] as int,
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
    this.video = false,
    this.names = const {},
    this.history = const [],
    this.voice = const VoiceState(),
  });
  /// The app makes and takes video calls here: it has a camera and H.264.
  final bool video;
  final Me me;
  final String relay;

  /// In id order: the latest last.
  final List<CallView> calls;
  final AudioState audio;
  final Messaging messaging;
  final PresenceState presence;

  /// The names this device's user gave identities, by identity (`set_name`): the app's own address book.
  final Map<String, String> names;

  /// The calls that ended, oldest first, kept across restarts.
  final List<CallRecord> history;

  /// A voice message or voicemail being recorded, and what plays.
  final VoiceState voice;

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
    video: j['video'] as bool? ?? false,
    messaging: Messaging.fromJson(j['messaging'] as Map<String, dynamic>),
    presence: PresenceState.fromJson(j['presence'] as Map<String, dynamic>? ?? const {}),
    names: (j['names'] as Map<String, dynamic>? ?? const {}).cast<String, String>(),
    history: [for (final c in j['history'] as List? ?? const []) CallRecord.fromJson(c as Map<String, dynamic>)],
    voice: VoiceState.fromJson(j['voice'] as Map<String, dynamic>? ?? const {}),
  );
}

/// Recording and playing voice messages and voicemail.
class VoiceState {
  const VoiceState({this.recording, this.playing});

  /// The recording, under way or stopped at its limit and waiting to be sent or dropped.
  final Recording? recording;

  /// The file playing.
  final String? playing;

  factory VoiceState.fromJson(Map<String, dynamic> j) => VoiceState(
    recording: j['recording'] == null ? null : Recording.fromJson(j['recording'] as Map<String, dynamic>),
    playing: j['playing'] as String?,
  );
}

/// A recording ([VoiceState.recording]).
class Recording {
  const Recording({required this.running, required this.startedAt, this.maxMs, this.durationMs});

  /// Under way; false: it stopped (at its limit, or for a call) and waits to be sent or dropped.
  final bool running;

  /// Unix seconds.
  final int startedAt;

  /// Where it stops by itself (a voicemail's limit).
  final int? maxMs;

  /// Its length, once stopped.
  final int? durationMs;

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
    running: j['running'] as bool,
    startedAt: j['started_at'] as int,
    maxMs: j['max_ms'] as int?,
    durationMs: j['duration_ms'] as int?,
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
    this.name,
    this.contentType,
    this.size,
    this.path,
    this.purpose,
    this.durationMs,
    this.session,
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

  /// An attachment's name, media type and size.
  final String? name;
  final String? contentType;
  final int? size;

  /// An attachment's file on this device, once fetched.
  final String? path;

  /// Why it was sent: an `audio`'s `voice` or `voicemail`, an attachment's `attachment`.
  final String? purpose;

  /// An `audio`'s length.
  final int? durationMs;

  /// A voicemail's call.
  final String? session;

  /// A voice message or a voicemail: played where it is shown.
  bool get audio => kind == 'audio';

  /// Left after a call that was not answered.
  bool get voicemail => purpose == 'voicemail';

  /// Whether it carries a file (an `image`, a `file`, or a kind with a media type).
  bool get attachment => contentType != null || kind == 'image' || kind == 'file';

  MessageView withPath(String path) => MessageView(
    conversation: conversation,
    id: id,
    from: from,
    mine: mine,
    kind: kind,
    text: text,
    sentAt: sentAt,
    name: name,
    contentType: contentType,
    size: size,
    path: path,
    purpose: purpose,
    durationMs: durationMs,
    session: session,
  );

  factory MessageView.fromJson(Map<String, dynamic> j) => MessageView(
    conversation: j['conversation'] as String,
    id: j['id'] as String,
    from: j['from'] as String,
    mine: j['mine'] as bool,
    kind: j['kind'] as String,
    text: j['text'] as String?,
    sentAt: j['sent_at'] as int,
    name: j['name'] as String?,
    contentType: j['content_type'] as String?,
    size: j['size'] as int?,
    path: j['path'] as String?,
    purpose: j['purpose'] as String?,
    durationMs: j['duration_ms'] as int?,
    session: j['session'] as String?,
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
