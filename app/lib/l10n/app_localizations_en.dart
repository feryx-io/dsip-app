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
  String get startFailedTitle => 'DSIP did not start';

  @override
  String get startFailedRetry => 'Try again';

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
  String get firstRunJoin => 'Join another device';

  @override
  String get firstRunJoinIntro =>
      'On a device that has your identity, open Settings, Add a device, and enter this join code there. Check it shows the same check code.';

  @override
  String get firstRunJoinCode => 'Join code';

  @override
  String firstRunCheckCode(String check) {
    return 'Check code: $check';
  }

  @override
  String get firstRunWelcome => 'Welcome code';

  @override
  String get firstRunWelcomeHint =>
      'What the other device shows once it has the join code';

  @override
  String get firstRunWelcomeNeeded =>
      'Enter the welcome code from the other device.';

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
  String get firstRunServer => 'Server';

  @override
  String get firstRunServerHint =>
      'Where your relay and mailbox are found, such as feryx.io. You can change them later in Settings.';

  @override
  String get firstRunServerNeeded => 'Enter a server, such as feryx.io.';

  @override
  String get firstRunByHand => 'Enter the relay and mailbox yourself';

  @override
  String get firstRunByServer => 'Use a server instead';

  @override
  String firstRunServersFailed(String server, String reason) {
    return 'Could not get the servers from $server: $reason';
  }

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
  String get firstRunHints => 'Hints node';

  @override
  String get firstRunHintsNeeded =>
      'Messages need a hints node too: without one, nobody can find your mailbox.';

  @override
  String get firstRunHintsBad =>
      'Enter a hints node address starting with https:// or http://.';

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
    return '$reason';
  }

  @override
  String get callNoSound => 'No sound yet';

  @override
  String callSound(
    int mic,
    int sent,
    int heard,
    int decoded,
    int played,
    int ringback,
  ) {
    return 'Sound: mic $mic · sent $sent · heard $heard · decoded $decoded · played $played · ringback $ringback';
  }

  @override
  String callSoundStalled(String stage) {
    return 'Sound stops at: $stage';
  }

  @override
  String introductionTheirs(String name) {
    return '$name introduced themselves';
  }

  @override
  String get introductionYours => 'You introduced yourself';

  @override
  String get callVideoButton => 'Video call';

  @override
  String get callCameraOn => 'Camera on';

  @override
  String get callCameraOff => 'Camera off';

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
  String get settingsDevices => 'Your devices';

  @override
  String get settingsDevicesIntro =>
      'Add another phone or computer to your identity. It gets its own key, and never your identity\'s key.';

  @override
  String get settingsAddDevice => 'Add a device';

  @override
  String get addDeviceTitle => 'Add a device';

  @override
  String get addDeviceJoin => 'The new device\'s join code';

  @override
  String get addDeviceJoinNeeded => 'Enter the join code the new device shows.';

  @override
  String get addDeviceMake => 'Make the welcome code';

  @override
  String addDeviceWelcome(String check) {
    return 'Enter this welcome code on the new device. It should show the same check code: $check.';
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

  @override
  String get nameAction => 'Name';

  @override
  String nameTitle(String who) {
    return 'Name $who';
  }

  @override
  String get nameField => 'Name';

  @override
  String get nameHint =>
      'Kept on this device only. Leave it empty to remove the name.';

  @override
  String get nameSave => 'Save';

  @override
  String get reasonUserHangup => 'Ended';

  @override
  String get reasonUserDeclined => 'Declined';

  @override
  String get reasonUserNoAnswer => 'No answer';

  @override
  String get reasonUserCancelled => 'Cancelled';

  @override
  String get reasonUserBlocked => 'Blocked';

  @override
  String get reasonEndpointBusy => 'Busy';

  @override
  String get reasonEndpointUnavailable => 'Unavailable';

  @override
  String get reasonEndpointCapability =>
      'Their device can\'t take this kind of call';

  @override
  String get reasonEndpoint => 'Their device couldn\'t take the call';

  @override
  String get reasonIdentityNotInService => 'Not in service';

  @override
  String get reasonIdentityMoved => 'This identity has moved';

  @override
  String get reasonIdentitySuspended => 'This identity is suspended';

  @override
  String get reasonIdentityUnknown => 'No such identity';

  @override
  String get reasonIdentity => 'This identity can\'t be reached';

  @override
  String get reasonSessionTimeout => 'No answer in time';

  @override
  String get reasonSessionElsewhere => 'Answered on another device';

  @override
  String get reasonSessionCancelled => 'Cancelled';

  @override
  String get reasonSession => 'The call failed';

  @override
  String get reasonMediaFailed => 'The sound connection failed';

  @override
  String get reasonMedia => 'Couldn\'t agree on how to send sound';

  @override
  String get reasonPolicyFirstContact => 'They haven\'t accepted you yet';

  @override
  String get reasonPolicyRateLimited => 'Too many calls: try again later';

  @override
  String get reasonPolicy => 'Not allowed';

  @override
  String get reasonTransportUnreached => 'Couldn\'t reach them';

  @override
  String get reasonTransport => 'The connection was lost';

  @override
  String get reasonGateway => 'The phone network couldn\'t connect the call';

  @override
  String callEndedCode(String code) {
    return 'Reason code: $code';
  }

  @override
  String get backupContactsBody =>
      'The names you gave people, and who you follow, are not in the code. Copy the backup with names, keep that text with the code, and restore from it to bring them back.';

  @override
  String get backupCopyFile => 'Copy with names';

  @override
  String get scanButton => 'Scan';

  @override
  String get scanTitle => 'Scan the code';

  @override
  String get scanHint => 'Point the camera at the QR code on the other device.';

  @override
  String get scanQrLabel =>
      'The code as a QR code, for the other device\'s camera';

  @override
  String scanNoCamera(String reason) {
    return 'The camera is not available ($reason). Type or paste the code instead.';
  }

  @override
  String get backupSaveFile => 'Save as a file';

  @override
  String get backupSaved => 'Saved.';

  @override
  String backupSaveFailed(String reason) {
    return 'The file was not saved: $reason';
  }

  @override
  String get firstRunOpenFile => 'Open a backup file';

  @override
  String get firstRunRestoreServers =>
      'A backup file also brings back the servers it was made with. The server below is used only when it has none.';

  @override
  String firstRunOpenFailed(String reason) {
    return 'That file could not be read as a backup: $reason';
  }

  @override
  String get firstRunJoinNearby =>
      'A phone with your identity can scan this QR code instead. On the same network, the welcome code then comes back here by itself.';

  @override
  String firstRunWelcomeReceived(String name, String identity) {
    return 'Received from $name ($identity). Start only if this is your identity.';
  }

  @override
  String addDeviceSent(String check) {
    return 'Sent to the new device. Check that it shows the same check code: $check.';
  }

  @override
  String addDeviceNotSent(String reason) {
    return 'The new device could not be reached ($reason). Enter this welcome code on it instead.';
  }

  @override
  String get navContacts => 'Contacts';

  @override
  String get contactsNone =>
      'No contacts yet. Whoever accepts your introduction, and whoever you accept, is added here.';

  @override
  String get contactAdd => 'Add a contact';

  @override
  String get contactAddTitle => 'New contact';

  @override
  String get contactCall => 'Call';

  @override
  String get contactMessage => 'Message';

  @override
  String get contactRename => 'Rename';

  @override
  String get deleteAction => 'Delete';

  @override
  String contactDeleteConfirm(String name) {
    return 'Delete $name from your contacts? Your calls and conversations with them stay.';
  }

  @override
  String contactMessageTitle(String name) {
    return 'Message $name';
  }

  @override
  String get introduceName => 'What to call them';

  @override
  String get introduceNameHint =>
      'Optional. Saved as your contact once they accept';

  @override
  String get introducedTitle => 'Your introductions';

  @override
  String get introducedWaiting => 'Waiting for them to accept';

  @override
  String get introducedAccepted => 'Accepted: you can message them';

  @override
  String get introducedForget => 'Remove from this list';

  @override
  String get messageDeleteConfirm =>
      'Delete this message from this device? The others in the conversation keep theirs.';

  @override
  String get conversationDelete => 'Delete conversation';

  @override
  String get conversationDeleteConfirm =>
      'Delete this conversation\'s messages from this device? It comes back if a new message arrives.';

  @override
  String get groupDeleteConfirm =>
      'Leave this group and delete its messages from this device?';

  @override
  String get callBack => 'Call back';

  @override
  String get callMissed => 'Missed';

  @override
  String get callsClear => 'Clear history';

  @override
  String get callsClearConfirm =>
      'Delete your whole call history on this device?';

  @override
  String get callForget => 'Delete from history';

  @override
  String get settingsAlerts => 'Alerts';

  @override
  String get alertsEnabled => 'Show alerts';

  @override
  String get alertsEnabledHint =>
      'In the app, and from the system while the app is in the background';

  @override
  String get alertsMessages => 'New messages';

  @override
  String get alertsRequests => 'Requests to message you, and answers to yours';

  @override
  String get alertsCalls =>
      'Missed calls, and calls ringing while the app is in the background';

  @override
  String get alertOpen => 'Open';

  @override
  String alertRequest(String name) {
    return '$name asks to message you';
  }

  @override
  String alertGranted(String name) {
    return '$name accepted you';
  }

  @override
  String get alertGrantedBody => 'You can message them now.';

  @override
  String alertMissed(String name) {
    return 'Missed call from $name';
  }

  @override
  String alertIncoming(String name) {
    return '$name is calling';
  }

  @override
  String get attachAction => 'Attach a file';

  @override
  String attachSending(String name) {
    return 'Sending $name…';
  }

  @override
  String get attachmentFetching => 'Downloading…';

  @override
  String get attachmentOpen => 'Open';

  @override
  String get attachmentSave => 'Save';

  @override
  String get attachmentSaved => 'Saved.';

  @override
  String get attachmentNotOpened =>
      'Could not open it here. Save it, then open it from where you saved it.';

  @override
  String get voiceMessage => 'Voice message';

  @override
  String get voicemail => 'Voicemail';

  @override
  String get voiceRecord => 'Record a voice message';

  @override
  String get voicePlay => 'Play';

  @override
  String get voiceStop => 'Stop';

  @override
  String voiceRecordingTime(String time) {
    return 'Recording $time';
  }

  @override
  String voiceRecorded(String time) {
    return 'Recorded $time';
  }

  @override
  String get voiceDrop => 'Delete the recording';

  @override
  String voicemailOfferTitle(String name) {
    return '$name didn\'t answer';
  }

  @override
  String voicemailOfferBody(String time) {
    return 'Leave a voicemail? Up to $time.';
  }

  @override
  String get voicemailRecord => 'Record';

  @override
  String get voicemailSent => 'Voicemail sent.';
}

/// The translations for English (`en_XA`).
class StringsEnXa extends StringsEn {
  StringsEnXa() : super('en_XA');

  @override
  String get appName => '[ĐŠÍÞ ]';

  @override
  String get firstRunTitle => '[Ŵéĺçóɱé ţó ĐŠÍÞ one]';

  @override
  String get startFailedTitle => '[ĐŠÍÞ đíđ ñóţ šţàŕţ one ]';

  @override
  String get startFailedRetry => '[Ţŕý àĝàíñ o]';

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
  String get firstRunJoin => '[Ĵóíñ àñóţĥéŕ đéṽíçé one ]';

  @override
  String get firstRunJoinIntro =>
      '[Óñ à đéṽíçé ţĥàţ ĥàš ýóúŕ íđéñţíţý, óþéñ Šéţţíñĝš, Àđđ à đéṽíçé, àñđ éñţéŕ ţĥíš ĵóíñ çóđé ţĥéŕé. Çĥéçķ íţ šĥóŵš ţĥé šàɱé çĥéçķ çóđé. one two three four five six seven]';

  @override
  String get firstRunJoinCode => '[Ĵóíñ çóđé o]';

  @override
  String firstRunCheckCode(String check) {
    return '[Çĥéçķ çóđé: $check one]';
  }

  @override
  String get firstRunWelcome => '[Ŵéĺçóɱé çóđé on]';

  @override
  String get firstRunWelcomeHint =>
      '[Ŵĥàţ ţĥé óţĥéŕ đéṽíçé šĥóŵš óñçé íţ ĥàš ţĥé ĵóíñ çóđé one two three]';

  @override
  String get firstRunWelcomeNeeded =>
      '[Éñţéŕ ţĥé ŵéĺçóɱé çóđé ƒŕóɱ ţĥé óţĥéŕ đéṽíçé. one two thr]';

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
  String get firstRunServer => '[Šéŕṽéŕ o]';

  @override
  String get firstRunServerHint =>
      '[Ŵĥéŕé ýóúŕ ŕéĺàý àñđ ɱàíĺƀóẋ àŕé ƒóúñđ, šúçĥ àš ƒéŕýẋ.íó. Ýóú çàñ çĥàñĝé ţĥéɱ ĺàţéŕ íñ Šéţţíñĝš. one two three four five ]';

  @override
  String get firstRunServerNeeded =>
      '[Éñţéŕ à šéŕṽéŕ, šúçĥ àš ƒéŕýẋ.íó. one two]';

  @override
  String get firstRunByHand =>
      '[Éñţéŕ ţĥé ŕéĺàý àñđ ɱàíĺƀóẋ ýóúŕšéĺƒ one two t]';

  @override
  String get firstRunByServer => '[Úšé à šéŕṽéŕ íñšţéàđ one ]';

  @override
  String firstRunServersFailed(String server, String reason) {
    return '[Çóúĺđ ñóţ ĝéţ ţĥé šéŕṽéŕš ƒŕóɱ $server: $reason one two thr]';
  }

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
  String get firstRunHints => '[Ĥíñţš ñóđé on]';

  @override
  String get firstRunHintsNeeded =>
      '[Ḿéššàĝéš ñééđ à ĥíñţš ñóđé ţóó: ŵíţĥóúţ óñé, ñóƀóđý çàñ ƒíñđ ýóúŕ ɱàíĺƀóẋ. one two three four]';

  @override
  String get firstRunHintsBad =>
      '[Éñţéŕ à ĥíñţš ñóđé àđđŕéšš šţàŕţíñĝ ŵíţĥ ĥţţþš:// óŕ ĥţţþ://. one two three ]';

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
    return '[$reason o]';
  }

  @override
  String get callNoSound => '[Ñó šóúñđ ýéţ on]';

  @override
  String callSound(
    int mic,
    int sent,
    int heard,
    int decoded,
    int played,
    int ringback,
  ) {
    return '[Šóúñđ: ɱíç $mic · šéñţ $sent · ĥéàŕđ $heard · đéçóđéđ $decoded · þĺàýéđ $played · ŕíñĝƀàçķ $ringback one two three four fiv]';
  }

  @override
  String callSoundStalled(String stage) {
    return '[Šóúñđ šţóþš àţ: $stage one ]';
  }

  @override
  String introductionTheirs(String name) {
    return '[$name íñţŕóđúçéđ ţĥéɱšéĺṽéš one two]';
  }

  @override
  String get introductionYours => '[Ýóú íñţŕóđúçéđ ýóúŕšéĺƒ one tw]';

  @override
  String get callVideoButton => '[Ṽíđéó çàĺĺ on]';

  @override
  String get callCameraOn => '[Çàɱéŕà óñ o]';

  @override
  String get callCameraOff => '[Çàɱéŕà óƒƒ on]';

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
  String get settingsDevices => '[Ýóúŕ đéṽíçéš on]';

  @override
  String get settingsDevicesIntro =>
      '[Àđđ àñóţĥéŕ þĥóñé óŕ çóɱþúţéŕ ţó ýóúŕ íđéñţíţý. Íţ ĝéţš íţš óŵñ ķéý, àñđ ñéṽéŕ ýóúŕ íđéñţíţý\'š ķéý. one two three four five s]';

  @override
  String get settingsAddDevice => '[Àđđ à đéṽíçé on]';

  @override
  String get addDeviceTitle => '[Àđđ à đéṽíçé on]';

  @override
  String get addDeviceJoin => '[Ţĥé ñéŵ đéṽíçé\'š ĵóíñ çóđé one tw]';

  @override
  String get addDeviceJoinNeeded =>
      '[Éñţéŕ ţĥé ĵóíñ çóđé ţĥé ñéŵ đéṽíçé šĥóŵš. one two th]';

  @override
  String get addDeviceMake => '[Ḿàķé ţĥé ŵéĺçóɱé çóđé one t]';

  @override
  String addDeviceWelcome(String check) {
    return '[Éñţéŕ ţĥíš ŵéĺçóɱé çóđé óñ ţĥé ñéŵ đéṽíçé. Íţ šĥóúĺđ šĥóŵ ţĥé šàɱé çĥéçķ çóđé: $check. one two three four fi]';
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

  @override
  String get nameAction => '[Ñàɱé ]';

  @override
  String nameTitle(String who) {
    return '[Ñàɱé $who o]';
  }

  @override
  String get nameField => '[Ñàɱé ]';

  @override
  String get nameHint =>
      '[Ķéþţ óñ ţĥíš đéṽíçé óñĺý. Ĺéàṽé íţ éɱþţý ţó ŕéɱóṽé ţĥé ñàɱé. one two three ]';

  @override
  String get nameSave => '[Šàṽé ]';

  @override
  String get reasonUserHangup => '[Éñđéđ ]';

  @override
  String get reasonUserDeclined => '[Đéçĺíñéđ o]';

  @override
  String get reasonUserNoAnswer => '[Ñó àñšŵéŕ o]';

  @override
  String get reasonUserCancelled => '[Çàñçéĺĺéđ on]';

  @override
  String get reasonUserBlocked => '[Ɓĺóçķéđ o]';

  @override
  String get reasonEndpointBusy => '[Ɓúšý ]';

  @override
  String get reasonEndpointUnavailable => '[Úñàṽàíĺàƀĺé on]';

  @override
  String get reasonEndpointCapability =>
      '[Ţĥéíŕ đéṽíçé çàñ\'ţ ţàķé ţĥíš ķíñđ óƒ çàĺĺ one two th]';

  @override
  String get reasonEndpoint =>
      '[Ţĥéíŕ đéṽíçé çóúĺđñ\'ţ ţàķé ţĥé çàĺĺ one two ]';

  @override
  String get reasonIdentityNotInService => '[Ñóţ íñ šéŕṽíçé one]';

  @override
  String get reasonIdentityMoved => '[Ţĥíš íđéñţíţý ĥàš ɱóṽéđ one t]';

  @override
  String get reasonIdentitySuspended => '[Ţĥíš íđéñţíţý íš šúšþéñđéđ one tw]';

  @override
  String get reasonIdentityUnknown => '[Ñó šúçĥ íđéñţíţý one]';

  @override
  String get reasonIdentity => '[Ţĥíš íđéñţíţý çàñ\'ţ ƀé ŕéàçĥéđ one two]';

  @override
  String get reasonSessionTimeout => '[Ñó àñšŵéŕ íñ ţíɱé one]';

  @override
  String get reasonSessionElsewhere => '[Àñšŵéŕéđ óñ àñóţĥéŕ đéṽíçé one tw]';

  @override
  String get reasonSessionCancelled => '[Çàñçéĺĺéđ on]';

  @override
  String get reasonSession => '[Ţĥé çàĺĺ ƒàíĺéđ one]';

  @override
  String get reasonMediaFailed => '[Ţĥé šóúñđ çóññéçţíóñ ƒàíĺéđ one two]';

  @override
  String get reasonMedia => '[Çóúĺđñ\'ţ àĝŕéé óñ ĥóŵ ţó šéñđ šóúñđ one two ]';

  @override
  String get reasonPolicyFirstContact =>
      '[Ţĥéý ĥàṽéñ\'ţ àççéþţéđ ýóú ýéţ one two]';

  @override
  String get reasonPolicyRateLimited =>
      '[Ţóó ɱàñý çàĺĺš: ţŕý àĝàíñ ĺàţéŕ one two]';

  @override
  String get reasonPolicy => '[Ñóţ àĺĺóŵéđ on]';

  @override
  String get reasonTransportUnreached => '[Çóúĺđñ\'ţ ŕéàçĥ ţĥéɱ one ]';

  @override
  String get reasonTransport => '[Ţĥé çóññéçţíóñ ŵàš ĺóšţ one t]';

  @override
  String get reasonGateway =>
      '[Ţĥé þĥóñé ñéţŵóŕķ çóúĺđñ\'ţ çóññéçţ ţĥé çàĺĺ one two thr]';

  @override
  String callEndedCode(String code) {
    return '[Ŕéàšóñ çóđé: $code one]';
  }

  @override
  String get backupContactsBody =>
      '[Ţĥé ñàɱéš ýóú ĝàṽé þéóþĺé, àñđ ŵĥó ýóú ƒóĺĺóŵ, àŕé ñóţ íñ ţĥé çóđé. Çóþý ţĥé ƀàçķúþ ŵíţĥ ñàɱéš, ķééþ ţĥàţ ţéẋţ ŵíţĥ ţĥé çóđé, àñđ ŕéšţóŕé ƒŕóɱ íţ ţó ƀŕíñĝ ţĥéɱ ƀàçķ. one two three four five six seven eight n]';

  @override
  String get backupCopyFile => '[Çóþý ŵíţĥ ñàɱéš one]';

  @override
  String get scanButton => '[Šçàñ ]';

  @override
  String get scanTitle => '[Šçàñ ţĥé çóđé on]';

  @override
  String get scanHint =>
      '[Þóíñţ ţĥé çàɱéŕà àţ ţĥé ǪŔ çóđé óñ ţĥé óţĥéŕ đéṽíçé. one two thre]';

  @override
  String get scanQrLabel =>
      '[Ţĥé çóđé àš à ǪŔ çóđé, ƒóŕ ţĥé óţĥéŕ đéṽíçé\'š çàɱéŕà one two thre]';

  @override
  String scanNoCamera(String reason) {
    return '[Ţĥé çàɱéŕà íš ñóţ àṽàíĺàƀĺé ($reason). Ţýþé óŕ þàšţé ţĥé çóđé íñšţéàđ. one two three fou]';
  }

  @override
  String get backupSaveFile => '[Šàṽé àš à ƒíĺé on]';

  @override
  String get backupSaved => '[Šàṽéđ. ]';

  @override
  String backupSaveFailed(String reason) {
    return '[Ţĥé ƒíĺé ŵàš ñóţ šàṽéđ: $reason one two]';
  }

  @override
  String get firstRunOpenFile => '[Óþéñ à ƀàçķúþ ƒíĺé one ]';

  @override
  String get firstRunRestoreServers =>
      '[À ƀàçķúþ ƒíĺé àĺšó ƀŕíñĝš ƀàçķ ţĥé šéŕṽéŕš íţ ŵàš ɱàđé ŵíţĥ. Ţĥé šéŕṽéŕ ƀéĺóŵ íš úšéđ óñĺý ŵĥéñ íţ ĥàš ñóñé. one two three four five six]';

  @override
  String firstRunOpenFailed(String reason) {
    return '[Ţĥàţ ƒíĺé çóúĺđ ñóţ ƀé ŕéàđ àš à ƀàçķúþ: $reason one two thr]';
  }

  @override
  String get firstRunJoinNearby =>
      '[À þĥóñé ŵíţĥ ýóúŕ íđéñţíţý çàñ šçàñ ţĥíš ǪŔ çóđé íñšţéàđ. Óñ ţĥé šàɱé ñéţŵóŕķ, ţĥé ŵéĺçóɱé çóđé ţĥéñ çóɱéš ƀàçķ ĥéŕé ƀý íţšéĺƒ. one two three four five six seve]';

  @override
  String firstRunWelcomeReceived(String name, String identity) {
    return '[Ŕéçéíṽéđ ƒŕóɱ $name ($identity). Šţàŕţ óñĺý íƒ ţĥíš íš ýóúŕ íđéñţíţý. one two three fo]';
  }

  @override
  String addDeviceSent(String check) {
    return '[Šéñţ ţó ţĥé ñéŵ đéṽíçé. Çĥéçķ ţĥàţ íţ šĥóŵš ţĥé šàɱé çĥéçķ çóđé: $check. one two three fou]';
  }

  @override
  String addDeviceNotSent(String reason) {
    return '[Ţĥé ñéŵ đéṽíçé çóúĺđ ñóţ ƀé ŕéàçĥéđ ($reason). Éñţéŕ ţĥíš ŵéĺçóɱé çóđé óñ íţ íñšţéàđ. one two three four fi]';
  }

  @override
  String get navContacts => '[Çóñţàçţš o]';

  @override
  String get contactsNone =>
      '[Ñó çóñţàçţš ýéţ. Ŵĥóéṽéŕ àççéþţš ýóúŕ íñţŕóđúçţíóñ, àñđ ŵĥóéṽéŕ ýóú àççéþţ, íš àđđéđ ĥéŕé. one two three four five]';

  @override
  String get contactAdd => '[Àđđ à çóñţàçţ on]';

  @override
  String get contactAddTitle => '[Ñéŵ çóñţàçţ on]';

  @override
  String get contactCall => '[Çàĺĺ ]';

  @override
  String get contactMessage => '[Ḿéššàĝé o]';

  @override
  String get contactRename => '[Ŕéñàɱé o]';

  @override
  String get deleteAction => '[Đéĺéţé o]';

  @override
  String contactDeleteConfirm(String name) {
    return '[Đéĺéţé $name ƒŕóɱ ýóúŕ çóñţàçţš? Ýóúŕ çàĺĺš àñđ çóñṽéŕšàţíóñš ŵíţĥ ţĥéɱ šţàý. one two three four f]';
  }

  @override
  String contactMessageTitle(String name) {
    return '[Ḿéššàĝé $name on]';
  }

  @override
  String get introduceName => '[Ŵĥàţ ţó çàĺĺ ţĥéɱ one]';

  @override
  String get introduceNameHint =>
      '[Óþţíóñàĺ. Šàṽéđ àš ýóúŕ çóñţàçţ óñçé ţĥéý àççéþţ one two thre]';

  @override
  String get introducedTitle => '[Ýóúŕ íñţŕóđúçţíóñš one ]';

  @override
  String get introducedWaiting => '[Ŵàíţíñĝ ƒóŕ ţĥéɱ ţó àççéþţ one tw]';

  @override
  String get introducedAccepted => '[Àççéþţéđ: ýóú çàñ ɱéššàĝé ţĥéɱ one two]';

  @override
  String get introducedForget => '[Ŕéɱóṽé ƒŕóɱ ţĥíš ĺíšţ one t]';

  @override
  String get messageDeleteConfirm =>
      '[Đéĺéţé ţĥíš ɱéššàĝé ƒŕóɱ ţĥíš đéṽíçé? Ţĥé óţĥéŕš íñ ţĥé çóñṽéŕšàţíóñ ķééþ ţĥéíŕš. one two three four fi]';

  @override
  String get conversationDelete => '[Đéĺéţé çóñṽéŕšàţíóñ one t]';

  @override
  String get conversationDeleteConfirm =>
      '[Đéĺéţé ţĥíš çóñṽéŕšàţíóñ\'š ɱéššàĝéš ƒŕóɱ ţĥíš đéṽíçé? Íţ çóɱéš ƀàçķ íƒ à ñéŵ ɱéššàĝé àŕŕíṽéš. one two three four five ]';

  @override
  String get groupDeleteConfirm =>
      '[Ĺéàṽé ţĥíš ĝŕóúþ àñđ đéĺéţé íţš ɱéššàĝéš ƒŕóɱ ţĥíš đéṽíçé? one two three f]';

  @override
  String get callBack => '[Çàĺĺ ƀàçķ o]';

  @override
  String get callMissed => '[Ḿíššéđ o]';

  @override
  String get callsClear => '[Çĺéàŕ ĥíšţóŕý one]';

  @override
  String get callsClearConfirm =>
      '[Đéĺéţé ýóúŕ ŵĥóĺé çàĺĺ ĥíšţóŕý óñ ţĥíš đéṽíçé? one two thr]';

  @override
  String get callForget => '[Đéĺéţé ƒŕóɱ ĥíšţóŕý one ]';

  @override
  String get settingsAlerts => '[Àĺéŕţš o]';

  @override
  String get alertsEnabled => '[Šĥóŵ àĺéŕţš on]';

  @override
  String get alertsEnabledHint =>
      '[Íñ ţĥé àþþ, àñđ ƒŕóɱ ţĥé šýšţéɱ ŵĥíĺé ţĥé àþþ íš íñ ţĥé ƀàçķĝŕóúñđ one two three fo]';

  @override
  String get alertsMessages => '[Ñéŵ ɱéššàĝéš on]';

  @override
  String get alertsRequests =>
      '[Ŕéǫúéšţš ţó ɱéššàĝé ýóú, àñđ àñšŵéŕš ţó ýóúŕš one two thr]';

  @override
  String get alertsCalls =>
      '[Ḿíššéđ çàĺĺš, àñđ çàĺĺš ŕíñĝíñĝ ŵĥíĺé ţĥé àþþ íš íñ ţĥé ƀàçķĝŕóúñđ one two three fou]';

  @override
  String get alertOpen => '[Óþéñ ]';

  @override
  String alertRequest(String name) {
    return '[$name àšķš ţó ɱéššàĝé ýóú one t]';
  }

  @override
  String alertGranted(String name) {
    return '[$name àççéþţéđ ýóú one ]';
  }

  @override
  String get alertGrantedBody => '[Ýóú çàñ ɱéššàĝé ţĥéɱ ñóŵ. one t]';

  @override
  String alertMissed(String name) {
    return '[Ḿíššéđ çàĺĺ ƒŕóɱ $name one t]';
  }

  @override
  String alertIncoming(String name) {
    return '[$name íš çàĺĺíñĝ one]';
  }

  @override
  String get attachAction => '[Àţţàçĥ à ƒíĺé on]';

  @override
  String attachSending(String name) {
    return '[Šéñđíñĝ $name… on]';
  }

  @override
  String get attachmentFetching => '[Đóŵñĺóàđíñĝ… on]';

  @override
  String get attachmentOpen => '[Óþéñ ]';

  @override
  String get attachmentSave => '[Šàṽé ]';

  @override
  String get attachmentSaved => '[Šàṽéđ. ]';

  @override
  String get attachmentNotOpened =>
      '[Çóúĺđ ñóţ óþéñ íţ ĥéŕé. Šàṽé íţ, ţĥéñ óþéñ íţ ƒŕóɱ ŵĥéŕé ýóú šàṽéđ íţ. one two three fo]';

  @override
  String get voiceMessage => '[Ṽóíçé ɱéššàĝé one]';

  @override
  String get voicemail => '[Ṽóíçéɱàíĺ on]';

  @override
  String get voiceRecord => '[Ŕéçóŕđ à ṽóíçé ɱéššàĝé one t]';

  @override
  String get voicePlay => '[Þĺàý ]';

  @override
  String get voiceStop => '[Šţóþ ]';

  @override
  String voiceRecordingTime(String time) {
    return '[Ŕéçóŕđíñĝ $time one]';
  }

  @override
  String voiceRecorded(String time) {
    return '[Ŕéçóŕđéđ $time one]';
  }

  @override
  String get voiceDrop => '[Đéĺéţé ţĥé ŕéçóŕđíñĝ one t]';

  @override
  String voicemailOfferTitle(String name) {
    return '[$name đíđñ\'ţ àñšŵéŕ one ]';
  }

  @override
  String voicemailOfferBody(String time) {
    return '[Ĺéàṽé à ṽóíçéɱàíĺ? Úþ ţó $time. one tw]';
  }

  @override
  String get voicemailRecord => '[Ŕéçóŕđ o]';

  @override
  String get voicemailSent => '[Ṽóíçéɱàíĺ šéñţ. one]';
}
