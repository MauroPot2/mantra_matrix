import 'dart:async';

import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_join_preview.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class InMemoryAuctionSessionRepository implements AuctionSessionRepository {
  final Map<String, RestoredAuctionSession> sessions = {};
  final List<AuctionEvent> appendedEvents = [];
  final Map<String, StreamController<List<AuctionEvent>>> _eventControllers =
      {};
  final Map<String, StreamController<AuctionSessionStatus>>
      _statusControllers = {};
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
    required String? expectedLastEventId,
  }) async {
    if (failWrites) throw StateError('write failed');
    final current = sessions[sessionId];
    if (current == null) throw StateError('session not found');
    if (current.session.status != AuctionSessionStatus.live) {
      throw StateError('session completed');
    }
    final actualLastEventId = current.session.events.isEmpty
        ? null
        : current.session.events.last.id;
    if (actualLastEventId != expectedLastEventId) {
      throw const AuctionSessionConflictException();
    }

    appendedEvents.add(event);
    sessions[sessionId] = RestoredAuctionSession(
      session: current.session.copyWith(
        events: [...current.session.events, event],
      ),
      myTeamId: current.myTeamId,
    );
    _eventControllers[sessionId]?.add(
      List<AuctionEvent>.unmodifiable(
        sessions[sessionId]!.session.events,
      ),
    );
  }

  @override
  Stream<List<AuctionEvent>> watchEvents({required String sessionId}) async* {
    yield List<AuctionEvent>.unmodifiable(
      sessions[sessionId]?.session.events ?? const [],
    );
    final controller = _eventControllers.putIfAbsent(
      sessionId,
      () => StreamController<List<AuctionEvent>>.broadcast(),
    );
    yield* controller.stream;
  }

  @override
  Stream<AuctionSessionStatus> watchStatus({required String sessionId}) async* {
    yield sessions[sessionId]?.session.status ?? AuctionSessionStatus.completed;
    final controller = _statusControllers.putIfAbsent(
      sessionId,
      () => StreamController<AuctionSessionStatus>.broadcast(),
    );
    yield* controller.stream;
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
        isOwner: true,
        isShared: session.isShared,
        joinCode: session.joinCode,
        memberCount: session.memberTeamIds.length,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Stream.value(List.unmodifiable(summaries));
  }

  @override
  Future<AuctionJoinPreview> loadJoinPreview({required String joinCode}) async {
    final item = sessions.values.firstWhere(
      (item) => item.session.joinCode == joinCode,
      orElse: () => throw const AuctionSessionPersistenceException(
        'Codice asta non valido.',
      ),
    );
    return AuctionJoinPreview(
      sessionId: item.session.id,
      sessionName: item.session.name,
      joinCode: joinCode,
      teams: item.session.initialTeams,
      claimedTeamIds: item.session.memberTeamIds.values.toSet(),
    );
  }

  @override
  Future<String> joinSession({
    required String joinCode,
    required String teamId,
  }) async {
    final item = sessions.values.firstWhere(
      (item) => item.session.joinCode == joinCode,
      orElse: () => throw const AuctionSessionPersistenceException(
        'Codice asta non valido.',
      ),
    );
    return item.session.id;
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
    _statusControllers[sessionId]?.add(status);
  }
}
