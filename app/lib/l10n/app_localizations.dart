import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of Strings
/// returned by `Strings.of(context)`.
///
/// Applications need to include `Strings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: Strings.localizationsDelegates,
///   supportedLocales: Strings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the Strings.supportedLocales
/// property.
abstract class Strings {
  Strings(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static Strings of(BuildContext context) {
    return Localizations.of<Strings>(context, Strings)!;
  }

  static const LocalizationsDelegate<Strings> delegate = _StringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('en', 'XA'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'DSIP'**
  String get appName;

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to DSIP'**
  String get firstRunTitle;

  /// No description provided for @startFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'DSIP did not start'**
  String get startFailedTitle;

  /// No description provided for @startFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get startFailedRetry;

  /// No description provided for @firstRunIntro.
  ///
  /// In en, this message translates to:
  /// **'Your identity is yours: a key on this device, not an account on a server. Make one, or use one you already have.'**
  String get firstRunIntro;

  /// No description provided for @firstRunNew.
  ///
  /// In en, this message translates to:
  /// **'Make an identity'**
  String get firstRunNew;

  /// No description provided for @firstRunExisting.
  ///
  /// In en, this message translates to:
  /// **'Use an identity folder'**
  String get firstRunExisting;

  /// No description provided for @firstRunName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get firstRunName;

  /// No description provided for @firstRunNameHint.
  ///
  /// In en, this message translates to:
  /// **'What others see when you call or write (they are told it is your claim)'**
  String get firstRunNameHint;

  /// No description provided for @firstRunNameNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter your name.'**
  String get firstRunNameNeeded;

  /// No description provided for @firstRunFolder.
  ///
  /// In en, this message translates to:
  /// **'Identity folder'**
  String get firstRunFolder;

  /// No description provided for @firstRunFolderHint.
  ///
  /// In en, this message translates to:
  /// **'A folder made by dsip-app init or dsip identity init'**
  String get firstRunFolderHint;

  /// No description provided for @firstRunFolderNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter the identity folder.'**
  String get firstRunFolderNeeded;

  /// No description provided for @firstRunRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get firstRunRestore;

  /// No description provided for @firstRunJoin.
  ///
  /// In en, this message translates to:
  /// **'Join another device'**
  String get firstRunJoin;

  /// No description provided for @firstRunJoinIntro.
  ///
  /// In en, this message translates to:
  /// **'On a device that has your identity, open Settings, Add a device, and enter this join code there. Check it shows the same check code.'**
  String get firstRunJoinIntro;

  /// No description provided for @firstRunJoinCode.
  ///
  /// In en, this message translates to:
  /// **'Join code'**
  String get firstRunJoinCode;

  /// No description provided for @firstRunCheckCode.
  ///
  /// In en, this message translates to:
  /// **'Check code: {check}'**
  String firstRunCheckCode(String check);

  /// No description provided for @firstRunWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome code'**
  String get firstRunWelcome;

  /// No description provided for @firstRunWelcomeHint.
  ///
  /// In en, this message translates to:
  /// **'What the other device shows once it has the join code'**
  String get firstRunWelcomeHint;

  /// No description provided for @firstRunWelcomeNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter the welcome code from the other device.'**
  String get firstRunWelcomeNeeded;

  /// No description provided for @firstRunCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get firstRunCode;

  /// No description provided for @firstRunCodeHint.
  ///
  /// In en, this message translates to:
  /// **'DSIP1-… as you wrote it down or saved it, or the backup file\'s text'**
  String get firstRunCodeHint;

  /// No description provided for @firstRunCodeNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code.'**
  String get firstRunCodeNeeded;

  /// No description provided for @backupPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get backupPassphrase;

  /// No description provided for @backupPassphraseNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter the passphrase.'**
  String get backupPassphraseNeeded;

  /// No description provided for @firstRunServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get firstRunServer;

  /// No description provided for @firstRunServerHint.
  ///
  /// In en, this message translates to:
  /// **'Where your relay and mailbox are found, such as feryx.io. You can change them later in Settings.'**
  String get firstRunServerHint;

  /// No description provided for @firstRunServerNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter a server, such as feryx.io.'**
  String get firstRunServerNeeded;

  /// No description provided for @firstRunByHand.
  ///
  /// In en, this message translates to:
  /// **'Enter the relay and mailbox yourself'**
  String get firstRunByHand;

  /// No description provided for @firstRunByServer.
  ///
  /// In en, this message translates to:
  /// **'Use a server instead'**
  String get firstRunByServer;

  /// No description provided for @firstRunServersFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not get the servers from {server}: {reason}'**
  String firstRunServersFailed(String server, String reason);

  /// No description provided for @firstRunRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get firstRunRelay;

  /// No description provided for @firstRunRelayHint.
  ///
  /// In en, this message translates to:
  /// **'wss://relay.example.com:8443/dsip'**
  String get firstRunRelayHint;

  /// No description provided for @firstRunRelayNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter a relay address starting with wss://.'**
  String get firstRunRelayNeeded;

  /// No description provided for @firstRunMailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox (for messages, optional)'**
  String get firstRunMailbox;

  /// No description provided for @firstRunMailboxHint.
  ///
  /// In en, this message translates to:
  /// **'wss://mailbox.example.com:9443/dsip'**
  String get firstRunMailboxHint;

  /// No description provided for @firstRunMailboxDid.
  ///
  /// In en, this message translates to:
  /// **'Mailbox DID'**
  String get firstRunMailboxDid;

  /// No description provided for @firstRunMailboxDidNeeded.
  ///
  /// In en, this message translates to:
  /// **'A mailbox needs its DID too.'**
  String get firstRunMailboxDidNeeded;

  /// No description provided for @firstRunHints.
  ///
  /// In en, this message translates to:
  /// **'Hints node'**
  String get firstRunHints;

  /// No description provided for @firstRunHintsNeeded.
  ///
  /// In en, this message translates to:
  /// **'Messages need a hints node too: without one, nobody can find your mailbox.'**
  String get firstRunHintsNeeded;

  /// No description provided for @firstRunHintsBad.
  ///
  /// In en, this message translates to:
  /// **'Enter a hints node address starting with https:// or http://.'**
  String get firstRunHintsBad;

  /// No description provided for @firstRunHintsHint.
  ///
  /// In en, this message translates to:
  /// **'https://hints.example.com'**
  String get firstRunHintsHint;

  /// No description provided for @firstRunStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get firstRunStart;

  /// No description provided for @firstRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start: {reason}'**
  String firstRunFailed(String reason);

  /// No description provided for @navCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get navCalls;

  /// No description provided for @navMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get navMe;

  /// No description provided for @callTo.
  ///
  /// In en, this message translates to:
  /// **'Identity to call'**
  String get callTo;

  /// No description provided for @callToHint.
  ///
  /// In en, this message translates to:
  /// **'did:key:… or did:web:…'**
  String get callToHint;

  /// No description provided for @callButton.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callButton;

  /// No description provided for @callAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get callAnswer;

  /// No description provided for @callDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get callDecline;

  /// No description provided for @callHangUp.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get callHangUp;

  /// No description provided for @callMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMute;

  /// No description provided for @callUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get callUnmute;

  /// No description provided for @callCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling…'**
  String get callCalling;

  /// No description provided for @callRingingThere.
  ///
  /// In en, this message translates to:
  /// **'Ringing…'**
  String get callRingingThere;

  /// No description provided for @callRingingHere.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get callRingingHere;

  /// No description provided for @callAnswered.
  ///
  /// In en, this message translates to:
  /// **'In call'**
  String get callAnswered;

  /// No description provided for @callAnsweredBy.
  ///
  /// In en, this message translates to:
  /// **'Answered by {by}'**
  String callAnsweredBy(String by);

  /// A recent call's line under its name: why it ended, in words (one of the reason… messages).
  ///
  /// In en, this message translates to:
  /// **'{reason}'**
  String callEnded(String reason);

  /// No description provided for @callNoSound.
  ///
  /// In en, this message translates to:
  /// **'No sound yet'**
  String get callNoSound;

  /// A call's sound counted on this device, stage by stage, to find where it stops: 20 ms frames from the microphone, frames sent, packets heard from the other side, packets decoded, frames played, ringback frames played.
  ///
  /// In en, this message translates to:
  /// **'Sound: mic {mic} · sent {sent} · heard {heard} · decoded {decoded} · played {played} · ringback {ringback}'**
  String callSound(
    int mic,
    int sent,
    int heard,
    int decoded,
    int played,
    int ringback,
  );

  /// Shown when a stage of a call's sound stopped counting: stage is the counter's name as in callSound, untranslated (mic, sent, heard, decoded, played or ringback).
  ///
  /// In en, this message translates to:
  /// **'Sound stops at: {stage}'**
  String callSoundStalled(String stage);

  /// Heading of the introduction a new contact sent, shown on top of the conversation with them once accepted; its text follows.
  ///
  /// In en, this message translates to:
  /// **'{name} introduced themselves'**
  String introductionTheirs(String name);

  /// Heading of the introduction this user sent, shown on top of the conversation with someone who accepted it; its text follows.
  ///
  /// In en, this message translates to:
  /// **'You introduced yourself'**
  String get introductionYours;

  /// Button beside Call that places a video call to the identity typed in.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get callVideoButton;

  /// Button in a video call that turns this side's camera on.
  ///
  /// In en, this message translates to:
  /// **'Camera on'**
  String get callCameraOn;

  /// Button in a video call that turns this side's camera off.
  ///
  /// In en, this message translates to:
  /// **'Camera off'**
  String get callCameraOff;

  /// No description provided for @callVia.
  ///
  /// In en, this message translates to:
  /// **'Through {relay}'**
  String callVia(String relay);

  /// No description provided for @callsNone.
  ///
  /// In en, this message translates to:
  /// **'No calls. Enter an identity above to call it.'**
  String get callsNone;

  /// No description provided for @callsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get callsRecent;

  /// No description provided for @meIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get meIdentity;

  /// No description provided for @meDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get meDevice;

  /// No description provided for @meRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get meRelay;

  /// No description provided for @meMailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox'**
  String get meMailbox;

  /// No description provided for @meMailboxConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get meMailboxConnected;

  /// No description provided for @meMailboxOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get meMailboxOffline;

  /// No description provided for @meMailboxNone.
  ///
  /// In en, this message translates to:
  /// **'None: calls only'**
  String get meMailboxNone;

  /// No description provided for @meCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get meCopy;

  /// No description provided for @meCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get meCopied;

  /// No description provided for @commandFailed.
  ///
  /// In en, this message translates to:
  /// **'{reason}'**
  String commandFailed(String reason);

  /// No description provided for @appStopped.
  ///
  /// In en, this message translates to:
  /// **'The app stopped.'**
  String get appStopped;

  /// No description provided for @navMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get navMessages;

  /// No description provided for @messagingOff.
  ///
  /// In en, this message translates to:
  /// **'Messaging is off: this app has no mailbox. Add one in its settings to message.'**
  String get messagingOff;

  /// No description provided for @messagingOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected to your mailbox: messages go out once it is back.'**
  String get messagingOffline;

  /// No description provided for @requestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Asking to message you'**
  String get requestsTitle;

  /// No description provided for @requestFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} (says they are)'**
  String requestFrom(String name);

  /// No description provided for @requestAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get requestAccept;

  /// No description provided for @requestDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get requestDecline;

  /// No description provided for @conversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsTitle;

  /// No description provided for @conversationsNone.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. Introduce yourself to someone, and message them once they accept.'**
  String get conversationsNone;

  /// No description provided for @conversationGroup.
  ///
  /// In en, this message translates to:
  /// **'Group of {count}'**
  String conversationGroup(int count);

  /// No description provided for @conversationPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message not yet at the hub} other{{count} messages not yet at the hub}}'**
  String conversationPending(int count);

  /// No description provided for @actionIntroduce.
  ///
  /// In en, this message translates to:
  /// **'Introduce yourself'**
  String get actionIntroduce;

  /// No description provided for @actionNewMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get actionNewMessage;

  /// No description provided for @actionNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get actionNewGroup;

  /// No description provided for @introduceTitle.
  ///
  /// In en, this message translates to:
  /// **'Introduce yourself'**
  String get introduceTitle;

  /// No description provided for @introduceTo.
  ///
  /// In en, this message translates to:
  /// **'Their identity'**
  String get introduceTo;

  /// No description provided for @introducePurpose.
  ///
  /// In en, this message translates to:
  /// **'Why you are writing'**
  String get introducePurpose;

  /// No description provided for @introducePurposeHint.
  ///
  /// In en, this message translates to:
  /// **'Only they can read it'**
  String get introducePurposeHint;

  /// No description provided for @introduceSent.
  ///
  /// In en, this message translates to:
  /// **'Asked. You can message them once they accept.'**
  String get introduceSent;

  /// No description provided for @newMessageTo.
  ///
  /// In en, this message translates to:
  /// **'To (an identity that accepted you)'**
  String get newMessageTo;

  /// No description provided for @newGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Members, one identity per line'**
  String get newGroupMembers;

  /// No description provided for @newGroupHint.
  ///
  /// In en, this message translates to:
  /// **'Each must have accepted you'**
  String get newGroupHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageHint;

  /// No description provided for @threadEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get threadEmpty;

  /// No description provided for @threadNotText.
  ///
  /// In en, this message translates to:
  /// **'({kind} message)'**
  String threadNotText(String kind);

  /// No description provided for @threadMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get threadMembers;

  /// No description provided for @threadAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add someone'**
  String get threadAddMember;

  /// No description provided for @threadRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get threadRemove;

  /// No description provided for @threadLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get threadLeave;

  /// No description provided for @threadLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave this conversation? The others keep it; you no longer see it.'**
  String get threadLeaveConfirm;

  /// No description provided for @noticeGranted.
  ///
  /// In en, this message translates to:
  /// **'{who} accepted: you can message them, call them and see their presence.'**
  String noticeGranted(String who);

  /// No description provided for @noticeRemoved.
  ///
  /// In en, this message translates to:
  /// **'{who} removed you from a conversation.'**
  String noticeRemoved(String who);

  /// No description provided for @navPresence.
  ///
  /// In en, this message translates to:
  /// **'Presence'**
  String get navPresence;

  /// No description provided for @presenceMine.
  ///
  /// In en, this message translates to:
  /// **'Your presence'**
  String get presenceMine;

  /// No description provided for @presenceAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get presenceAutomatic;

  /// No description provided for @presenceAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get presenceAvailable;

  /// No description provided for @presenceBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get presenceBusy;

  /// No description provided for @presenceAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get presenceAway;

  /// No description provided for @presenceDnd.
  ///
  /// In en, this message translates to:
  /// **'Do not disturb'**
  String get presenceDnd;

  /// No description provided for @presenceOffline.
  ///
  /// In en, this message translates to:
  /// **'Invisible'**
  String get presenceOffline;

  /// No description provided for @presenceAutomaticExplained.
  ///
  /// In en, this message translates to:
  /// **'Those who follow you see you available while this app is connected, and offline when it is not.'**
  String get presenceAutomaticExplained;

  /// No description provided for @presenceSetExplained.
  ///
  /// In en, this message translates to:
  /// **'Those who follow you see this, sealed so that only they can read it: not your relay.'**
  String get presenceSetExplained;

  /// No description provided for @presenceOfflineExplained.
  ///
  /// In en, this message translates to:
  /// **'Those who follow you see you offline. Calls still reach you.'**
  String get presenceOfflineExplained;

  /// No description provided for @presenceFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get presenceFollowing;

  /// No description provided for @presenceFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow someone'**
  String get presenceFollow;

  /// No description provided for @presenceFollowHint.
  ///
  /// In en, this message translates to:
  /// **'They see that you follow them; their presence shows once they have accepted you'**
  String get presenceFollowHint;

  /// No description provided for @presenceNone.
  ///
  /// In en, this message translates to:
  /// **'You follow no one. Those who accept you are followed for you.'**
  String get presenceNone;

  /// No description provided for @presenceWaiting.
  ///
  /// In en, this message translates to:
  /// **'Not shown: they have not accepted you, or their relay is out of reach'**
  String get presenceWaiting;

  /// No description provided for @presenceByRelay.
  ///
  /// In en, this message translates to:
  /// **'their relay says they are connected'**
  String get presenceByRelay;

  /// No description provided for @presenceSealed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device sealed to others} other{{count} devices sealed to others}}'**
  String presenceSealed(int count);

  /// No description provided for @presenceMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get presenceMore;

  /// No description provided for @presenceUnfollow.
  ///
  /// In en, this message translates to:
  /// **'Stop following'**
  String get presenceUnfollow;

  /// No description provided for @presenceStopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing with them'**
  String get presenceStopSharing;

  /// No description provided for @presenceStopSharingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Withdraw what you granted {who}? They can no longer call you or follow your presence, and your presence keys change for everyone else who follows you.'**
  String presenceStopSharingConfirm(String who);

  /// No description provided for @presenceRevoked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{{who} held no grant of yours.} =1{Withdrew 1 grant from {who}.} other{Withdrew {count} grants from {who}.}}'**
  String presenceRevoked(int count, String who);

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsSoundTone.
  ///
  /// In en, this message translates to:
  /// **'This app plays a test tone instead of using a microphone and speaker.'**
  String get settingsSoundTone;

  /// No description provided for @settingsSoundNone.
  ///
  /// In en, this message translates to:
  /// **'Calls have no sound in this app.'**
  String get settingsSoundNone;

  /// No description provided for @settingsMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsMicrophone;

  /// No description provided for @settingsSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get settingsSpeaker;

  /// No description provided for @settingsSoundDefault.
  ///
  /// In en, this message translates to:
  /// **'The system\'s default'**
  String get settingsSoundDefault;

  /// No description provided for @settingsSoundSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'{name} (the system\'s default)'**
  String settingsSoundSystemDefault(String name);

  /// No description provided for @settingsSoundRefresh.
  ///
  /// In en, this message translates to:
  /// **'Look for devices again'**
  String get settingsSoundRefresh;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @settingsIdentityFolder.
  ///
  /// In en, this message translates to:
  /// **'Identity folder'**
  String get settingsIdentityFolder;

  /// No description provided for @settingsStun.
  ///
  /// In en, this message translates to:
  /// **'STUN server (optional)'**
  String get settingsStun;

  /// No description provided for @settingsStunHint.
  ///
  /// In en, this message translates to:
  /// **'stun:stun.example.com:3478'**
  String get settingsStunHint;

  /// No description provided for @settingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save and restart'**
  String get settingsSave;

  /// No description provided for @settingsRestartTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart the app?'**
  String get settingsRestartTitle;

  /// No description provided for @settingsRestartBody.
  ///
  /// In en, this message translates to:
  /// **'The app disconnects and connects again with these settings.'**
  String get settingsRestartBody;

  /// No description provided for @settingsRestartCalls.
  ///
  /// In en, this message translates to:
  /// **'The app disconnects and connects again with these settings. Calls in progress end.'**
  String get settingsRestartCalls;

  /// No description provided for @settingsRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get settingsRestart;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Identity backup'**
  String get settingsBackup;

  /// No description provided for @settingsBackupIntro.
  ///
  /// In en, this message translates to:
  /// **'Your identity is a key on this device. If this device is lost, a backup is the only way to keep your identity: a recovery code, sealed under a passphrase you choose.'**
  String get settingsBackupIntro;

  /// No description provided for @settingsBackupMake.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get settingsBackupMake;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your identity'**
  String get backupTitle;

  /// No description provided for @backupPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters. Without it, the code opens nothing: keep them apart.'**
  String get backupPassphraseHint;

  /// No description provided for @backupPassphraseShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 10 characters.'**
  String get backupPassphraseShort;

  /// No description provided for @backupPassphraseAgain.
  ///
  /// In en, this message translates to:
  /// **'The passphrase again'**
  String get backupPassphraseAgain;

  /// No description provided for @backupPassphraseDiffers.
  ///
  /// In en, this message translates to:
  /// **'The two passphrases differ.'**
  String get backupPassphraseDiffers;

  /// No description provided for @backupMake.
  ///
  /// In en, this message translates to:
  /// **'Make the code'**
  String get backupMake;

  /// No description provided for @backupCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get backupCodeTitle;

  /// No description provided for @backupCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Write it down or keep it somewhere safe, with the passphrase apart. Anyone with both is you.'**
  String get backupCodeBody;

  /// No description provided for @backupCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get backupCopy;

  /// No description provided for @backupCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get backupCopied;

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get backupDone;

  /// No description provided for @backupCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get backupCancel;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'No backup: {reason}'**
  String backupFailed(String reason);

  /// No description provided for @settingsDevices.
  ///
  /// In en, this message translates to:
  /// **'Your devices'**
  String get settingsDevices;

  /// No description provided for @settingsDevicesIntro.
  ///
  /// In en, this message translates to:
  /// **'Add another phone or computer to your identity. It gets its own key, and never your identity\'s key.'**
  String get settingsDevicesIntro;

  /// No description provided for @settingsAddDevice.
  ///
  /// In en, this message translates to:
  /// **'Add a device'**
  String get settingsAddDevice;

  /// No description provided for @addDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a device'**
  String get addDeviceTitle;

  /// No description provided for @addDeviceJoin.
  ///
  /// In en, this message translates to:
  /// **'The new device\'s join code'**
  String get addDeviceJoin;

  /// No description provided for @addDeviceJoinNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter the join code the new device shows.'**
  String get addDeviceJoinNeeded;

  /// No description provided for @addDeviceMake.
  ///
  /// In en, this message translates to:
  /// **'Make the welcome code'**
  String get addDeviceMake;

  /// No description provided for @addDeviceWelcome.
  ///
  /// In en, this message translates to:
  /// **'Enter this welcome code on the new device. It should show the same check code: {check}.'**
  String addDeviceWelcome(String check);

  /// No description provided for @settingsWeb.
  ///
  /// In en, this message translates to:
  /// **'Your own domain'**
  String get settingsWeb;

  /// No description provided for @settingsWebIntro.
  ///
  /// In en, this message translates to:
  /// **'Use a DID on a domain you control (did:web) in place of this device\'s key. You can then change keys without losing the identity. People who know you now will see it as a new identity, and need to accept you again.'**
  String get settingsWebIntro;

  /// No description provided for @settingsWebStart.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get settingsWebStart;

  /// No description provided for @webTitle.
  ///
  /// In en, this message translates to:
  /// **'Your own domain'**
  String get webTitle;

  /// No description provided for @webDid.
  ///
  /// In en, this message translates to:
  /// **'Your did:web'**
  String get webDid;

  /// No description provided for @webDidHint.
  ///
  /// In en, this message translates to:
  /// **'did:web:example.com, or did:web:example.com:users:ann'**
  String get webDidHint;

  /// No description provided for @webDidNeeded.
  ///
  /// In en, this message translates to:
  /// **'Enter a DID that starts with did:web:'**
  String get webDidNeeded;

  /// No description provided for @webPrepare.
  ///
  /// In en, this message translates to:
  /// **'Make the document'**
  String get webPrepare;

  /// No description provided for @webServe.
  ///
  /// In en, this message translates to:
  /// **'Serve this at {url}, then check.'**
  String webServe(String url);

  /// No description provided for @webCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get webCheck;

  /// No description provided for @webServed.
  ///
  /// In en, this message translates to:
  /// **'Your domain serves the document.'**
  String get webServed;

  /// No description provided for @webDiffers.
  ///
  /// In en, this message translates to:
  /// **'Not yet: {differences}'**
  String webDiffers(String differences);

  /// No description provided for @webMove.
  ///
  /// In en, this message translates to:
  /// **'Move to it'**
  String get webMove;

  /// No description provided for @webMoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Move your identity?'**
  String get webMoveConfirmTitle;

  /// No description provided for @webMoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'You become {did}. The app restarts, and calls in progress end. Contacts see a new identity and need to accept you again.'**
  String webMoveConfirm(String did);

  /// No description provided for @webFailed.
  ///
  /// In en, this message translates to:
  /// **'That did not work: {reason}'**
  String webFailed(String reason);

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'DSIP {version}'**
  String settingsVersion(String version);

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheck;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @updateLatest.
  ///
  /// In en, this message translates to:
  /// **'This is the latest version.'**
  String get updateLatest;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'DSIP {version} is out.'**
  String updateAvailable(String version);

  /// No description provided for @updateAfterCall.
  ///
  /// In en, this message translates to:
  /// **'DSIP {version} is out: update once your call is over.'**
  String updateAfterCall(String version);

  /// No description provided for @updateByHand.
  ///
  /// In en, this message translates to:
  /// **'DSIP {version} is out. This copy does not update itself ({reason}).'**
  String updateByHand(String version, String reason);

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Getting DSIP {version}…'**
  String updateDownloading(String version);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update: {reason}'**
  String updateFailed(String reason);

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Update and restart'**
  String get updateInstall;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateNotes.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateNotes;

  /// On a phone, when the system refused the microphone.
  ///
  /// In en, this message translates to:
  /// **'DSIP may not use the microphone, so the people you call will not hear you. Allow it in the system\'s settings for DSIP.'**
  String get microphoneRefused;

  /// A call's audio at the phone's earpiece, held to the ear.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get routeEarpiece;

  /// A call's audio on the phone's loudspeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get routeSpeaker;

  /// A call's audio on a Bluetooth headset or car, when the system gives no name.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get routeBluetooth;

  /// A call's audio on a headset on a wire.
  ///
  /// In en, this message translates to:
  /// **'Headset'**
  String get routeWired;

  /// Opens the dialog to give an identity a name on this device (a menu item, a button's tooltip).
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameAction;

  /// The naming dialog's title.
  ///
  /// In en, this message translates to:
  /// **'Name {who}'**
  String nameTitle(String who);

  /// The naming dialog's field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameField;

  /// Under the naming dialog's field.
  ///
  /// In en, this message translates to:
  /// **'Kept on this device only. Leave it empty to remove the name.'**
  String get nameHint;

  /// The naming dialog's button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get nameSave;

  /// Why a call ended, for the reason code user.hangup.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get reasonUserHangup;

  /// Why a call ended, for the reason code user.declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get reasonUserDeclined;

  /// Why a call ended, for the reason code user.no-answer.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get reasonUserNoAnswer;

  /// Why a call ended, for the reason code user.cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get reasonUserCancelled;

  /// Why a call ended, for the reason code user.blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get reasonUserBlocked;

  /// Why a call ended, for the reason code endpoint.busy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get reasonEndpointBusy;

  /// Why a call ended, for the reason code endpoint.unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get reasonEndpointUnavailable;

  /// Why a call ended, for the reason code endpoint.capability.
  ///
  /// In en, this message translates to:
  /// **'Their device can\'t take this kind of call'**
  String get reasonEndpointCapability;

  /// Why a call ended, for the reason code endpoint.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'Their device couldn\'t take the call'**
  String get reasonEndpoint;

  /// Why a call ended, for the reason code identity.not-in-service.
  ///
  /// In en, this message translates to:
  /// **'Not in service'**
  String get reasonIdentityNotInService;

  /// Why a call ended, for the reason code identity.moved.
  ///
  /// In en, this message translates to:
  /// **'This identity has moved'**
  String get reasonIdentityMoved;

  /// Why a call ended, for the reason code identity.suspended.
  ///
  /// In en, this message translates to:
  /// **'This identity is suspended'**
  String get reasonIdentitySuspended;

  /// Why a call ended, for the reason code identity.unknown.
  ///
  /// In en, this message translates to:
  /// **'No such identity'**
  String get reasonIdentityUnknown;

  /// Why a call ended, for the reason code identity.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'This identity can\'t be reached'**
  String get reasonIdentity;

  /// Why a call ended, for the reason code session.timeout, session.expired.
  ///
  /// In en, this message translates to:
  /// **'No answer in time'**
  String get reasonSessionTimeout;

  /// Why a call ended, for the reason code session.answered-elsewhere, session.already-answered.
  ///
  /// In en, this message translates to:
  /// **'Answered on another device'**
  String get reasonSessionElsewhere;

  /// Why a call ended, for the reason code session.cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get reasonSessionCancelled;

  /// Why a call ended, for the reason code session.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'The call failed'**
  String get reasonSession;

  /// Why a call ended, for the reason code media.failed.
  ///
  /// In en, this message translates to:
  /// **'The sound connection failed'**
  String get reasonMediaFailed;

  /// Why a call ended, for the reason code media.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t agree on how to send sound'**
  String get reasonMedia;

  /// Why a call ended, for the reason code policy.first-contact-required.
  ///
  /// In en, this message translates to:
  /// **'They haven\'t accepted you yet'**
  String get reasonPolicyFirstContact;

  /// Why a call ended, for the reason code policy.rate-limited.
  ///
  /// In en, this message translates to:
  /// **'Too many calls: try again later'**
  String get reasonPolicyRateLimited;

  /// Why a call ended, for the reason code policy.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get reasonPolicy;

  /// Why a call ended, for the reason code transport.unknown-recipient, transport.no-response.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach them'**
  String get reasonTransportUnreached;

  /// Why a call ended, for the reason code transport.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'The connection was lost'**
  String get reasonTransport;

  /// Why a call ended, for the reason code gateway.* (any other code in that category, §15.3).
  ///
  /// In en, this message translates to:
  /// **'The phone network couldn\'t connect the call'**
  String get reasonGateway;

  /// Tooltip on why a call ended: the raw reason code, for support.
  ///
  /// In en, this message translates to:
  /// **'Reason code: {code}'**
  String callEndedCode(String code);

  /// In the recovery code dialog, when there are names or followed identities to keep: the code holds the identity only; the backup text holds them too, sealed under the same passphrase.
  ///
  /// In en, this message translates to:
  /// **'The names you gave people, and who you follow, are not in the code. Copy the backup with names, keep that text with the code, and restore from it to bring them back.'**
  String get backupContactsBody;

  /// Copies the whole backup text (the code, and the names and followed identities sealed under the same passphrase).
  ///
  /// In en, this message translates to:
  /// **'Copy with names'**
  String get backupCopyFile;

  /// A button that opens the camera to read a pairing code shown as a QR code on another device.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanButton;

  /// The camera page's title.
  ///
  /// In en, this message translates to:
  /// **'Scan the code'**
  String get scanTitle;

  /// Under the camera's view.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code on the other device.'**
  String get scanHint;

  /// What a screen reader says of a pairing code's QR code.
  ///
  /// In en, this message translates to:
  /// **'The code as a QR code, for the other device\'s camera'**
  String get scanQrLabel;

  /// When the camera cannot be used: no permission, no camera.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available ({reason}). Type or paste the code instead.'**
  String scanNoCamera(String reason);

  /// Saves the whole backup text (the code, and the names and followed identities sealed under the same passphrase) as a file where the person chooses.
  ///
  /// In en, this message translates to:
  /// **'Save as a file'**
  String get backupSaveFile;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get backupSaved;

  /// No description provided for @backupSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The file was not saved: {reason}'**
  String backupSaveFailed(String reason);

  /// Opens a backup file saved earlier, putting its text in the recovery code field.
  ///
  /// In en, this message translates to:
  /// **'Open a backup file'**
  String get firstRunOpenFile;

  /// No description provided for @firstRunRestoreServers.
  ///
  /// In en, this message translates to:
  /// **'A backup file also brings back the servers it was made with. The server below is used only when it has none.'**
  String get firstRunRestoreServers;

  /// No description provided for @firstRunOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read as a backup: {reason}'**
  String firstRunOpenFailed(String reason);

  /// No description provided for @firstRunJoinNearby.
  ///
  /// In en, this message translates to:
  /// **'A phone with your identity can scan this QR code instead. On the same network, the welcome code then comes back here by itself.'**
  String get firstRunJoinNearby;

  /// A welcome code arrived over the local network; it names the identity it would join.
  ///
  /// In en, this message translates to:
  /// **'Received from {name} ({identity}). Start only if this is your identity.'**
  String firstRunWelcomeReceived(String name, String identity);

  /// No description provided for @addDeviceSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to the new device. Check that it shows the same check code: {check}.'**
  String addDeviceSent(String check);

  /// No description provided for @addDeviceNotSent.
  ///
  /// In en, this message translates to:
  /// **'The new device could not be reached ({reason}). Enter this welcome code on it instead.'**
  String addDeviceNotSent(String reason);

  /// No description provided for @navContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get navContacts;

  /// No description provided for @contactsNone.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet. Whoever accepts your introduction, and whoever you accept, is added here.'**
  String get contactsNone;

  /// No description provided for @contactAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a contact'**
  String get contactAdd;

  /// No description provided for @contactAddTitle.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get contactAddTitle;

  /// No description provided for @contactCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get contactCall;

  /// No description provided for @contactMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get contactMessage;

  /// No description provided for @contactRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get contactRename;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @contactDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name} from your contacts? Your calls and conversations with them stay.'**
  String contactDeleteConfirm(String name);

  /// No description provided for @contactMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Message {name}'**
  String contactMessageTitle(String name);

  /// No description provided for @introduceName.
  ///
  /// In en, this message translates to:
  /// **'What to call them'**
  String get introduceName;

  /// No description provided for @introduceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. Saved as your contact once they accept'**
  String get introduceNameHint;

  /// No description provided for @introducedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your introductions'**
  String get introducedTitle;

  /// No description provided for @introducedWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for them to accept'**
  String get introducedWaiting;

  /// No description provided for @introducedAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted: you can message them'**
  String get introducedAccepted;

  /// No description provided for @introducedForget.
  ///
  /// In en, this message translates to:
  /// **'Remove from this list'**
  String get introducedForget;

  /// No description provided for @messageDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this message from this device? The others in the conversation keep theirs.'**
  String get messageDeleteConfirm;

  /// No description provided for @conversationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get conversationDelete;

  /// No description provided for @conversationDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation\'s messages from this device? It comes back if a new message arrives.'**
  String get conversationDeleteConfirm;

  /// No description provided for @groupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave this group and delete its messages from this device?'**
  String get groupDeleteConfirm;

  /// No description provided for @callBack.
  ///
  /// In en, this message translates to:
  /// **'Call back'**
  String get callBack;

  /// No description provided for @callMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get callMissed;

  /// No description provided for @callsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get callsClear;

  /// No description provided for @callsClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete your whole call history on this device?'**
  String get callsClearConfirm;

  /// No description provided for @callForget.
  ///
  /// In en, this message translates to:
  /// **'Delete from history'**
  String get callForget;

  /// No description provided for @settingsAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get settingsAlerts;

  /// No description provided for @alertsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Show alerts'**
  String get alertsEnabled;

  /// No description provided for @alertsEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'In the app, and from the system while the app is in the background'**
  String get alertsEnabledHint;

  /// No description provided for @alertsMessages.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get alertsMessages;

  /// No description provided for @alertsRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests to message you, and answers to yours'**
  String get alertsRequests;

  /// No description provided for @alertsCalls.
  ///
  /// In en, this message translates to:
  /// **'Missed calls, and calls ringing while the app is in the background'**
  String get alertsCalls;

  /// No description provided for @alertOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get alertOpen;

  /// No description provided for @alertRequest.
  ///
  /// In en, this message translates to:
  /// **'{name} asks to message you'**
  String alertRequest(String name);

  /// No description provided for @alertGranted.
  ///
  /// In en, this message translates to:
  /// **'{name} accepted you'**
  String alertGranted(String name);

  /// No description provided for @alertGrantedBody.
  ///
  /// In en, this message translates to:
  /// **'You can message them now.'**
  String get alertGrantedBody;

  /// No description provided for @alertMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed call from {name}'**
  String alertMissed(String name);

  /// No description provided for @alertIncoming.
  ///
  /// In en, this message translates to:
  /// **'{name} is calling'**
  String alertIncoming(String name);

  /// No description provided for @attachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get attachAction;

  /// No description provided for @attachSending.
  ///
  /// In en, this message translates to:
  /// **'Sending {name}…'**
  String attachSending(String name);

  /// No description provided for @attachmentFetching.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get attachmentFetching;

  /// No description provided for @attachmentOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get attachmentOpen;

  /// No description provided for @attachmentSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get attachmentSave;

  /// No description provided for @attachmentSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get attachmentSaved;

  /// No description provided for @attachmentNotOpened.
  ///
  /// In en, this message translates to:
  /// **'Could not open it here. Save it, then open it from where you saved it.'**
  String get attachmentNotOpened;

  /// A message that is a recording of someone speaking, sent instead of typed.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessage;

  /// A recording a caller left after a call that was not answered.
  ///
  /// In en, this message translates to:
  /// **'Voicemail'**
  String get voicemail;

  /// No description provided for @voiceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record a voice message'**
  String get voiceRecord;

  /// No description provided for @voicePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get voicePlay;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceRecordingTime.
  ///
  /// In en, this message translates to:
  /// **'Recording {time}'**
  String voiceRecordingTime(String time);

  /// No description provided for @voiceRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded {time}'**
  String voiceRecorded(String time);

  /// No description provided for @voiceDrop.
  ///
  /// In en, this message translates to:
  /// **'Delete the recording'**
  String get voiceDrop;

  /// No description provided for @voicemailOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} didn\'t answer'**
  String voicemailOfferTitle(String name);

  /// No description provided for @voicemailOfferBody.
  ///
  /// In en, this message translates to:
  /// **'Leave a voicemail? Up to {time}.'**
  String voicemailOfferBody(String time);

  /// No description provided for @voicemailRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get voicemailRecord;

  /// No description provided for @voicemailSent.
  ///
  /// In en, this message translates to:
  /// **'Voicemail sent.'**
  String get voicemailSent;
}

class _StringsDelegate extends LocalizationsDelegate<Strings> {
  const _StringsDelegate();

  @override
  Future<Strings> load(Locale locale) {
    return SynchronousFuture<Strings>(lookupStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_StringsDelegate old) => false;
}

Strings lookupStrings(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'XA':
            return StringsEnXa();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return StringsEn();
  }

  throw FlutterError(
    'Strings.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
