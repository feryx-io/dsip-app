import '../../l10n/app_localizations.dart';

/// Why a call ended, in words, from its reason code (`category.condition`). A code the app has no words for takes its
/// category's (the app's own `transport.closed`, a dropped connection, among them); a category it does not know is
/// `session.failed`'s. Spec: §15.2, §15.3, §15.4.
String endedReason(Strings s, String? code) {
  final c = code ?? 'session.failed';
  return switch (c) {
    'user.hangup' => s.reasonUserHangup,
    'user.declined' => s.reasonUserDeclined,
    'user.no-answer' => s.reasonUserNoAnswer,
    'user.cancelled' => s.reasonUserCancelled,
    'user.blocked' => s.reasonUserBlocked,
    'endpoint.busy' => s.reasonEndpointBusy,
    'endpoint.unavailable' => s.reasonEndpointUnavailable,
    'endpoint.capability' => s.reasonEndpointCapability,
    'identity.not-in-service' => s.reasonIdentityNotInService,
    'identity.moved' => s.reasonIdentityMoved,
    'identity.suspended' => s.reasonIdentitySuspended,
    'identity.unknown' => s.reasonIdentityUnknown,
    'session.timeout' || 'session.expired' => s.reasonSessionTimeout,
    'session.answered-elsewhere' || 'session.already-answered' => s.reasonSessionElsewhere,
    'session.cancelled' => s.reasonSessionCancelled,
    'media.failed' => s.reasonMediaFailed,
    'policy.first-contact-required' => s.reasonPolicyFirstContact,
    'policy.rate-limited' => s.reasonPolicyRateLimited,
    'transport.unknown-recipient' || 'transport.no-response' => s.reasonTransportUnreached,
    _ => switch (c.split('.').first) {
      'user' => s.reasonUserHangup,
      'endpoint' => s.reasonEndpoint,
      'identity' => s.reasonIdentity,
      'session' => s.reasonSession,
      'media' => s.reasonMedia,
      'policy' => s.reasonPolicy,
      'transport' => s.reasonTransport,
      'gateway' => s.reasonGateway,
      _ => s.reasonSession,
    },
  };
}
