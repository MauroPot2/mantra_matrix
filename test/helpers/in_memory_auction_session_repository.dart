import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class InMemoryAuctionSessionRepository implements AuctionSessionRepository {
  final Map<String, RestoredAuctionSession> sessions = {};
  final List<AuctionEvent> appendedEvents = [];
  bool failWrites = false;

  @override
  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  }) async {
    if (failWrites) throw StateError('write failed');
    sessions[session.id] = RestoredAuctionSession(
      session: session,
      myTeamId: myTeamId,
    );
  }

  @override
  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
  }) async {
    if (failWrites) throw StateError('write failed');
    final current = sessions[sessionId];
    if (current == null) throw StateError('session not found');

    appendedEvents.add(event);
    sessions[sessionId] = RestoredAuctionSession(
      session: current.session.copyWith(
        events: [...current.session.events, event],
      ),
      myTeamId: current.myTeamId,
    );
  }

  @override
  Stream<List<AuctionSessionSummary>> watchOwnedSessions() {
    final summaries = sessions.values.map((item) {
      final session = item.session;
      return AuctionSessionSummary(
        id: session.id,
        name: session.name,
        status: session.status,
        createdAt: session.createdAt,
        updatedAt: session.createdAt,
        myTeamId: item.myTeamId,
        teamCount: session.initialTeams.length,
        initialCredits: session.config.initialCredits,
        rosterSize: session.config.rosterSize,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Stream.value(List.unmodifiable(summaries));
  }

  @override
  Future<RestoredAuctionSession?> loadLatestActiveSession({
    required List<PlayerEntity> players,
  }) async {
    final active = sessions.values
        .where(
          (item) => item.session.status == AuctionSessionStatus.live,
        )
        .toList(growable: false)
      ..sort(
        (a, b) => b.session.createdAt.compareTo(a.session.createdAt),
      );
    return active.isEmpty ? null : active.first;
  }

  @override
  Future<RestoredAuctionSession?> loadSession({
    required String sessionId,
    required List<PlayerEntity> players,
  }) async {
    return sessions[sessionId];
  }

  @override
  Future<void> updateStatus({
    required String sessionId,
    required AuctionSessionStatus status,
  }) async {
    if (failWrites) throw StateError('write failed');
    final current = sessions[sessionId];
    if (current == null) throw StateError('session not found');
    sessions[sessionId] = RestoredAuctionSession(
      session: current.session.copyWith(status: status),
      myTeamId: current.myTeamId,
    );
  }
}
