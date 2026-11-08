// Why a call ended, in words (§15): a registered code's own words, a code unknown in a known category its category's,
// an unknown category `session.failed`'s; the raw code kept in a tooltip.

import 'package:dsip_app/l10n/app_localizations_en.dart';
import 'package:dsip_app/src/screens/reasons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = StringsEn();

  test('a registered code has its own words', () {
    expect(endedReason(s, 'user.hangup'), 'Ended');
    expect(endedReason(s, 'user.declined'), 'Declined');
    expect(endedReason(s, 'endpoint.busy'), 'Busy');
    expect(endedReason(s, 'session.answered-elsewhere'), 'Answered on another device');
    expect(endedReason(s, 'policy.first-contact-required'), "They haven't accepted you yet");
  });

  test("a code unknown in a known category takes the category's words (§15.3)", () {
    expect(endedReason(s, 'endpoint.overheated'), "Their device couldn't take the call");
    expect(endedReason(s, 'transport.closed'), 'The connection was lost', reason: "the app's own, for a dropped link");
    expect(endedReason(s, 'user.wandered-off'), 'Ended');
    expect(endedReason(s, 'session.invalid-state'), 'The call failed');
  });

  test("an unknown category, or no code, is session.failed's (§15.3)", () {
    expect(endedReason(s, 'weather.stormy'), 'The call failed');
    expect(endedReason(s, 'nodot'), 'The call failed');
    expect(endedReason(s, null), 'The call failed');
  });
}
