import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';

void main() {
  test('invite URI round-trips token and human entry code', () {
    const invite = AuctionShareInvite(
      sessionId: 'auction_123',
      ownerUid: 'alice',
      token: 'abcdefghijklmnopqrstuvwxyz123456',
      entryCode: '7K9MP4QX',
    );

    final parsed = AuctionShareInvite.tryParse(invite.toUri().toString());

    expect(parsed, isNotNull);
    expect(parsed!.sessionId, invite.sessionId);
    expect(parsed.ownerUid, invite.ownerUid);
    expect(parsed.token, invite.token);
    expect(parsed.entryCode, invite.entryCode);
    expect(parsed.formattedEntryCode, '7K9M-P4QX');
  });

  test('normalizes typed entry codes', () {
    expect(
      AuctionShareInvite.normalizeEntryCode(' 7k9m-p4qx '),
      '7K9MP4QX',
    );
  });

  test('rejects malformed or incomplete invite payloads', () {
    expect(AuctionShareInvite.tryParse('https://example.com'), isNull);
    expect(
      AuctionShareInvite.tryParse(
        'astamatrix://join?session=a&owner=b&token=too-short&code=7K9MP4QX',
      ),
      isNull,
    );
    expect(
      AuctionShareInvite.tryParse(
        'astamatrix://join?session=a&owner=b&token=abcdefghijklmnopqrstuvwxyz123456',
      ),
      isNull,
    );
  });
}
