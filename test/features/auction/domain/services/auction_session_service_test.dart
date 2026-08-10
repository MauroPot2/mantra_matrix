import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const service = AuctionSessionService();
  const config = AuctionConfig(
    initialCredits: 100,
    rosterSize: 3,
    minimumBid: 1,
  );

  test('assegnazione aggiorna giocatore, rosa e crediti', () {
    var session = buildSession();

    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );
    session = service.changeCurrentBid(
      session,
      bid: 12,
      eventId: 'e2',
      occurredAt: date(2),
    );
    session = service.assignActivePlayer(
      session,
      teamId: 't1',
      eventId: 'e3',
      occurredAt: date(3),
    );

    final state = service.snapshot(session);
    final player = state.playersById['p1']!;
    final team = state.teamsById['t1']!;

    expect(player.status, DraftStatus.drafted);
    expect(player.draftedByTeamId, 't1');
    expect(player.purchasePrice, 12);
    expect(team.creditsRemaining, 88);
    expect(team.roster.single.id, 'p1');
    expect(state.activePlayerId, isNull);
    expect(state.assignmentsByPlayerId['p1']!.price, 12);
    expect(state.availablePlayers.map((player) => player.id), isNot(contains('p1')));
    expect(state.uncalledPlayers.map((player) => player.id), isNot(contains('p1')));
    expect(state.unsoldPlayers.map((player) => player.id), isNot(contains('p1')));
    expect(state.draftedPlayers.map((player) => player.id), contains('p1'));
  });

  test('impedisce una spesa che non consente di completare la rosa', () {
    var session = AuctionSession(
      id: 'session',
      name: 'Asta test',
      config: config,
      createdAt: date(0),
      initialPlayers: [buildPlayer('p1')],
      initialTeams: const [
        FantasyTeamEntity(
          id: 't1',
          name: 'Matrix FC',
          creditsRemaining: 10,
        ),
      ],
    );

    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );

    // Con tre slot vuoti, dopo l'acquisto devono restare almeno 2 crediti.
    expect(
      () => service.assignActivePlayer(
        session,
        teamId: 't1',
        price: 9,
        eventId: 'e2',
        occurredAt: date(2),
      ),
      throwsA(isA<AuctionSessionException>()),
    );
  });

  test('undo dell’assegnazione ripristina budget e giocatore chiamato', () {
    var session = buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );
    session = service.changeCurrentBid(
      session,
      bid: 12,
      eventId: 'e2',
      occurredAt: date(2),
    );
    session = service.assignActivePlayer(
      session,
      teamId: 't1',
      eventId: 'e3',
      occurredAt: date(3),
    );
    session = service.undoLast(
      session,
      eventId: 'e4',
      occurredAt: date(4),
    );

    final state = service.snapshot(session);
    final player = state.playersById['p1']!;
    final team = state.teamsById['t1']!;

    expect(player.status, DraftStatus.available);
    expect(player.draftedByTeamId, isNull);
    expect(player.purchasePrice, isNull);
    expect(team.creditsRemaining, 100);
    expect(team.roster, isEmpty);
    expect(state.activePlayerId, 'p1');
    expect(state.currentBid, 12);
    expect(state.revertedEventIds, contains('e3'));
  });

  test('undo ripetuto torna al prezzo precedente e poi alla chiamata', () {
    var session = buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );
    session = service.changeCurrentBid(
      session,
      bid: 5,
      eventId: 'e2',
      occurredAt: date(2),
    );
    session = service.changeCurrentBid(
      session,
      bid: 8,
      eventId: 'e3',
      occurredAt: date(3),
    );

    session = service.undoLast(
      session,
      eventId: 'e4',
      occurredAt: date(4),
    );
    expect(service.snapshot(session).currentBid, 5);

    session = service.undoLast(
      session,
      eventId: 'e5',
      occurredAt: date(5),
    );
    expect(service.snapshot(session).currentBid, 1);
  });

  test('saltare mantiene il giocatore disponibile e undo riapre la chiamata', () {
    var session = buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );
    session = service.skipActivePlayer(
      session,
      eventId: 'e2',
      occurredAt: date(2),
    );

    final skippedState = service.snapshot(session);
    expect(skippedState.activePlayerId, isNull);
    expect(skippedState.playersById['p1']!.status, DraftStatus.available);
    expect(skippedState.unsoldPlayers.map((player) => player.id), ['p1']);
    expect(skippedState.uncalledPlayers.map((player) => player.id), ['p2']);

    session = service.undoLast(
      session,
      eventId: 'e3',
      occurredAt: date(3),
    );
    final restoredState = service.snapshot(session);
    expect(restoredState.activePlayerId, 'p1');
    expect(restoredState.unsoldPlayers, isEmpty);
  });

  test('uno svincolato può essere richiamato e poi assegnato', () {
    var session = buildSession();
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: date(1),
    );
    session = service.skipActivePlayer(
      session,
      eventId: 'e2',
      occurredAt: date(2),
    );

    expect(service.snapshot(session).unsoldPlayerIds, ['p1']);

    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e3',
      occurredAt: date(3),
    );
    expect(service.snapshot(session).unsoldPlayers, isEmpty);

    session = service.assignActivePlayer(
      session,
      teamId: 't2',
      price: 7,
      eventId: 'e4',
      occurredAt: date(4),
    );

    final state = service.snapshot(session);
    expect(state.unsoldPlayers, isEmpty);
    expect(state.availablePlayers.map((player) => player.id), isNot(contains('p1')));
    expect(state.teamsById['t2']!.roster.single.id, 'p1');
  });

  test('evento serializzato viene ricostruito senza perdere dati', () {
    final original = AuctionEvent.playerAssigned(
      id: 'e1',
      occurredAt: date(1),
      playerId: 'p1',
      teamId: 't1',
      price: 17,
    );

    final restored = AuctionEvent.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.type, AuctionEventType.playerAssigned);
    expect(restored.playerId, 'p1');
    expect(restored.teamId, 't1');
    expect(restored.amount, 17);
    expect(restored.occurredAt, original.occurredAt);
  });

  test('timer condiviso assegna il giocatore alla squadra leader', () {
    var session = buildSession().copyWith(
      config: config.copyWith(bidDurationSeconds: 30),
    );
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'timer-call',
      occurredAt: date(1),
    );
    session = service.placeBid(
      session,
      teamId: 't2',
      bid: 7,
      eventId: 'timer-bid',
      occurredAt: date(1).add(const Duration(seconds: 5)),
    );

    final liveState = service.snapshot(session);
    expect(liveState.activeBid!.leadingTeamId, 't2');
    expect(
      liveState.activeBid!.endsAt,
      date(1).add(const Duration(seconds: 30)),
    );

    session = service.settleExpiredLot(
      session,
      occurredAt: date(1).add(const Duration(seconds: 31)),
    );
    final settled = service.snapshot(session);
    expect(settled.playersById['p1']!.draftedByTeamId, 't2');
    expect(settled.playersById['p1']!.purchasePrice, 7);
  });

  test('timer senza offerte sposta il giocatore tra gli svincolati', () {
    var session = buildSession().copyWith(
      config: config.copyWith(bidDurationSeconds: 15),
    );
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'empty-call',
      occurredAt: date(1),
    );
    session = service.settleExpiredLot(
      session,
      occurredAt: date(1).add(const Duration(seconds: 16)),
    );

    expect(service.snapshot(session).unsoldPlayerIds, ['p1']);
  });

  test('una sessione legacy senza timer accetta offerte tardive', () {
    var session = buildSession().copyWith(
      config: config.copyWith(bidDurationSeconds: 0),
    );
    session = service.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'legacy-call',
      occurredAt: date(1),
    );
    session = service.placeBid(
      session,
      teamId: 't1',
      bid: 4,
      eventId: 'legacy-bid',
      occurredAt: date(1).add(const Duration(days: 1)),
    );

    expect(service.snapshot(session).currentBid, 4);
  });
}

AuctionSession buildSession() {
  return AuctionSession(
    id: 'session',
    name: 'Asta test',
    config: const AuctionConfig(
      initialCredits: 100,
      rosterSize: 3,
      minimumBid: 1,
    ),
    createdAt: date(0),
    initialPlayers: [buildPlayer('p1'), buildPlayer('p2')],
    initialTeams: const [
      FantasyTeamEntity(
        id: 't1',
        name: 'Matrix FC',
        creditsRemaining: 100,
      ),
      FantasyTeamEntity(
        id: 't2',
        name: 'Rival FC',
        creditsRemaining: 100,
      ),
    ],
  );
}

PlayerEntity buildPlayer(String id) {
  return PlayerEntity(
    id: id,
    name: 'Player $id',
    team: 'TEST',
    roles: const [MantraRole.c],
    basePrice: 10,
    expectedGoals: 2,
    expectedAssists: 3,
    expectedGoals90: 0.1,
    expectedAssists90: 0.2,
    expectedYellowCards: 3,
    historicalMinutes: 2000,
  );
}

DateTime date(int minute) => DateTime.utc(2026, 7, 27, 10, minute);
