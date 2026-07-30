import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
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
  /// Crea o aggiorna i metadati della sessione.
  /// Deve essere idempotente: richiamarlo con lo stesso ID non deve duplicare dati.
  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  });

  /// Accoda un singolo evento immutabile alla sessione.
  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
  });


  /// Osserva tutte le aste appartenenti all'utente corrente.
  /// La query concreta deve essere vincolata all'owner UID, così da essere
  /// compatibile con le regole Firestore (le rules non filtrano i risultati).
  Stream<List<AuctionSessionSummary>> watchOwnedSessions();

  /// Ripristina una sessione usando il catalogo giocatori già caricato.
  Future<RestoredAuctionSession?> loadSession({
    required String sessionId,
    required List<PlayerEntity> players,
  });

  /// Recupera la sessione live più recente, se presente.
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
