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
}
