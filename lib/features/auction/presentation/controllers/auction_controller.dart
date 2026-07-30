import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/auction/data/repositories/firestore_auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/auction/domain/services/live_auction_advisor.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

final auctionSessionServiceProvider = Provider<AuctionSessionService>((ref) {
  return const AuctionSessionService();
});

final liveAuctionAdvisorProvider = Provider<LiveAuctionAdvisor>((ref) {
  return LiveAuctionAdvisor(
    sessionService: ref.watch(auctionSessionServiceProvider),
  );
});

final auctionSessionRepositoryProvider = Provider<AuctionSessionRepository>((ref) {
  final ownerUid = ref.watch(currentUserUidProvider);
  if (ownerUid == null) {
    throw StateError('È necessario accedere prima di usare le aste.');
  }

  return FirestoreAuctionSessionRepository(
    ref.watch(firebaseFirestoreProvider),
    ownerUid: ownerUid,
  );
});

final auctionControllerProvider =
    NotifierProvider<AuctionController, AuctionUiState>(AuctionController.new);

enum AuctionRestoreStatus { notStarted, restoring, completed }

enum AuctionPersistenceStatus { idle, pending, synced, failed }

const _unset = Object();

class AuctionUiState {
  final AuctionSession? session;
  final AuctionSessionSnapshot? snapshot;
  final AuctionRecommendation? recommendation;
  final String? myTeamId;
  final String? errorMessage;
  final AuctionRestoreStatus restoreStatus;
  final AuctionPersistenceStatus persistenceStatus;
  final String? persistenceError;
  final DateTime? lastPersistedAt;

  const AuctionUiState({
    this.session,
    this.snapshot,
    this.recommendation,
    this.myTeamId,
    this.errorMessage,
    this.restoreStatus = AuctionRestoreStatus.notStarted,
    this.persistenceStatus = AuctionPersistenceStatus.idle,
    this.persistenceError,
    this.lastPersistedAt,
  });

  bool get isStarted => session != null && snapshot != null && myTeamId != null;
  bool get isRestoring => restoreStatus == AuctionRestoreStatus.restoring;

  AuctionUiState copyWith({
    Object? session = _unset,
    Object? snapshot = _unset,
    Object? recommendation = _unset,
    Object? myTeamId = _unset,
    Object? errorMessage = _unset,
    AuctionRestoreStatus? restoreStatus,
    AuctionPersistenceStatus? persistenceStatus,
    Object? persistenceError = _unset,
    Object? lastPersistedAt = _unset,
  }) {
    return AuctionUiState(
      session: identical(session, _unset)
          ? this.session
          : session as AuctionSession?,
      snapshot: identical(snapshot, _unset)
          ? this.snapshot
          : snapshot as AuctionSessionSnapshot?,
      recommendation: identical(recommendation, _unset)
          ? this.recommendation
          : recommendation as AuctionRecommendation?,
      myTeamId: identical(myTeamId, _unset)
          ? this.myTeamId
          : myTeamId as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      restoreStatus: restoreStatus ?? this.restoreStatus,
      persistenceStatus: persistenceStatus ?? this.persistenceStatus,
      persistenceError: identical(persistenceError, _unset)
          ? this.persistenceError
          : persistenceError as String?,
      lastPersistedAt: identical(lastPersistedAt, _unset)
          ? this.lastPersistedAt
          : lastPersistedAt as DateTime?,
    );
  }
}

class AuctionController extends Notifier<AuctionUiState> {
  final Set<Future<void>> _pendingPersistence = <Future<void>>{};
  int _restoreGeneration = 0;

  AuctionSessionService get _sessions =>
      ref.read(auctionSessionServiceProvider);

  LiveAuctionAdvisor get _advisor => ref.read(liveAuctionAdvisorProvider);

  AuctionSessionRepository get _repository =>
      ref.read(auctionSessionRepositoryProvider);

  @override
  AuctionUiState build() {
    // Rende lo stato dell'asta dipendente dall'account corrente. Al cambio
    // utente Riverpod ricrea uno stato pulito; la Home mostrerà esclusivamente
    // le sessioni associate al nuovo UID.
    final ownerUid = ref.watch(currentUserUidProvider);
    if (ownerUid == null) {
      return const AuctionUiState(
        restoreStatus: AuctionRestoreStatus.completed,
      );
    }

    return const AuctionUiState();
  }

  void startSession({
    required String sessionName,
    required String myTeamId,
    required AuctionConfig config,
    required List<PlayerEntity> players,
    required List<FantasyTeamEntity> teams,
  }) {
    if (players.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Il database giocatori è vuoto.',
        restoreStatus: AuctionRestoreStatus.completed,
      );
      return;
    }
    if (!teams.any((team) => team.id == myTeamId)) {
      state = state.copyWith(
        errorMessage: 'La tua squadra non è presente nella sessione.',
        restoreStatus: AuctionRestoreStatus.completed,
      );
      return;
    }

    final cleanPlayers = players
        .map(
          (player) => player.copyWith(
            status: DraftStatus.available,
            draftedByTeamId: null,
            purchasePrice: null,
          ),
        )
        .toList(growable: false);

    final normalizedTeams = teams
        .map(
          (team) => team.copyWith(
            creditsRemaining: config.initialCredits,
            roster: const [],
          ),
        )
        .toList(growable: false);

    final session = AuctionSession(
      id: 'auction_${DateTime.now().microsecondsSinceEpoch}',
      name: sessionName.trim(),
      config: config,
      createdAt: DateTime.now().toUtc(),
      initialPlayers: cleanPlayers,
      initialTeams: normalizedTeams,
    );

    state = _derive(session, myTeamId: myTeamId).copyWith(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.pending,
      persistenceError: null,
    );

    _schedulePersistence(
      () => _repository.saveSession(session: session, myTeamId: myTeamId),
    );
  }

  void prepareNewSession() {
    _restoreGeneration++;
    state = const AuctionUiState(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.idle,
    );
  }

  Future<bool> openSession({
    required String sessionId,
    required List<PlayerEntity> players,
  }) async {
    final restoreGeneration = ++_restoreGeneration;
    state = const AuctionUiState(
      restoreStatus: AuctionRestoreStatus.restoring,
      persistenceStatus: AuctionPersistenceStatus.idle,
    );

    try {
      final restored = await _repository
          .loadSession(sessionId: sessionId, players: players)
          .timeout(const Duration(seconds: 15));

      if (restoreGeneration != _restoreGeneration) return false;

      if (restored == null) {
        state = const AuctionUiState(
          restoreStatus: AuctionRestoreStatus.completed,
          persistenceStatus: AuctionPersistenceStatus.failed,
          errorMessage: 'L’asta selezionata non esiste più.',
          persistenceError: 'L’asta selezionata non esiste più.',
        );
        return false;
      }

      if (restored.session.status != AuctionSessionStatus.live) {
        state = const AuctionUiState(
          restoreStatus: AuctionRestoreStatus.completed,
          persistenceStatus: AuctionPersistenceStatus.failed,
          errorMessage: 'Questa asta è già conclusa e non può essere ripresa.',
          persistenceError:
              'Questa asta è già conclusa e non può essere ripresa.',
        );
        return false;
      }

      state = _derive(
        restored.session,
        myTeamId: restored.myTeamId,
      ).copyWith(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.synced,
        persistenceError: null,
        errorMessage: null,
        lastPersistedAt: DateTime.now().toUtc(),
      );
      return true;
    } on TimeoutException {
      if (restoreGeneration != _restoreGeneration) return false;
      const message =
          'Il caricamento dell’asta ha impiegato troppo tempo. Riprova.';
      state = const AuctionUiState(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        errorMessage: message,
        persistenceError: message,
      );
      return false;
    } on AuctionSessionPersistenceException catch (error) {
      if (restoreGeneration != _restoreGeneration) return false;
      state = AuctionUiState(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        errorMessage: error.message,
        persistenceError: error.message,
      );
      return false;
    } catch (error) {
      if (restoreGeneration != _restoreGeneration) return false;
      final message = 'Apertura asta non riuscita: $error';
      state = AuctionUiState(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        errorMessage: message,
        persistenceError: message,
      );
      return false;
    }
  }

  Future<void> restoreLatestSession({
    required List<PlayerEntity> players,
  }) async {
    if (state.restoreStatus != AuctionRestoreStatus.notStarted) return;

    final restoreGeneration = ++_restoreGeneration;
    state = state.copyWith(
      restoreStatus: AuctionRestoreStatus.restoring,
      errorMessage: null,
    );

    try {
      final restored = await _repository
          .loadLatestActiveSession(players: players)
          .timeout(const Duration(seconds: 12));

      if (restoreGeneration != _restoreGeneration) return;

      if (restored == null) {
        state = state.copyWith(
          restoreStatus: AuctionRestoreStatus.completed,
          persistenceStatus: AuctionPersistenceStatus.idle,
        );
        return;
      }

      state = _derive(
        restored.session,
        myTeamId: restored.myTeamId,
      ).copyWith(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.synced,
        persistenceError: null,
        lastPersistedAt: DateTime.now().toUtc(),
      );
    } on TimeoutException {
      if (restoreGeneration != _restoreGeneration) return;

      const message =
          'La ricerca delle aste ha impiegato troppo tempo. '
          'Puoi comunque creare una nuova asta.';
      state = state.copyWith(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        persistenceError: message,
        errorMessage: message,
      );
    } on AuctionSessionPersistenceException catch (error) {
      if (restoreGeneration != _restoreGeneration) return;

      state = state.copyWith(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        persistenceError: error.message,
        errorMessage: error.message,
      );
    } catch (error) {
      if (restoreGeneration != _restoreGeneration) return;

      final message = 'Ripristino asta non riuscito: $error';
      state = state.copyWith(
        restoreStatus: AuctionRestoreStatus.completed,
        persistenceStatus: AuctionPersistenceStatus.failed,
        persistenceError: message,
        errorMessage: message,
      );
    }
  }

  void skipRestore() {
    _restoreGeneration++;
    state = state.copyWith(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.idle,
      persistenceError: null,
      errorMessage: null,
    );
  }

  void nominatePlayer(String playerId) {
    _apply((session) => _sessions.nominatePlayer(session, playerId: playerId));
  }

  void setCurrentBid(int bid) {
    if (state.snapshot?.currentBid == bid) return;
    _apply((session) => _sessions.changeCurrentBid(session, bid: bid));
  }

  void incrementBid([int amount = 1]) {
    final current = state.snapshot?.currentBid ?? 0;
    setCurrentBid(current + amount);
  }

  void decrementBid([int amount = 1]) {
    final session = state.session;
    if (session == null) return;
    final current = state.snapshot?.currentBid ?? session.config.minimumBid;
    final next = (current - amount)
        .clamp(session.config.minimumBid, 1 << 30)
        .toInt();
    setCurrentBid(next);
  }

  void assignActivePlayer(String teamId) {
    _apply(
      (session) => _sessions.assignActivePlayer(session, teamId: teamId),
    );
  }

  void skipActivePlayer() {
    _apply((session) => _sessions.skipActivePlayer(session));
  }

  void markActivePlayerUnavailable({String? note}) {
    _apply(
      (session) => _sessions.markActivePlayerUnavailable(
        session,
        note: note,
      ),
    );
  }

  void undoLast() {
    _apply((session) => _sessions.undoLast(session));
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  /// Esce dalla schermata live ma lascia la sessione nello stato `live`, così
  /// verrà ripristinata al prossimo avvio.
  void closeSession() {
    state = AuctionUiState(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: state.persistenceStatus,
      persistenceError: state.persistenceError,
      lastPersistedAt: state.lastPersistedAt,
    );
  }

  /// Marca l'asta come conclusa e torna alla configurazione iniziale.
  void completeSession() {
    final session = state.session;
    if (session == null) return;

    _schedulePersistence(
      () => _repository.updateStatus(
        sessionId: session.id,
        status: AuctionSessionStatus.completed,
      ),
    );

    state = AuctionUiState(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.pending,
    );
  }

  void _apply(AuctionSession Function(AuctionSession session) command) {
    final session = state.session;
    final myTeamId = state.myTeamId;
    if (session == null || myTeamId == null) {
      state = state.copyWith(errorMessage: 'Nessuna asta attiva.');
      return;
    }

    try {
      final updated = command(session);
      if (updated.events.length != session.events.length + 1) {
        throw StateError(
          'Ogni comando d’asta deve produrre esattamente un evento.',
        );
      }

      final newEvent = updated.events.last;
      final previous = state;
      state = _derive(updated, myTeamId: myTeamId).copyWith(
        restoreStatus: previous.restoreStatus,
        persistenceStatus: AuctionPersistenceStatus.pending,
        persistenceError: previous.persistenceError,
        lastPersistedAt: previous.lastPersistedAt,
      );

      _schedulePersistence(
        () => _repository.appendEvent(
          sessionId: updated.id,
          event: newEvent,
        ),
      );
    } on AuctionSessionException catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    } on StateError catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    } on ArgumentError catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    }
  }

  void _schedulePersistence(Future<void> Function() operation) {
    state = state.copyWith(
      persistenceStatus: AuctionPersistenceStatus.pending,
      persistenceError: null,
    );

    late final Future<void> future;
    future = operation()
        .then((_) {
          if (_pendingPersistence.length <= 1) {
            state = state.copyWith(
              persistenceStatus: AuctionPersistenceStatus.synced,
              persistenceError: null,
              lastPersistedAt: DateTime.now().toUtc(),
            );
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          state = state.copyWith(
            persistenceStatus: AuctionPersistenceStatus.failed,
            persistenceError: 'Salvataggio non riuscito: $error',
          );
        })
        .whenComplete(() {
          _pendingPersistence.remove(future);
          if (_pendingPersistence.isEmpty &&
              state.persistenceStatus == AuctionPersistenceStatus.pending) {
            state = state.copyWith(
              persistenceStatus: AuctionPersistenceStatus.synced,
              lastPersistedAt: DateTime.now().toUtc(),
            );
          }
        });

    _pendingPersistence.add(future);
    unawaited(future);
  }

  /// Esposto soprattutto per i test: in produzione la UI resta ottimistica e
  /// non viene bloccata in attesa della rete.
  Future<void> waitForPendingPersistence() async {
    while (_pendingPersistence.isNotEmpty) {
      await Future.wait(_pendingPersistence.toList(growable: false));
    }
  }

  AuctionUiState _derive(
    AuctionSession session, {
    required String myTeamId,
  }) {
    final snapshot = _sessions.snapshot(session);
    AuctionRecommendation? recommendation;

    if (snapshot.activePlayer != null) {
      recommendation = _advisor.evaluate(
        session: session,
        myTeamId: myTeamId,
      );
    }

    return AuctionUiState(
      session: session,
      snapshot: snapshot,
      recommendation: recommendation,
      myTeamId: myTeamId,
    );
  }
}
