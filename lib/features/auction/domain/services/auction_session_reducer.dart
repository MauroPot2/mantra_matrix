import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/bid_snapshot.dart';
import 'package:mantra_matrix/features/auction/domain/entities/roster_assignment.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionSessionReducer {
  const AuctionSessionReducer();

  AuctionSessionSnapshot reduce(AuctionSession session) {
    final players = {
      for (final player in session.initialPlayers) player.id: player,
    };
    final teams = {for (final team in session.initialTeams) team.id: team};
    final assignments = <String, RosterAssignment>{};
    final unsoldPlayerIds = <String>[];

    final revertedEventIds = session.events
        .where((event) => event.type == AuctionEventType.eventReverted)
        .map((event) => event.targetEventId)
        .whereType<String>()
        .toSet();

    String? activePlayerId;
    BidSnapshot? activeBid;
    AuctionEvent? lastReversibleEvent;

    for (final event in session.events) {
      if (event.isReversion || revertedEventIds.contains(event.id)) {
        continue;
      }

      lastReversibleEvent = event;

      switch (event.type) {
        case AuctionEventType.playerNominated:
          final nominatedPlayer = players[event.playerId];
          if (nominatedPlayer == null) {
            throw StateError('Evento ${event.id}: giocatore inesistente.');
          }
          if (nominatedPlayer.status != DraftStatus.available) {
            throw StateError('Evento ${event.id}: giocatore non disponibile.');
          }
          if (activePlayerId != null) {
            throw StateError(
              'Evento ${event.id}: esiste già una chiamata attiva.',
            );
          }
          // Se era già passato come invenduto, durante la nuova chiamata
          // esce temporaneamente dalla lista dedicata.
          unsoldPlayerIds.remove(event.playerId);
          activePlayerId = event.playerId;
          activeBid = BidSnapshot(
            playerId: event.playerId!,
            currentBid: session.config.minimumBid,
            updatedAt: event.occurredAt,
            sourceEventId: event.id,
            nominationEventId: event.id,
            endsAt: session.config.bidDurationSeconds == 0
                ? DateTime.utc(9999)
                : event.occurredAt.add(
                    Duration(seconds: session.config.bidDurationSeconds),
                  ),
          );
          break;

        case AuctionEventType.bidChanged:
          if (activePlayerId == null || activePlayerId != event.playerId) {
            throw StateError(
              'Evento ${event.id}: cambio prezzo senza chiamata valida.',
            );
          }
          final previousBid = activeBid;
          if (previousBid == null) {
            throw StateError('Evento ${event.id}: offerta iniziale mancante.');
          }
          // Se era già passato come invenduto, durante la nuova chiamata
          // esce temporaneamente dalla lista dedicata.
          unsoldPlayerIds.remove(event.playerId);
          activePlayerId = event.playerId;
          activeBid = BidSnapshot(
            playerId: event.playerId!,
            currentBid: event.amount!,
            updatedAt: event.occurredAt,
            sourceEventId: event.id,
            nominationEventId: previousBid.nominationEventId,
            endsAt: previousBid.endsAt,
            leadingTeamId: event.teamId ?? previousBid.leadingTeamId,
          );
          break;

        case AuctionEventType.playerAssigned:
          final player = players[event.playerId];
          final team = teams[event.teamId];
          if (player == null) {
            throw StateError('Evento ${event.id}: giocatore inesistente.');
          }
          if (team == null) {
            throw StateError('Evento ${event.id}: squadra inesistente.');
          }
          if (activePlayerId != player.id ||
              player.status != DraftStatus.available) {
            throw StateError('Evento ${event.id}: assegnazione non valida.');
          }
          if (event.amount! > team.creditsRemaining) {
            throw StateError('Evento ${event.id}: crediti insufficienti.');
          }

          final draftedPlayer = player.copyWith(
            status: DraftStatus.drafted,
            draftedByTeamId: event.teamId,
            purchasePrice: event.amount,
          );
          players[player.id] = draftedPlayer;

          final rosterWithoutPlayer = team.roster
              .where((item) => item.id != player.id)
              .toList(growable: true);
          rosterWithoutPlayer.add(draftedPlayer);
          teams[team.id] = team.copyWith(
            creditsRemaining: team.creditsRemaining - event.amount!,
            roster: List.unmodifiable(rosterWithoutPlayer),
          );

          unsoldPlayerIds.remove(player.id);
          assignments[player.id] = RosterAssignment(
            eventId: event.id,
            playerId: player.id,
            teamId: team.id,
            price: event.amount!,
            assignedAt: event.occurredAt,
          );
          activePlayerId = null;
          activeBid = null;
          break;

        case AuctionEventType.playerSkipped:
          if (activePlayerId != event.playerId) {
            throw StateError(
              'Evento ${event.id}: salto senza chiamata valida.',
            );
          }
          // Manteniamo una sola occorrenza e spostiamo il giocatore in fondo,
          // così la lista rispetta l'ordine cronologico degli ultimi invenduti.
          unsoldPlayerIds
            ..remove(event.playerId)
            ..add(event.playerId!);
          activePlayerId = null;
          activeBid = null;
          break;

        case AuctionEventType.playerMarkedUnavailable:
          final player = players[event.playerId];
          if (player == null) {
            throw StateError('Evento ${event.id}: giocatore inesistente.');
          }
          if (activePlayerId != player.id ||
              player.status != DraftStatus.available) {
            throw StateError('Evento ${event.id}: indisponibilità non valida.');
          }
          players[player.id] = player.copyWith(
            status: DraftStatus.unavailable,
            draftedByTeamId: null,
            purchasePrice: null,
          );
          assignments.remove(event.playerId);
          unsoldPlayerIds.remove(event.playerId);
          activePlayerId = null;
          activeBid = null;
          break;

        case AuctionEventType.eventReverted:
          // Gestito prima del replay.
          break;
      }
    }

    return AuctionSessionSnapshot(
      playersById: players,
      teamsById: teams,
      assignmentsByPlayerId: assignments,
      revertedEventIds: revertedEventIds,
      unsoldPlayerIds: unsoldPlayerIds,
      activePlayerId: activePlayerId,
      activeBid: activeBid,
      lastReversibleEvent: lastReversibleEvent,
    );
  }
}
