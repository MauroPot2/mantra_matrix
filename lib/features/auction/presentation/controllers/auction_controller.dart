import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/auction/data/repositories/firestore_auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_join_preview.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_call_order_service.dart';
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

final auctionCallOrderServiceProvider = Provider((ref) {
  return const AuctionCallOrderService();
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
  final bool isOwner;

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
    this.isOwner = true,
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
    bool? isOwner,
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
      isOwner: isOwner ?? this.isOwner,
    );
  }
}

class AuctionController extends Notifier<AuctionUiState> {
  final Set<Future<void>> _pendingPersistence = <Future<void>>{};
  Future<void> _persistenceTail = Future<void>.value();
  StreamSubscription<List<AuctionEvent>>? _eventSubscription;
  StreamSubscription<AuctionSessionStatus>? _statusSubscription;
  int _restoreGeneration = 0;

  AuctionSessionService get _sessions =>
      ref.read(auctionSessionServiceProvider);

  LiveAuctionAdvisor get _advisor => ref.read(liveAuctionAdvisorProvider);

  AuctionSessionRepository get _repository =>
      ref.read(auctionSessionRepositoryProvider);

  AuctionCallOrderService get _callOrder =>
      ref.read(auctionCallOrderServiceProvider);

  @override
  AuctionUiState build() {
    // Rende lo stato dell'asta dipendente dall'account corrente. Al cambio
    // utente Riverpod ricrea uno stato pulito; la Home mostrerà esclusivamente
    // le sessioni associate al nuovo UID.
    final ownerUid = ref.watch(currentUserUidProvider);
    ref.onDispose(() {
      unawaited(_eventSubscription?.cancel());
      unawaited(_statusSubscription?.cancel());
    });
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
    bool isShared = true,
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

    final ownerUid = ref.read(currentUserUidProvider) ?? 'local-owner';
    final createdAt = DateTime.now().toUtc();
    final session = AuctionSession(
      id: 'auction_${DateTime.now().microsecondsSinceEpoch}',
      name: sessionName.trim(),
      config: config,
      createdAt: createdAt,
      initialPlayers: cleanPlayers,
      initialTeams: normalizedTeams,
      callOrderPlayerIds: _callOrder.build(
        players: cleanPlayers,
        mode: config.callOrderMode,
        seed: Random.secure().nextInt(1 << 31),
      ),
      ownerUid: ownerUid,
      joinCode: isShared ? _generateJoinCode() : '',
      isShared: isShared,
      memberTeamIds: {ownerUid: myTeamId},
    );

    state = _derive(session, myTeamId: myTeamId).copyWith(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.pending,
      persistenceError: null,
    );

    _schedulePersistence(
      () => _repository.saveSession(session: session, myTeamId: myTeamId),
      onSuccess: () => _subscribeToEvents(session.id),
    );
  }

  void prepareNewSession() {
    _restoreGeneration++;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;
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
      _subscribeToEvents(restored.session.id);
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
      _subscribeToEvents(restored.session.id);
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

  Future<AuctionJoinPreview> loadJoinPreview(String joinCode) {
    return _repository
        .loadJoinPreview(joinCode: joinCode)
        .timeout(const Duration(seconds: 12));
  }

  Future<bool> joinSession({
    required String joinCode,
    required String teamId,
    required List<PlayerEntity> players,
  }) async {
    try {
      final sessionId = await _repository
          .joinSession(joinCode: joinCode, teamId: teamId)
          .timeout(const Duration(seconds: 15));
      return openSession(sessionId: sessionId, players: players);
    } on TimeoutException {
      state = state.copyWith(
        errorMessage: 'L’ingresso nell’asta ha impiegato troppo tempo. Riprova.',
      );
      return false;
    } on AuctionSessionPersistenceException catch (error) {
      state = state.copyWith(errorMessage: error.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Ingresso nell’asta non riuscito: $error',
      );
      return false;
    }
  }

  void nominatePlayer(String playerId) {
    if (!_requireOwner()) return;
    _apply((session) => _sessions.nominatePlayer(session, playerId: playerId));
  }

  void setCurrentBid(int bid) {
    if (!_requireOwner()) return;
    if (state.snapshot?.currentBid == bid) return;
    _apply((session) => _sessions.changeCurrentBid(session, bid: bid));
  }

  void placeBid({required String teamId, required int bid}) {
    final myTeamId = state.myTeamId;
    if (!state.isOwner && teamId != myTeamId) {
      state = state.copyWith(
        errorMessage: 'Puoi offrire soltanto per la tua squadra.',
      );
      return;
    }
    _apply(
      (session) => _sessions.placeBid(
        session,
        teamId: teamId,
        bid: bid,
      ),
    );
  }

  void settleExpiredLot() {
    if (!_requireOwner()) return;
    _apply((session) => _sessions.settleExpiredLot(session));
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
    if (!_requireOwner()) return;
    _apply(
      (session) => _sessions.assignActivePlayer(session, teamId: teamId),
    );
  }

  void skipActivePlayer() {
    if (!_requireOwner()) return;
    _apply((session) => _sessions.skipActivePlayer(session));
  }

  void markActivePlayerUnavailable({String? note}) {
    if (!_requireOwner()) return;
    _apply(
      (session) => _sessions.markActivePlayerUnavailable(
        session,
        note: note,
      ),
    );
  }

  void undoLast() {
    if (!_requireOwner()) return;
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
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;
    state = AuctionUiState(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: state.persistenceStatus,
      persistenceError: state.persistenceError,
      lastPersistedAt: state.lastPersistedAt,
    );
  }

  /// Marca l'asta come conclusa e torna alla configurazione iniziale.
  void completeSession() {
    if (!_requireOwner()) return;
    final session = state.session;
    if (session == null) return;

    _schedulePersistence(
      () => _repository.updateStatus(
        sessionId: session.id,
        status: AuctionSessionStatus.completed,
      ),
    );

    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;

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
      final expectedLastEventId = session.events.isEmpty
          ? null
          : session.events.last.id;
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
          expectedLastEventId: expectedLastEventId,
        ),
        onFailure: (error) {
          final current = state.session;
          if (current?.id == session.id &&
              current!.events.isNotEmpty &&
              current.events.last.id == newEvent.id) {
            final message = error is AuctionSessionPersistenceException
                ? error.message
                : 'Salvataggio non riuscito: $error';
            state = _derive(session, myTeamId: myTeamId).copyWith(
              restoreStatus: previous.restoreStatus,
              persistenceStatus: AuctionPersistenceStatus.failed,
              persistenceError: message,
              errorMessage: message,
              lastPersistedAt: previous.lastPersistedAt,
            );
          }
        },
      );
    } on AuctionSessionException catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    } on StateError catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    } on ArgumentError catch (error) {
      state = state.copyWith(errorMessage: error.message.toString());
    }
  }

  void _schedulePersistence(
    Future<void> Function() operation, {
    void Function()? onSuccess,
    void Function(Object error)? onFailure,
  }) {
    state = state.copyWith(
      persistenceStatus: AuctionPersistenceStatus.pending,
      persistenceError: null,
    );

    late final Future<void> future;
    future = _persistenceTail
        .then((_) => operation())
        .then((_) {
          onSuccess?.call();
          if (_pendingPersistence.length <= 1) {
            state = state.copyWith(
              persistenceStatus: AuctionPersistenceStatus.synced,
              persistenceError: null,
              lastPersistedAt: DateTime.now().toUtc(),
            );
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          onFailure?.call(error);
          final message = error is AuctionSessionPersistenceException
              ? error.message
              : 'Salvataggio non riuscito: $error';
          state = state.copyWith(
            persistenceStatus: AuctionPersistenceStatus.failed,
            persistenceError: message,
            errorMessage: message,
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
    _persistenceTail = future;
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

    final currentUid = ref.read(currentUserUidProvider);
    return AuctionUiState(
      session: session,
      snapshot: snapshot,
      recommendation: recommendation,
      myTeamId: myTeamId,
      isOwner: currentUid == null ||
          session.ownerUid.isEmpty ||
          session.ownerUid == currentUid,
    );
  }

  void _subscribeToEvents(String sessionId) {
    unawaited(_eventSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    _eventSubscription = _repository
        .watchEvents(sessionId: sessionId)
        .listen(
      (events) {
        final current = state.session;
        final myTeamId = state.myTeamId;
        if (current == null || current.id != sessionId || myTeamId == null) {
          return;
        }
        if (_sameEvents(events, current.events)) return;

        final previous = state;
        state = _derive(
          current.copyWith(events: events),
          myTeamId: myTeamId,
        ).copyWith(
          restoreStatus: previous.restoreStatus,
          persistenceStatus: AuctionPersistenceStatus.synced,
          persistenceError: null,
          lastPersistedAt: DateTime.now().toUtc(),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        final message = 'Sincronizzazione live non riuscita: $error';
        state = state.copyWith(
          persistenceStatus: AuctionPersistenceStatus.failed,
          persistenceError: message,
          errorMessage: message,
        );
      },
    );
    _statusSubscription = _repository
        .watchStatus(sessionId: sessionId)
        .listen(
      (status) {
        final current = state.session;
        final myTeamId = state.myTeamId;
        if (current == null || current.id != sessionId || myTeamId == null) {
          return;
        }
        if (current.status == status) return;

        final previous = state;
        state = _derive(
          current.copyWith(status: status),
          myTeamId: myTeamId,
        ).copyWith(
          restoreStatus: previous.restoreStatus,
          persistenceStatus: AuctionPersistenceStatus.synced,
          lastPersistedAt: DateTime.now().toUtc(),
          errorMessage: status == AuctionSessionStatus.completed
              ? 'Il creatore ha concluso l’asta.'
              : previous.errorMessage,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        final message = 'Stato sessione non sincronizzato: $error';
        state = state.copyWith(
          persistenceStatus: AuctionPersistenceStatus.failed,
          persistenceError: message,
          errorMessage: message,
        );
      },
    );
  }

  bool _requireOwner() {
    if (state.isOwner) return true;
    state = state.copyWith(
      errorMessage: 'Solo il creatore dell’asta può eseguire questa azione.',
    );
    return false;
  }

  String _generateJoinCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static bool _sameEvents(List<AuctionEvent> a, List<AuctionEvent> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final first = a[index];
      final second = b[index];
      if (first.id != second.id ||
          first.type != second.type ||
          first.occurredAt != second.occurredAt ||
          first.playerId != second.playerId ||
          first.teamId != second.teamId ||
          first.amount != second.amount ||
          first.targetEventId != second.targetEventId) {
        return false;
      }
    }
    return true;
  }
}
