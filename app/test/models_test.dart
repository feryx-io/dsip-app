import 'package:dsip_app/src/client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

void main() {
  test('the update dsip-app sends is read whole', () {
    final u = Update.fromJson(fixture());
    expect(u.kind, 'call_changed');
    final s = u.state;
    expect(s.me.displayName, 'Alice');
    expect(s.relay, startsWith('wss://'));
    expect(s.calls.map((c) => c.id), [1, 2, 3]);
    expect(s.calls[0].state.ended, isTrue);
    expect(s.calls[0].state.reason, 'user.hangup');
    expect(s.calls[1].state.answeredBy, 'user');
    expect(s.calls[1].muted, isTrue);
    expect(s.calls[1].via, isNotNull);
    expect(s.calls[2].ringingHere, isTrue);
    expect(s.calls[2].peerName, 'Bob');
    expect(s.live.map((c) => c.id), [3, 2], reason: 'the latest first, the ended one left out');
    expect(s.audio.devices.single.isDefault, isTrue);
    expect(s.messaging.connected, isTrue);
    expect(s.messaging.conversations.single.pending, 1);
    expect(s.messaging.requests.single.name, 'Carol');
    expect(s.presence.mine, 'busy');
    expect(s.presence.following.single.unreadable, 1);
  });
}
