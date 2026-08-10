import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_reducer.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionSessionException implements Exception {
  final String message;

  const AuctionSessionException(this.message);

  @override
  String toString() => 'AuctionSessionException: $message';
}

class AuctionSessionService {
  final AuctionSessionReducer reducer;

  const AuctionSessionService({
    this.reducer = const AuctionSessionReducer(),
  });

  AuctionSessionSnapshot snapshot(AuctionSession session) {
    return reducer.reduce(session);
  }

  AuctionSession nominatePlayer(
    AuctionSession session, {
    required String playerId,
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final player = state.playersById[playerId];

    if (player == null) {
      throw AuctionSessionException('Giocatore $playerId inesistente.');
    }
    if (player.status != DraftStatus.available) {
      throw AuctionSessionException(
        'Il giocatore ${player.name} non è disponibile.',
      );
    }
    if (state.activePlayerId != null) {
      throw const AuctionSessionException(
        'Chiudi o annulla la chiamata corrente prima di chiamarne un’altra.',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.playerNominated(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: playerId,
        startingBid: session.config.minimumBid,
      ),
    );
  }

  /// Corregge manualmente il prezzo senza considerarlo un rilancio.
  AuctionSession changeCurrentBid(
    AuctionSession session, {
    required int bid,
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final activePlayerId = state.activePlayerId;

    if (activePlayerId == null) {
      throw const AuctionSessionException(
        'Nessun giocatore attualmente chiamato.',
      );
    }
    if (bid < session.config.minimumBid) {
      throw AuctionSessionException(
        'L’offerta non può essere inferiore a ${session.config.minimumBid}.',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.bidChanged(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: activePlayerId,
        bid: bid,
      ),
    );
  }

  /// Registra un vero rilancio verso l'alto. L'estensione temporale è una
  /// proprietà dell'evento, così tutti i dispositivi applicano esattamente lo
  /// stesso +N secondi senza dipendere dalla propria latenza.
  AuctionSession raiseCurrentBid(
    AuctionSession session, {
    required int bid,
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final activePlayerId = state.activePlayerId;

    if (activePlayerId == null) {
      throw const AuctionSessionException(
        'Nessun giocatore attualmente chiamato.',
      );
    }
    if (bid <= state.currentBid) {
      throw AuctionSessionException(
        'Un rilancio deve superare l’offerta corrente (${state.currentBid}).',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.bidRaised(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: activePlayerId,
        bid: bid,
        clockExtensionSeconds: session.config.bidExtensionSeconds,
      ),
    );
  }

  AuctionSession assignActivePlayer(
    AuctionSession session, {
    required String teamId,
    int? price,
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final activePlayer = state.activePlayer;
    final team = state.teamsById[teamId];

    if (activePlayer == null) {
      throw const AuctionSessionException(
        'Nessun giocatore attualmente chiamato.',
      );
    }
    if (team == null) {
      throw AuctionSessionException('Squadra $teamId inesistente.');
    }
    if (team.slotsRemaining(session.config) <= 0) {
      throw AuctionSessionException(
        'La rosa di ${team.name} è già completa.',
      );
    }

    final finalPrice = price ?? state.currentBid;
    if (finalPrice < session.config.minimumBid) {
      throw AuctionSessionException(
        'Il prezzo non può essere inferiore a ${session.config.minimumBid}.',
      );
    }

    final ceiling = team.maxAffordableBid(session.config);
    if (finalPrice > ceiling) {
      throw AuctionSessionException(
        'Prezzo non sostenibile: massimo $ceiling crediti per completare la rosa.',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.playerAssigned(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: activePlayer.id,
        teamId: teamId,
        price: finalPrice,
      ),
    );
  }

  AuctionSession skipActivePlayer(
    AuctionSession session, {
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final activePlayerId = state.activePlayerId;

    if (activePlayerId == null) {
      throw const AuctionSessionException(
        'Nessun giocatore attualmente chiamato.',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.playerSkipped(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: activePlayerId,
      ),
    );
  }

  AuctionSession markActivePlayerUnavailable(
    AuctionSession session, {
    String? note,
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final activePlayerId = state.activePlayerId;

    if (activePlayerId == null) {
      throw const AuctionSessionException(
        'Nessun giocatore attualmente chiamato.',
      );
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.playerMarkedUnavailable(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        playerId: activePlayerId,
        note: note,
      ),
    );
  }

  /// Annulla l'ultima azione effettiva aggiungendo un evento compensativo.
  /// L'evento originale resta nel log per audit e sincronizzazione.
  AuctionSession undoLast(
    AuctionSession session, {
    String? eventId,
    DateTime? occurredAt,
  }) {
    _ensureLive(session);
    final state = snapshot(session);
    final target = state.lastReversibleEvent;

    if (target == null) {
      throw const AuctionSessionException('Non ci sono azioni da annullare.');
    }

    final timestamp = occurredAt ?? DateTime.now().toUtc();
    return _append(
      session,
      AuctionEvent.eventReverted(
        id: eventId ?? _eventId(session, timestamp),
        occurredAt: timestamp,
        targetEventId: target.id,
      ),
    );
  }

  AuctionSession _append(AuctionSession session, AuctionEvent event) {
    if (session.events.any((existing) => existing.id == event.id)) {
      throw AuctionSessionException('Evento duplicato: ${event.id}.');
    }
    return session.copyWith(
      events: List.unmodifiable([...session.events, event]),
    );
  }

  void _ensureLive(AuctionSession session) {
    if (session.status != AuctionSessionStatus.live) {
      throw const AuctionSessionException('La sessione non è attiva.');
    }
  }

  String _eventId(AuctionSession session, DateTime occurredAt) {
    return '${occurredAt.microsecondsSinceEpoch}_${session.events.length}';
  }
}
