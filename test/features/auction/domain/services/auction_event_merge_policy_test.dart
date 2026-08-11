import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_event_merge_policy.dart';

void main() {
  const policy = AuctionEventMergePolicy();

  test('keeps a pending raise after the event just confirmed by Firestore', () {
    final localFirst = raised('e1', minute: 1, bid: 2);
    final localSecond = raised('e2', minute: 2, bid: 3);
    final confirmedFirst = withRevision(localFirst, 1);

    final result = policy.merge(
      localEvents: [localFirst, localSecond],
      remoteEvents: [confirmedFirst],
      pendingEventIds: const ['e1', 'e2'],
    );

    expect(result.events.map((event) => event.id), ['e1', 'e2']);
    expect(result.events.first.serverRevision, 1);
    expect(result.events.last.serverRevision, isNull);
    expect(result.pendingEventIds, ['e2']);
  });

  test('rapid pending raises preserve their local production order', () {
    final local1 = raised('e1', minute: 1, bid: 2);
    final local2 = raised('e2', minute: 2, bid: 3);
    final local3 = raised('e3', minute: 3, bid: 4);

    final result = policy.merge(
      localEvents: [local1, local2, local3],
      remoteEvents: [withRevision(local1, 10)],
      pendingEventIds: const ['e1', 'e2', 'e3'],
    );

    expect(result.events.map((event) => event.id), ['e1', 'e2', 'e3']);
    expect(result.pendingEventIds, ['e2', 'e3']);
  });

  test('server copy replaces the optimistic copy and clears pending id', () {
    final local1 = raised('e1', minute: 1, bid: 2);
    final local2 = raised('e2', minute: 2, bid: 3);

    final result = policy.merge(
      localEvents: [local1, local2],
      remoteEvents: [withRevision(local2, 2), withRevision(local1, 1)],
      pendingEventIds: const ['e1', 'e2'],
    );

    expect(result.events.map((event) => event.id), ['e1', 'e2']);
    expect(result.events.map((event) => event.serverRevision), [1, 2]);
    expect(result.pendingEventIds, isEmpty);
  });
}

AuctionEvent raised(
  String id, {
  required int minute,
  required int bid,
}) {
  return AuctionEvent.bidRaised(
    id: id,
    occurredAt: DateTime.utc(2026, 8, 11, 10, minute),
    playerId: 'p1',
    bid: bid,
    clockExtensionSeconds: 5,
  );
}

AuctionEvent withRevision(AuctionEvent event, int revision) {
  return AuctionEvent.fromJson({
    ...event.toJson(),
    'server_revision': revision,
  });
}
