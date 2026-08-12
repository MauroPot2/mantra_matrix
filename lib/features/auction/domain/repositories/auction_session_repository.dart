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
  /// Identificatore effimero dell'istanza app corrente. Serve a garantire che
  /// una sola istanza alla volta produca mutazioni dell'asta.
  String get instanceId;

  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  });

  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
    required AuctionSessionSnapshot snapshotAfterEvent,
  });

  Stream<List<AuctionEvent>> watchEvents({required String sessionId});

  Stream<AuctionLiveState?> watchLiveState({required String sessionId});

  /// Trasferisce esplicitamente il controllo dell'asta all'istanza app corrente.
  Future<void> claimControl({required String sessionId});

  Stream<List<AuctionSessionSummary>> watchOwnedSessions();

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
