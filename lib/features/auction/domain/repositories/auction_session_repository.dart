import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class RestoredAuctionSession {
  final AuctionSession session;
  final String myTeamId;

  const RestoredAuctionSession({
    required this.session,
    required this.myTeamId,
  });
}

abstract class AuctionSessionRepository {
  /// Crea o aggiorna i metadati della sessione e il relativo snapshot dati.
  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  });

  /// Accoda un singolo evento immutabile alla sessione e aggiorna lo stato
  /// live condiviso nello stesso batch Firestore.
  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
    required AuctionSessionSnapshot snapshotAfterEvent,
  });

  /// Stream realtime del log eventi. Serve a riallineare più dispositivi senza
  /// polling e senza duplicare il motore di riduzione lato cloud.
  Stream<List<AuctionEvent>> watchEvents({required String sessionId});

  /// Stato minimale ad alta frequenza: giocatore attivo, prezzo e clock.
  Stream<AuctionLiveState?> watchLiveState({required String sessionId});

  /// Osserva tutte le aste appartenenti all'utente corrente.
  Stream<List<AuctionSessionSummary>> watchOwnedSessions();

  /// Ripristina una sessione. [players] è usato esclusivamente come ponte per
  /// le sessioni legacy schema <= 5.
  Future<RestoredAuctionSession?> loadSession({
    required String sessionId,
    required List<PlayerEntity> players,
  });

  Future<RestoredAuctionSession?> loadLatestActiveSession({
    required List<PlayerEntity> players,
  });

  Future<void> updateStatus({
    required String sessionId,
    required AuctionSessionStatus status,
  });
}

class AuctionSessionPersistenceException implements Exception {
  final String message;

  const AuctionSessionPersistenceException(this.message);

  @override
  String toString() => message;
}
