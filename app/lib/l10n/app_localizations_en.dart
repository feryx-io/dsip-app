// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class StringsEn extends Strings {
  StringsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DSIP';

  @override
  String get firstRunTitle => 'Welcome to DSIP';

  @override
  String get firstRunIntro =>
      'Your identity is yours: a key on this device, not an account on a server. Make one, or use one you already have.';

  @override
  String get firstRunNew => 'Make an identity';

  @override
  String get firstRunExisting => 'Use an identity folder';

  @override
  String get firstRunName => 'Your name';

  @override
  String get firstRunNameHint =>
      'What others see when you call or write (they are told it is your claim)';

  @override
  String get firstRunNameNeeded => 'Enter your name.';

  @override
  String get firstRunFolder => 'Identity folder';

  @override
  String get firstRunFolderHint =>
      'A folder made by dsip-app init or dsip identity init';

  @override
  String get firstRunFolderNeeded => 'Enter the identity folder.';

  @override
  String get firstRunRestore => 'Restore from a backup';

  @override
  String get firstRunCode => 'Recovery code';

  @override
  String get firstRunCodeHint =>
      'DSIP1-… as you wrote it down or saved it, or the backup file\'s text';

  @override
  String get firstRunCodeNeeded => 'Enter the recovery code.';

  @override
  String get backupPassphrase => 'Passphrase';

  @override
  String get backupPassphraseNeeded => 'Enter the passphrase.';

  @override
  String get firstRunRelay => 'Relay';

  @override
  String get firstRunRelayHint => 'wss://relay.example.com:8443/dsip';

  @override
  String get firstRunRelayNeeded =>
      'Enter a relay address starting with wss://.';

  @override
  String get firstRunMailbox => 'Mailbox (for messages, optional)';

  @override
  String get firstRunMailboxHint => 'wss://mailbox.example.com:9443/dsip';

  @override
  String get firstRunMailboxDid => 'Mailbox DID';

  @override
  String get firstRunMailboxDidNeeded => 'A mailbox needs its DID too.';

  @override
  String get firstRunHints => 'Hints node (optional)';

  @override
  String get firstRunHintsHint => 'https://hints.example.com';

  @override
  String get firstRunStart => 'Start';

  @override
  String firstRunFailed(String reason) {
    return 'Could not start: $reason';
  }

  @override
  String get navCalls => 'Calls';

  @override
  String get navMe => 'Me';

  @override
  String get callTo => 'Identity to call';

  @override
  String get callToHint => 'did:key:… or did:web:…';

  @override
  String get callButton => 'Call';

  @override
  String get callAnswer => 'Answer';

  @override
  String get callDecline => 'Decline';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callMute => 'Mute';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get callCalling => 'Calling…';

  @override
  String get callRingingThere => 'Ringing…';

  @override
  String get callRingingHere => 'Incoming call';

  @override
  String get callAnswered => 'In call';

  @override
  String callAnsweredBy(String by) {
    return 'Answered by $by';
  }

  @override
  String callEnded(String reason) {
    return 'Ended: $reason';
  }

  @override
  String get callNoSound => 'No sound yet';

  @override
  String callVia(String relay) {
    return 'Through $relay';
  }

  @override
  String get callsNone => 'No calls. Enter an identity above to call it.';

  @override
  String get callsRecent => 'Recent';

  @override
  String get meIdentity => 'Identity';

  @override
  String get meDevice => 'This device';

  @override
  String get meRelay => 'Relay';

  @override
  String get meMailbox => 'Mailbox';

  @override
  String get meMailboxConnected => 'Connected';

  @override
  String get meMailboxOffline => 'Not connected';

  @override
  String get meMailboxNone => 'None: calls only';

  @override
  String get meCopy => 'Copy';

  @override
  String get meCopied => 'Copied';

  @override
  String commandFailed(String reason) {
    return '$reason';
  }

  @override
  String get appStopped => 'The app stopped.';

  @override
  String get navMessages => 'Messages';

  @override
  String get messagingOff =>
      'Messaging is off: this app has no mailbox. Add one in its settings to message.';

  @override
  String get messagingOffline =>
      'Not connected to your mailbox: messages go out once it is back.';

  @override
  String get requestsTitle => 'Asking to message you';

  @override
  String requestFrom(String name) {
    return '$name (says they are)';
  }

  @override
  String get requestAccept => 'Accept';

  @override
  String get requestDecline => 'Decline';

  @override
  String get conversationsTitle => 'Conversations';

  @override
  String get conversationsNone =>
      'No conversations yet. Introduce yourself to someone, and message them once they accept.';

  @override
  String conversationGroup(int count) {
    return 'Group of $count';
  }

  @override
  String conversationPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages not yet at the hub',
      one: '1 message not yet at the hub',
    );
    return '$_temp0';
  }

  @override
  String get actionIntroduce => 'Introduce yourself';

  @override
  String get actionNewMessage => 'New message';

  @override
  String get actionNewGroup => 'New group';

  @override
  String get introduceTitle => 'Introduce yourself';

  @override
  String get introduceTo => 'Their identity';

  @override
  String get introducePurpose => 'Why you are writing';

  @override
  String get introducePurposeHint => 'Only they can read it';

  @override
  String get introduceSent => 'Asked. You can message them once they accept.';

  @override
  String get newMessageTo => 'To (an identity that accepted you)';

  @override
  String get newGroupMembers => 'Members, one identity per line';

  @override
  String get newGroupHint => 'Each must have accepted you';

  @override
  String get send => 'Send';

  @override
  String get cancel => 'Cancel';

  @override
  String get messageHint => 'Message';

  @override
  String get threadEmpty => 'No messages yet.';

  @override
  String threadNotText(String kind) {
    return '($kind message)';
  }

  @override
  String get threadMembers => 'Members';

  @override
  String get threadAddMember => 'Add someone';

  @override
  String get threadRemove => 'Remove';

  @override
  String get threadLeave => 'Leave';

  @override
  String get threadLeaveConfirm =>
      'Leave this conversation? The others keep it; you no longer see it.';

  @override
  String noticeGranted(String who) {
    return '$who accepted: you can message them, call them and see their presence.';
  }

  @override
  String noticeRemoved(String who) {
    return '$who removed you from a conversation.';
  }

  @override
  String get navPresence => 'Presence';

  @override
  String get presenceMine => 'Your presence';

  @override
  String get presenceAutomatic => 'Automatic';

  @override
  String get presenceAvailable => 'Available';

  @override
  String get presenceBusy => 'Busy';

  @override
  String get presenceAway => 'Away';

  @override
  String get presenceDnd => 'Do not disturb';

  @override
  String get presenceOffline => 'Invisible';

  @override
  String get presenceAutomaticExplained =>
      'Those who follow you see you available while this app is connected, and offline when it is not.';

  @override
  String get presenceSetExplained =>
      'Those who follow you see this, sealed so that only they can read it: not your relay.';

  @override
  String get presenceOfflineExplained =>
      'Those who follow you see you offline. Calls still reach you.';

  @override
  String get presenceFollowing => 'Following';

  @override
  String get presenceFollow => 'Follow someone';

  @override
  String get presenceFollowHint =>
      'They see that you follow them; their presence shows once they have accepted you';

  @override
  String get presenceNone =>
      'You follow no one. Those who accept you are followed for you.';

  @override
  String get presenceWaiting =>
      'Not shown: they have not accepted you, or their relay is out of reach';

  @override
  String get presenceByRelay => 'their relay says they are connected';

  @override
  String presenceSealed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices sealed to others',
      one: '1 device sealed to others',
    );
    return '$_temp0';
  }

  @override
  String get presenceMore => 'More';

  @override
  String get presenceUnfollow => 'Stop following';

  @override
  String get presenceStopSharing => 'Stop sharing with them';

  @override
  String presenceStopSharingConfirm(String who) {
    return 'Withdraw what you granted $who? They can no longer call you or follow your presence, and your presence keys change for everyone else who follows you.';
  }

  @override
  String presenceRevoked(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Withdrew $count grants from $who.',
      one: 'Withdrew 1 grant from $who.',
      zero: '$who held no grant of yours.',
    );
    return '$_temp0';
  }

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsSoundTone =>
      'This app plays a test tone instead of using a microphone and speaker.';

  @override
  String get settingsSoundNone => 'Calls have no sound in this app.';

  @override
  String get settingsMicrophone => 'Microphone';

  @override
  String get settingsSpeaker => 'Speaker';

  @override
  String get settingsSoundDefault => 'The system\'s default';

  @override
  String settingsSoundSystemDefault(String name) {
    return '$name (the system\'s default)';
  }

  @override
  String get settingsSoundRefresh => 'Look for devices again';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsIdentityFolder => 'Identity folder';

  @override
  String get settingsStun => 'STUN server (optional)';

  @override
  String get settingsStunHint => 'stun:stun.example.com:3478';

  @override
  String get settingsSave => 'Save and restart';

  @override
  String get settingsRestartTitle => 'Restart the app?';

  @override
  String get settingsRestartBody =>
      'The app disconnects and connects again with these settings.';

  @override
  String get settingsRestartCalls =>
      'The app disconnects and connects again with these settings. Calls in progress end.';

  @override
  String get settingsRestart => 'Restart';

  @override
  String get settingsBackup => 'Identity backup';

  @override
  String get settingsBackupIntro =>
      'Your identity is a key on this device. If this device is lost, a backup is the only way to keep your identity: a recovery code, sealed under a passphrase you choose.';

  @override
  String get settingsBackupMake => 'Back up';

  @override
  String get backupTitle => 'Back up your identity';

  @override
  String get backupPassphraseHint =>
      'At least 10 characters. Without it, the code opens nothing: keep them apart.';

  @override
  String get backupPassphraseShort => 'Use at least 10 characters.';

  @override
  String get backupPassphraseAgain => 'The passphrase again';

  @override
  String get backupPassphraseDiffers => 'The two passphrases differ.';

  @override
  String get backupMake => 'Make the code';

  @override
  String get backupCodeTitle => 'Your recovery code';

  @override
  String get backupCodeBody =>
      'Write it down or keep it somewhere safe, with the passphrase apart. Anyone with both is you.';

  @override
  String get backupCopy => 'Copy';

  @override
  String get backupCopied => 'Copied.';

  @override
  String get backupDone => 'Done';

  @override
  String get backupCancel => 'Cancel';

  @override
  String backupFailed(String reason) {
    return 'No backup: $reason';
  }

  @override
  String get settingsWeb => 'Your own domain';

  @override
  String get settingsWebIntro =>
      'Use a DID on a domain you control (did:web) in place of this device\'s key. You can then change keys without losing the identity. People who know you now will see it as a new identity, and need to accept you again.';

  @override
  String get settingsWebStart => 'Set up';

  @override
  String get webTitle => 'Your own domain';

  @override
  String get webDid => 'Your did:web';

  @override
  String get webDidHint =>
      'did:web:example.com, or did:web:example.com:users:ann';

  @override
  String get webDidNeeded => 'Enter a DID that starts with did:web:';

  @override
  String get webPrepare => 'Make the document';

  @override
  String webServe(String url) {
    return 'Serve this at $url, then check.';
  }

  @override
  String get webCheck => 'Check';

  @override
  String get webServed => 'Your domain serves the document.';

  @override
  String webDiffers(String differences) {
    return 'Not yet: $differences';
  }

  @override
  String get webMove => 'Move to it';

  @override
  String get webMoveConfirmTitle => 'Move your identity?';

  @override
  String webMoveConfirm(String did) {
    return 'You become $did. The app restarts, and calls in progress end. Contacts see a new identity and need to accept you again.';
  }

  @override
  String webFailed(String reason) {
    return 'That did not work: $reason';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'DSIP $version';
  }

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get updateLatest => 'This is the latest version.';

  @override
  String updateAvailable(String version) {
    return 'DSIP $version is out.';
  }

  @override
  String updateAfterCall(String version) {
    return 'DSIP $version is out: update once your call is over.';
  }

  @override
  String updateByHand(String version, String reason) {
    return 'DSIP $version is out. This copy does not update itself ($reason).';
  }

  @override
  String updateDownloading(String version) {
    return 'Getting DSIP $version…';
  }

  @override
  String updateFailed(String reason) {
    return 'Could not update: $reason';
  }

  @override
  String get updateInstall => 'Update and restart';

  @override
  String get updateDownload => 'Download';

  @override
  String get updateLater => 'Later';

  @override
  String get updateNotes => 'What\'s new';

  @override
  String get microphoneRefused =>
      'DSIP may not use the microphone, so the people you call will not hear you. Allow it in the system\'s settings for DSIP.';

  @override
  String get routeEarpiece => 'Phone';

  @override
  String get routeSpeaker => 'Speaker';

  @override
  String get routeBluetooth => 'Bluetooth';

  @override
  String get routeWired => 'Headset';
}

/// The translations for English (`en_XA`).
class StringsEnXa extends StringsEn {
  StringsEnXa() : super('en_XA');

  @override
  String get appName => '[ĐŠÍÞ ]';

  @override
  String get firstRunTitle => '[Ŵéĺçóɱé ţó ĐŠÍÞ one]';

  @override
  String get firstRunIntro =>
      '[Ýóúŕ íđéñţíţý íš ýóúŕš: à ķéý óñ ţĥíš đéṽíçé, ñóţ àñ àççóúñţ óñ à šéŕṽéŕ. Ḿàķé óñé, óŕ úšé óñé ýóú àĺŕéàđý ĥàṽé. one two three four five six]';

  @override
  String get firstRunNew => '[Ḿàķé àñ íđéñţíţý one]';

  @override
  String get firstRunExisting => '[Úšé àñ íđéñţíţý ƒóĺđéŕ one t]';

  @override
  String get firstRunName => '[Ýóúŕ ñàɱé o]';

  @override
  String get firstRunNameHint =>
      '[Ŵĥàţ óţĥéŕš šéé ŵĥéñ ýóú çàĺĺ óŕ ŵŕíţé (ţĥéý àŕé ţóĺđ íţ íš ýóúŕ çĺàíɱ) one two three fou]';

  @override
  String get firstRunNameNeeded => '[Éñţéŕ ýóúŕ ñàɱé. one]';

  @override
  String get firstRunFolder => '[Íđéñţíţý ƒóĺđéŕ one]';

  @override
  String get firstRunFolderHint =>
      '[À ƒóĺđéŕ ɱàđé ƀý đšíþ-àþþ íñíţ óŕ đšíþ íđéñţíţý íñíţ one two three]';

  @override
  String get firstRunFolderNeeded => '[Éñţéŕ ţĥé íđéñţíţý ƒóĺđéŕ. one tw]';

  @override
  String get firstRunRestore => '[Ŕéšţóŕé ƒŕóɱ à ƀàçķúþ one t]';

  @override
  String get firstRunCode => '[Ŕéçóṽéŕý çóđé one]';

  @override
  String get firstRunCodeHint =>
      '[ĐŠÍÞ1-… àš ýóú ŵŕóţé íţ đóŵñ óŕ šàṽéđ íţ, óŕ ţĥé ƀàçķúþ ƒíĺé\'š ţéẋţ one two three f]';

  @override
  String get firstRunCodeNeeded => '[Éñţéŕ ţĥé ŕéçóṽéŕý çóđé. one t]';

  @override
  String get backupPassphrase => '[Þàššþĥŕàšé on]';

  @override
  String get backupPassphraseNeeded => '[Éñţéŕ ţĥé þàššþĥŕàšé. one t]';

  @override
  String get firstRunRelay => '[Ŕéĺàý ]';

  @override
  String get firstRunRelayHint => '[ŵšš://ŕéĺàý.éẋàɱþĺé.çóɱ:8443/đšíþ one tw]';

  @override
  String get firstRunRelayNeeded =>
      '[Éñţéŕ à ŕéĺàý àđđŕéšš šţàŕţíñĝ ŵíţĥ ŵšš://. one two th]';

  @override
  String get firstRunMailbox => '[Ḿàíĺƀóẋ (ƒóŕ ɱéššàĝéš, óþţíóñàĺ) one two]';

  @override
  String get firstRunMailboxHint =>
      '[ŵšš://ɱàíĺƀóẋ.éẋàɱþĺé.çóɱ:9443/đšíþ one two]';

  @override
  String get firstRunMailboxDid => '[Ḿàíĺƀóẋ ĐÍĐ on]';

  @override
  String get firstRunMailboxDidNeeded =>
      '[À ɱàíĺƀóẋ ñééđš íţš ĐÍĐ ţóó. one tw]';

  @override
  String get firstRunHints => '[Ĥíñţš ñóđé (óþţíóñàĺ) one ]';

  @override
  String get firstRunHintsHint => '[ĥţţþš://ĥíñţš.éẋàɱþĺé.çóɱ one t]';

  @override
  String get firstRunStart => '[Šţàŕţ ]';

  @override
  String firstRunFailed(String reason) {
    return '[Çóúĺđ ñóţ šţàŕţ: $reason one t]';
  }

  @override
  String get navCalls => '[Çàĺĺš ]';

  @override
  String get navMe => '[Ḿé ]';

  @override
  String get callTo => '[Íđéñţíţý ţó çàĺĺ one]';

  @override
  String get callToHint => '[đíđ:ķéý:… óŕ đíđ:ŵéƀ:… one]';

  @override
  String get callButton => '[Çàĺĺ ]';

  @override
  String get callAnswer => '[Àñšŵéŕ o]';

  @override
  String get callDecline => '[Đéçĺíñé o]';

  @override
  String get callHangUp => '[Ĥàñĝ úþ o]';

  @override
  String get callMute => '[Ḿúţé ]';

  @override
  String get callUnmute => '[Úñɱúţé o]';

  @override
  String get callCalling => '[Çàĺĺíñĝ… o]';

  @override
  String get callRingingThere => '[Ŕíñĝíñĝ… o]';

  @override
  String get callRingingHere => '[Íñçóɱíñĝ çàĺĺ one]';

  @override
  String get callAnswered => '[Íñ çàĺĺ o]';

  @override
  String callAnsweredBy(String by) {
    return '[Àñšŵéŕéđ ƀý $by one]';
  }

  @override
  String callEnded(String reason) {
    return '[Éñđéđ: $reason on]';
  }

  @override
  String get callNoSound => '[Ñó šóúñđ ýéţ on]';

  @override
  String callVia(String relay) {
    return '[Ţĥŕóúĝĥ $relay one]';
  }

  @override
  String get callsNone =>
      '[Ñó çàĺĺš. Éñţéŕ àñ íđéñţíţý àƀóṽé ţó çàĺĺ íţ. one two th]';

  @override
  String get callsRecent => '[Ŕéçéñţ o]';

  @override
  String get meIdentity => '[Íđéñţíţý o]';

  @override
  String get meDevice => '[Ţĥíš đéṽíçé on]';

  @override
  String get meRelay => '[Ŕéĺàý ]';

  @override
  String get meMailbox => '[Ḿàíĺƀóẋ o]';

  @override
  String get meMailboxConnected => '[Çóññéçţéđ on]';

  @override
  String get meMailboxOffline => '[Ñóţ çóññéçţéđ one]';

  @override
  String get meMailboxNone => '[Ñóñé: çàĺĺš óñĺý one]';

  @override
  String get meCopy => '[Çóþý ]';

  @override
  String get meCopied => '[Çóþíéđ o]';

  @override
  String commandFailed(String reason) {
    return '[$reason o]';
  }

  @override
  String get appStopped => '[Ţĥé àþþ šţóþþéđ. one]';

  @override
  String get navMessages => '[Ḿéššàĝéš o]';

  @override
  String get messagingOff =>
      '[Ḿéššàĝíñĝ íš óƒƒ: ţĥíš àþþ ĥàš ñó ɱàíĺƀóẋ. Àđđ óñé íñ íţš šéţţíñĝš ţó ɱéššàĝé. one two three four ]';

  @override
  String get messagingOffline =>
      '[Ñóţ çóññéçţéđ ţó ýóúŕ ɱàíĺƀóẋ: ɱéššàĝéš ĝó óúţ óñçé íţ íš ƀàçķ. one two three f]';

  @override
  String get requestsTitle => '[Àšķíñĝ ţó ɱéššàĝé ýóú one t]';

  @override
  String requestFrom(String name) {
    return '[$name (šàýš ţĥéý àŕé) one ]';
  }

  @override
  String get requestAccept => '[Àççéþţ o]';

  @override
  String get requestDecline => '[Đéçĺíñé o]';

  @override
  String get conversationsTitle => '[Çóñṽéŕšàţíóñš one]';

  @override
  String get conversationsNone =>
      '[Ñó çóñṽéŕšàţíóñš ýéţ. Íñţŕóđúçé ýóúŕšéĺƒ ţó šóɱéóñé, àñđ ɱéššàĝé ţĥéɱ óñçé ţĥéý àççéþţ. one two three four five]';

  @override
  String conversationGroup(int count) {
    return '[Ĝŕóúþ óƒ $count one]';
  }

  @override
  String conversationPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ɱéššàĝéš ñóţ ýéţ àţ ţĥé ĥúƀ',
      one: '1 ɱéššàĝé ñóţ ýéţ àţ ţĥé ĥúƀ',
    );
    return '[$_temp0 one two three four f]';
  }

  @override
  String get actionIntroduce => '[Íñţŕóđúçé ýóúŕšéĺƒ one ]';

  @override
  String get actionNewMessage => '[Ñéŵ ɱéššàĝé on]';

  @override
  String get actionNewGroup => '[Ñéŵ ĝŕóúþ o]';

  @override
  String get introduceTitle => '[Íñţŕóđúçé ýóúŕšéĺƒ one ]';

  @override
  String get introduceTo => '[Ţĥéíŕ íđéñţíţý one]';

  @override
  String get introducePurpose => '[Ŵĥý ýóú àŕé ŵŕíţíñĝ one ]';

  @override
  String get introducePurposeHint => '[Óñĺý ţĥéý çàñ ŕéàđ íţ one ]';

  @override
  String get introduceSent =>
      '[Àšķéđ. Ýóú çàñ ɱéššàĝé ţĥéɱ óñçé ţĥéý àççéþţ. one two thr]';

  @override
  String get newMessageTo => '[Ţó (àñ íđéñţíţý ţĥàţ àççéþţéđ ýóú) one two ]';

  @override
  String get newGroupMembers => '[Ḿéɱƀéŕš, óñé íđéñţíţý þéŕ ĺíñé one two]';

  @override
  String get newGroupHint => '[Éàçĥ ɱúšţ ĥàṽé àççéþţéđ ýóú one tw]';

  @override
  String get send => '[Šéñđ ]';

  @override
  String get cancel => '[Çàñçéĺ o]';

  @override
  String get messageHint => '[Ḿéššàĝé o]';

  @override
  String get threadEmpty => '[Ñó ɱéššàĝéš ýéţ. one]';

  @override
  String threadNotText(String kind) {
    return '[($kind ɱéššàĝé) on]';
  }

  @override
  String get threadMembers => '[Ḿéɱƀéŕš o]';

  @override
  String get threadAddMember => '[Àđđ šóɱéóñé on]';

  @override
  String get threadRemove => '[Ŕéɱóṽé o]';

  @override
  String get threadLeave => '[Ĺéàṽé ]';

  @override
  String get threadLeaveConfirm =>
      '[Ĺéàṽé ţĥíš çóñṽéŕšàţíóñ? Ţĥé óţĥéŕš ķééþ íţ; ýóú ñó ĺóñĝéŕ šéé íţ. one two three fo]';

  @override
  String noticeGranted(String who) {
    return '[$who àççéþţéđ: ýóú çàñ ɱéššàĝé ţĥéɱ, çàĺĺ ţĥéɱ àñđ šéé ţĥéíŕ þŕéšéñçé. one two three fou]';
  }

  @override
  String noticeRemoved(String who) {
    return '[$who ŕéɱóṽéđ ýóú ƒŕóɱ à çóñṽéŕšàţíóñ. one two t]';
  }

  @override
  String get navPresence => '[Þŕéšéñçé o]';

  @override
  String get presenceMine => '[Ýóúŕ þŕéšéñçé one]';

  @override
  String get presenceAutomatic => '[Àúţóɱàţíç on]';

  @override
  String get presenceAvailable => '[Àṽàíĺàƀĺé on]';

  @override
  String get presenceBusy => '[Ɓúšý ]';

  @override
  String get presenceAway => '[Àŵàý ]';

  @override
  String get presenceDnd => '[Đó ñóţ đíšţúŕƀ one]';

  @override
  String get presenceOffline => '[Íñṽíšíƀĺé on]';

  @override
  String get presenceAutomaticExplained =>
      '[Ţĥóšé ŵĥó ƒóĺĺóŵ ýóú šéé ýóú àṽàíĺàƀĺé ŵĥíĺé ţĥíš àþþ íš çóññéçţéđ, àñđ óƒƒĺíñé ŵĥéñ íţ íš ñóţ. one two three four five ]';

  @override
  String get presenceSetExplained =>
      '[Ţĥóšé ŵĥó ƒóĺĺóŵ ýóú šéé ţĥíš, šéàĺéđ šó ţĥàţ óñĺý ţĥéý çàñ ŕéàđ íţ: ñóţ ýóúŕ ŕéĺàý. one two three four f]';

  @override
  String get presenceOfflineExplained =>
      '[Ţĥóšé ŵĥó ƒóĺĺóŵ ýóú šéé ýóú óƒƒĺíñé. Çàĺĺš šţíĺĺ ŕéàçĥ ýóú. one two three f]';

  @override
  String get presenceFollowing => '[Ƒóĺĺóŵíñĝ on]';

  @override
  String get presenceFollow => '[Ƒóĺĺóŵ šóɱéóñé one]';

  @override
  String get presenceFollowHint =>
      '[Ţĥéý šéé ţĥàţ ýóú ƒóĺĺóŵ ţĥéɱ; ţĥéíŕ þŕéšéñçé šĥóŵš óñçé ţĥéý ĥàṽé àççéþţéđ ýóú one two three four f]';

  @override
  String get presenceNone =>
      '[Ýóú ƒóĺĺóŵ ñó óñé. Ţĥóšé ŵĥó àççéþţ ýóú àŕé ƒóĺĺóŵéđ ƒóŕ ýóú. one two three f]';

  @override
  String get presenceWaiting =>
      '[Ñóţ šĥóŵñ: ţĥéý ĥàṽé ñóţ àççéþţéđ ýóú, óŕ ţĥéíŕ ŕéĺàý íš óúţ óƒ ŕéàçĥ one two three fou]';

  @override
  String get presenceByRelay =>
      '[ţĥéíŕ ŕéĺàý šàýš ţĥéý àŕé çóññéçţéđ one two t]';

  @override
  String presenceSealed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count đéṽíçéš šéàĺéđ ţó óţĥéŕš',
      one: '1 đéṽíçé šéàĺéđ ţó óţĥéŕš',
    );
    return '[$_temp0 one two three four ]';
  }

  @override
  String get presenceMore => '[Ḿóŕé ]';

  @override
  String get presenceUnfollow => '[Šţóþ ƒóĺĺóŵíñĝ one]';

  @override
  String get presenceStopSharing => '[Šţóþ šĥàŕíñĝ ŵíţĥ ţĥéɱ one t]';

  @override
  String presenceStopSharingConfirm(String who) {
    return '[Ŵíţĥđŕàŵ ŵĥàţ ýóú ĝŕàñţéđ $who? Ţĥéý çàñ ñó ĺóñĝéŕ çàĺĺ ýóú óŕ ƒóĺĺóŵ ýóúŕ þŕéšéñçé, àñđ ýóúŕ þŕéšéñçé ķéýš çĥàñĝé ƒóŕ éṽéŕýóñé éĺšé ŵĥó ƒóĺĺóŵš ýóú. one two three four five six seven eight]';
  }

  @override
  String presenceRevoked(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ŵíţĥđŕéŵ $count ĝŕàñţš ƒŕóɱ $who.',
      one: 'Ŵíţĥđŕéŵ 1 ĝŕàñţ ƒŕóɱ $who.',
      zero: '$who ĥéĺđ ñó ĝŕàñţ óƒ ýóúŕš.',
    );
    return '[$_temp0 one two three four five si]';
  }

  @override
  String get navSettings => '[Šéţţíñĝš o]';

  @override
  String get settingsSound => '[Šóúñđ ]';

  @override
  String get settingsSoundTone =>
      '[Ţĥíš àþþ þĺàýš à ţéšţ ţóñé íñšţéàđ óƒ úšíñĝ à ɱíçŕóþĥóñé àñđ šþéàķéŕ. one two three fou]';

  @override
  String get settingsSoundNone => '[Çàĺĺš ĥàṽé ñó šóúñđ íñ ţĥíš àþþ. one two]';

  @override
  String get settingsMicrophone => '[Ḿíçŕóþĥóñé on]';

  @override
  String get settingsSpeaker => '[Šþéàķéŕ o]';

  @override
  String get settingsSoundDefault => '[Ţĥé šýšţéɱ\'š đéƒàúĺţ one ]';

  @override
  String settingsSoundSystemDefault(String name) {
    return '[$name (ţĥé šýšţéɱ\'š đéƒàúĺţ) one tw]';
  }

  @override
  String get settingsSoundRefresh => '[Ĺóóķ ƒóŕ đéṽíçéš àĝàíñ one t]';

  @override
  String get settingsConnection => '[Çóññéçţíóñ on]';

  @override
  String get settingsIdentityFolder => '[Íđéñţíţý ƒóĺđéŕ one]';

  @override
  String get settingsStun => '[ŠŢÚÑ šéŕṽéŕ (óþţíóñàĺ) one t]';

  @override
  String get settingsStunHint => '[šţúñ:šţúñ.éẋàɱþĺé.çóɱ:3478 one t]';

  @override
  String get settingsSave => '[Šàṽé àñđ ŕéšţàŕţ one]';

  @override
  String get settingsRestartTitle => '[Ŕéšţàŕţ ţĥé àþþ? one]';

  @override
  String get settingsRestartBody =>
      '[Ţĥé àþþ đíšçóññéçţš àñđ çóññéçţš àĝàíñ ŵíţĥ ţĥéšé šéţţíñĝš. one two three f]';

  @override
  String get settingsRestartCalls =>
      '[Ţĥé àþþ đíšçóññéçţš àñđ çóññéçţš àĝàíñ ŵíţĥ ţĥéšé šéţţíñĝš. Çàĺĺš íñ þŕóĝŕéšš éñđ. one two three four fi]';

  @override
  String get settingsRestart => '[Ŕéšţàŕţ o]';

  @override
  String get settingsBackup => '[Íđéñţíţý ƀàçķúþ one]';

  @override
  String get settingsBackupIntro =>
      '[Ýóúŕ íđéñţíţý íš à ķéý óñ ţĥíš đéṽíçé. Íƒ ţĥíš đéṽíçé íš ĺóšţ, à ƀàçķúþ íš ţĥé óñĺý ŵàý ţó ķééþ ýóúŕ íđéñţíţý: à ŕéçóṽéŕý çóđé, šéàĺéđ úñđéŕ à þàššþĥŕàšé ýóú çĥóóšé. one two three four five six seven eight ni]';

  @override
  String get settingsBackupMake => '[Ɓàçķ úþ o]';

  @override
  String get backupTitle => '[Ɓàçķ úþ ýóúŕ íđéñţíţý one t]';

  @override
  String get backupPassphraseHint =>
      '[Àţ ĺéàšţ 10 çĥàŕàçţéŕš. Ŵíţĥóúţ íţ, ţĥé çóđé óþéñš ñóţĥíñĝ: ķééþ ţĥéɱ àþàŕţ. one two three four]';

  @override
  String get backupPassphraseShort => '[Úšé àţ ĺéàšţ 10 çĥàŕàçţéŕš. one t]';

  @override
  String get backupPassphraseAgain => '[Ţĥé þàššþĥŕàšé àĝàíñ one t]';

  @override
  String get backupPassphraseDiffers => '[Ţĥé ţŵó þàššþĥŕàšéš đíƒƒéŕ. one tw]';

  @override
  String get backupMake => '[Ḿàķé ţĥé çóđé on]';

  @override
  String get backupCodeTitle => '[Ýóúŕ ŕéçóṽéŕý çóđé one ]';

  @override
  String get backupCodeBody =>
      '[Ŵŕíţé íţ đóŵñ óŕ ķééþ íţ šóɱéŵĥéŕé šàƒé, ŵíţĥ ţĥé þàššþĥŕàšé àþàŕţ. Àñýóñé ŵíţĥ ƀóţĥ íš ýóú. one two three four five]';

  @override
  String get backupCopy => '[Çóþý ]';

  @override
  String get backupCopied => '[Çóþíéđ. o]';

  @override
  String get backupDone => '[Đóñé ]';

  @override
  String get backupCancel => '[Çàñçéĺ o]';

  @override
  String backupFailed(String reason) {
    return '[Ñó ƀàçķúþ: $reason one]';
  }

  @override
  String get settingsWeb => '[Ýóúŕ óŵñ đóɱàíñ one]';

  @override
  String get settingsWebIntro =>
      '[Úšé à ĐÍĐ óñ à đóɱàíñ ýóú çóñţŕóĺ (đíđ:ŵéƀ) íñ þĺàçé óƒ ţĥíš đéṽíçé\'š ķéý. Ýóú çàñ ţĥéñ çĥàñĝé ķéýš ŵíţĥóúţ ĺóšíñĝ ţĥé íđéñţíţý. Þéóþĺé ŵĥó ķñóŵ ýóú ñóŵ ŵíĺĺ šéé íţ àš à ñéŵ íđéñţíţý, àñđ ñééđ ţó àççéþţ ýóú àĝàíñ. one two three four five six seven eight nine ten]';

  @override
  String get settingsWebStart => '[Šéţ úþ ]';

  @override
  String get webTitle => '[Ýóúŕ óŵñ đóɱàíñ one]';

  @override
  String get webDid => '[Ýóúŕ đíđ:ŵéƀ on]';

  @override
  String get webDidHint =>
      '[đíđ:ŵéƀ:éẋàɱþĺé.çóɱ, óŕ đíđ:ŵéƀ:éẋàɱþĺé.çóɱ:úšéŕš:àññ one two three]';

  @override
  String get webDidNeeded => '[Éñţéŕ à ĐÍĐ ţĥàţ šţàŕţš ŵíţĥ đíđ:ŵéƀ: one two ]';

  @override
  String get webPrepare => '[Ḿàķé ţĥé đóçúɱéñţ one ]';

  @override
  String webServe(String url) {
    return '[Šéŕṽé ţĥíš àţ $url, ţĥéñ çĥéçķ. one tw]';
  }

  @override
  String get webCheck => '[Çĥéçķ ]';

  @override
  String get webServed => '[Ýóúŕ đóɱàíñ šéŕṽéš ţĥé đóçúɱéñţ. one two ]';

  @override
  String webDiffers(String differences) {
    return '[Ñóţ ýéţ: $differences one ]';
  }

  @override
  String get webMove => '[Ḿóṽé ţó íţ o]';

  @override
  String get webMoveConfirmTitle => '[Ḿóṽé ýóúŕ íđéñţíţý? one ]';

  @override
  String webMoveConfirm(String did) {
    return '[Ýóú ƀéçóɱé $did. Ţĥé àþþ ŕéšţàŕţš, àñđ çàĺĺš íñ þŕóĝŕéšš éñđ. Çóñţàçţš šéé à ñéŵ íđéñţíţý àñđ ñééđ ţó àççéþţ ýóú àĝàíñ. one two three four five six se]';
  }

  @override
  String webFailed(String reason) {
    return '[Ţĥàţ đíđ ñóţ ŵóŕķ: $reason one t]';
  }

  @override
  String get settingsAbout => '[Àƀóúţ ]';

  @override
  String settingsVersion(String version) {
    return '[ĐŠÍÞ $version on]';
  }

  @override
  String get updateCheck => '[Çĥéçķ ƒóŕ úþđàţéš one ]';

  @override
  String get updateChecking => '[Çĥéçķíñĝ… o]';

  @override
  String get updateLatest => '[Ţĥíš íš ţĥé ĺàţéšţ ṽéŕšíóñ. one tw]';

  @override
  String updateAvailable(String version) {
    return '[ĐŠÍÞ $version íš óúţ. one ]';
  }

  @override
  String updateAfterCall(String version) {
    return '[ĐŠÍÞ $version íš óúţ: úþđàţé óñçé ýóúŕ çàĺĺ íš óṽéŕ. one two thre]';
  }

  @override
  String updateByHand(String version, String reason) {
    return '[ĐŠÍÞ $version íš óúţ. Ţĥíš çóþý đóéš ñóţ úþđàţé íţšéĺƒ ($reason). one two three f]';
  }

  @override
  String updateDownloading(String version) {
    return '[Ĝéţţíñĝ ĐŠÍÞ $version… one t]';
  }

  @override
  String updateFailed(String reason) {
    return '[Çóúĺđ ñóţ úþđàţé: $reason one t]';
  }

  @override
  String get updateInstall => '[Úþđàţé àñđ ŕéšţàŕţ one ]';

  @override
  String get updateDownload => '[Đóŵñĺóàđ o]';

  @override
  String get updateLater => '[Ĺàţéŕ ]';

  @override
  String get updateNotes => '[Ŵĥàţ\'š ñéŵ o]';

  @override
  String get microphoneRefused =>
      '[ĐŠÍÞ ɱàý ñóţ úšé ţĥé ɱíçŕóþĥóñé, šó ţĥé þéóþĺé ýóú çàĺĺ ŵíĺĺ ñóţ ĥéàŕ ýóú. Àĺĺóŵ íţ íñ ţĥé šýšţéɱ\'š šéţţíñĝš ƒóŕ ĐŠÍÞ. one two three four five six s]';

  @override
  String get routeEarpiece => '[Þĥóñé ]';

  @override
  String get routeSpeaker => '[Šþéàķéŕ o]';

  @override
  String get routeBluetooth => '[Ɓĺúéţóóţĥ on]';

  @override
  String get routeWired => '[Ĥéàđšéţ o]';
}
