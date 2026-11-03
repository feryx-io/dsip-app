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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

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
  /// **'Hints node (optional)'**
  String get firstRunHints;

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

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended: {reason}'**
  String callEnded(String reason);

  /// No description provided for @callNoSound.
  ///
  /// In en, this message translates to:
  /// **'No sound yet'**
  String get callNoSound;

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
