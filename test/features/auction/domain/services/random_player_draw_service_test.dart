import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/auction/domain/services/random_player_draw_service.dart';

import 'auction_session_service_test.dart' as fixtures;

void main() {
  const sessionService = AuctionSessionService();

  test('draw selects only from players never called yet', () {
    var session = fixtures.buildSession();
    session = sessionService.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );
    session = sessionService.skipActivePlayer(
      session,
      eventId: 'e2',
      occurredAt: fixtures.date(2),
    );

    final snapshot = sessionService.snapshot(session);
    final draw = RandomPlayerDrawService(random: Random(0)).draw(snapshot);

    expect(snapshot.unsoldPlayers.map((player) => player.id), ['p1']);
    expect(snapshot.uncalledPlayers.map((player) => player.id), ['p2']);
    expect(draw.id, 'p2');
  });

  test('draw refuses to preselect while another call is active', () {
    var session = fixtures.buildSession();
    session = sessionService.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );

    final snapshot = sessionService.snapshot(session);

    expect(
      () => RandomPlayerDrawService(random: Random(0)).draw(snapshot),
      throwsA(isA<RandomPlayerDrawException>()),
    );
  });

  test('draw does not expose a persisted future order', () {
    final snapshot = sessionService.snapshot(fixtures.buildSession());
    final serviceA = RandomPlayerDrawService(random: Random(1));
    final serviceB = RandomPlayerDrawService(random: Random(2));

    final drawA = serviceA.draw(snapshot);
    final drawB = serviceB.draw(snapshot);

    expect(snapshot.activePlayerId, isNull);
    expect(snapshot.uncalledPlayers.length, 2);
    expect([drawA.id, drawB.id], everyElement(isIn(['p1', 'p2'])));
  });
}
