import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_undo_clock_policy.dart';

import 'auction_session_service_test.dart' as fixtures;

void main() {
  const policy = AuctionUndoClockPolicy();
  const service = AuctionSessionService();

  test('undo di un rilancio rimuove solo la sua estensione', () {
    var session = fixtures.buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );
    session = service.raiseCurrentBid(
      session,
      bid: 5,
      eventId: 'e2',
      occurredAt: fixtures.date(2),
    );
    session = service.undoLast(
      session,
      eventId: 'e3',
      occurredAt: fixtures.date(3),
    );

    final undo = session.events.last;
    final snapshot = service.snapshot(session);
    final decision = policy.decide(
      undoEvent: undo,
      snapshotAfterUndo: snapshot,
      currentPhase: AuctionClockPhase.running,
      currentActivePlayerId: 'p1',
      currentExtensionSeconds: 10,
    );

    expect(undo.clockExtensionSeconds, -5);
    expect(decision.action, AuctionUndoClockAction.preserve);
    expect(decision.extensionSeconds, 5);
  });

  test('undo di una correzione prezzo conserva il timer invariato', () {
    var session = fixtures.buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );
    session = service.changeCurrentBid(
      session,
      bid: 4,
      eventId: 'e2',
      occurredAt: fixtures.date(2),
    );
    session = service.undoLast(
      session,
      eventId: 'e3',
      occurredAt: fixtures.date(3),
    );

    final decision = policy.decide(
      undoEvent: session.events.last,
      snapshotAfterUndo: service.snapshot(session),
      currentPhase: AuctionClockPhase.running,
      currentActivePlayerId: 'p1',
      currentExtensionSeconds: 15,
    );

    expect(decision.action, AuctionUndoClockAction.preserve);
    expect(decision.extensionSeconds, 15);
  });

  test('undo della nomina chiude il clock', () {
    var session = fixtures.buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );
    session = service.undoLast(
      session,
      eventId: 'e2',
      occurredAt: fixtures.date(2),
    );

    final decision = policy.decide(
      undoEvent: session.events.last,
      snapshotAfterUndo: service.snapshot(session),
      currentPhase: AuctionClockPhase.running,
      currentActivePlayerId: 'p1',
      currentExtensionSeconds: 5,
    );

    expect(decision.action, AuctionUndoClockAction.clear);
    expect(decision.extensionSeconds, 0);
  });

  test('undo di una chiusura riapre con countdown pieno', () {
    var session = fixtures.buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: fixtures.date(1),
    );
    session = service.assignActivePlayer(
      session,
      teamId: 't1',
      eventId: 'e2',
      occurredAt: fixtures.date(2),
    );
    session = service.undoLast(
      session,
      eventId: 'e3',
      occurredAt: fixtures.date(3),
    );

    final AuctionSessionSnapshot snapshot = service.snapshot(session);
    final decision = policy.decide(
      undoEvent: session.events.last,
      snapshotAfterUndo: snapshot,
      currentPhase: AuctionClockPhase.idle,
      currentActivePlayerId: null,
      currentExtensionSeconds: 0,
    );

    expect(snapshot.activePlayerId, 'p1');
    expect(decision.action, AuctionUndoClockAction.restart);
    expect(decision.extensionSeconds, 0);
  });
}
