import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';

void main() {
  test('invite URI round-trips without losing the secret', () {
    const invite = AuctionShareInvite(
      sessionId: 'auction_123',
      ownerUid: 'alice',
      token: 'abcdefghijklmnopqrstuvwxyz123456',
    );

    final parsed = AuctionShareInvite.tryParse(invite.toUri().toString());

    expect(parsed, isNotNull);
    expect(parsed!.sessionId, invite.sessionId);
    expect(parsed.ownerUid, invite.ownerUid);
    expect(parsed.token, invite.token);
  });

  test('rejects malformed or short invite payloads', () {
    expect(AuctionShareInvite.tryParse('https://example.com'), isNull);
    expect(
      AuctionShareInvite.tryParse(
        'astamatrix://join?session=a&owner=b&token=too-short',
      ),
      isNull,
    );
  });
}
