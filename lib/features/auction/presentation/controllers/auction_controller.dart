import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/auction/data/repositories/firestore_auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_event_merge_policy.dart';
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

final auctionInstanceIdProvider = Provider<String>((ref) {
  final nonce = Object();
  return 'instance_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${identityHashCode(nonce).toRadixString(36)}';
});

final auctionSessionRepositoryProvider = Provider<AuctionSessionRepository>((ref) {
  final ownerUid = ref.watch(currentUserUidProvider);
  if (ownerUid == null) {
    throw StateError('È necessario accedere prima di usare le aste.');
  }

  return FirestoreAuctionSessionRepository(
    ref.watch(firebaseFirestoreProvider),
    ownerUid: ownerUid,
    instanceId: ref.watch(auctionInstanceIdProvider),
  );
});

final auctionLiveStateProvider = StreamProvider.autoDispose
    .family<AuctionLiveState?, String>((ref, sessionId) {
  final repository = ref.watch(auctionSessionRepositoryProvider);
  return repository.watchLiveState(sessionId: sessionId);
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
  static const _mergePolicy = AuctionEventMergePolicy();

  final Set<Future<void>> _pendingPersistence = <Future<void>>{};
  final List<String> _pendingEventIds = <String>[];
  StreamSubscription<List<AuctionEvent>>? _eventsSubscription;
  StreamSubscription<AuctionLiveState?>? _liveStateSubscription;
  Future<void> _persistenceTail = Future<void>.value();
  AuctionLiveState? _latestLiveState;
  bool _liveStateResolved = false;
  int _restoreGeneration = 0;
  String? _subscribedSessionId;

  AuctionSessionService get _sessions =>
      ref.read(auctionSessionServiceProvider);

  LiveAuctionAdvisor get _advisor => ref.read(liveAuctionAdvisorProvider);

  AuctionSessionRepository get _repository =>
      ref.read(auctionSessionRepositoryProvider);

  @override
  AuctionUiState build() {
    ref.onDispose(() {
      unawaited(_eventsSubscription?.cancel());
      unawaited(_liveStateSubscription?.cancel());
    });

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
        errorMessage: 'Il dataset giocatori è vuoto.',
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

    _resetRealtimeTracking();

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

    final initialSave = _schedulePersistence(
      () => _repository.saveSession(session: session, myTeamId: myTeamId),
    );
    unawaited(_subscribeAfterInitialSave(session.id, initialSave));
  }

  void prepareNewSession() {
    _restoreGeneration++;
    _cancelEventSubscription();
    _resetRealtimeTracking();
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
    _cancelEventSubscription();
    _resetRealtimeTracking();
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
    _cancelEventSubscription();
    _resetRealtimeTracking();
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
    _cancelEventSubscription();
    _resetRealtimeTracking();
    state = state.copyWith(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: AuctionPersistenceStatus.idle,
      persistenceError: null,
      errorMessage: null,
    );
  }

  Future<bool> claimControl() async {
    final session = state.session;
    if (session == null) return false;

    try {
      await _repository.claimControl(sessionId: session.id);
      return true;
    } on AuctionSessionPersistenceException catch (error) {
      state = state.copyWith(errorMessage: error.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Acquisizione controllo non riuscita: $error',
      );
      return false;
    }
  }

  void nominatePlayer(String playerId) {
    _apply((session) => _sessions.nominatePlayer(session, playerId: playerId));
  }

  void setCurrentBid(int bid) {
    final current = state.snapshot?.currentBid;
    if (current == bid) return;

    if (current != null && bid > current) {
      _apply((session) => _sessions.raiseCurrentBid(session, bid: bid));
      return;
    }

    _apply((session) => _sessions.changeCurrentBid(session, bid: bid));
  }

  void incrementBid([int amount = 1]) {
    if (amount <= 0) return;
    final session = state.session;
    if (session == null) return;
    final current = state.snapshot?.currentBid ?? session.config.minimumBid;
    setCurrentBid(current + amount);
  }

  void decrementBid([int amount = 1]) {
    if (amount <= 0) return;
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

  void closeSession() {
    _cancelEventSubscription();
    _resetRealtimeTracking();
    state = AuctionUiState(
      restoreStatus: AuctionRestoreStatus.completed,
      persistenceStatus: state.persistenceStatus,
      persistenceError: state.persistenceError,
      lastPersistedAt: state.lastPersistedAt,
    );
  }

  void completeSession() {
    final session = state.session;
    if (session == null) return;
    if (!_ensureControllerForMutation()) return;

    _schedulePersistence(
      () => _repository.updateStatus(
        sessionId: session.id,
        status: AuctionSessionStatus.completed,
      ),
      onSuccess: () {
        if (state.session?.id != session.id) return;
        _cancelEventSubscription();
        _resetRealtimeTracking();
        state = AuctionUiState(
          restoreStatus: AuctionRestoreStatus.completed,
          persistenceStatus: AuctionPersistenceStatus.synced,
          lastPersistedAt: DateTime.now().toUtc(),
        );
      },
    );
  }

  void _apply(AuctionSession Function(AuctionSession session) command) {
    final session = state.session;
    final myTeamId = state.myTeamId;
    if (session == null || myTeamId == null) {
      state = state.copyWith(errorMessage: 'Nessuna asta attiva.');
      return;
    }
    if (!_ensureControllerForMutation()) return;

    try {
      final updated = command(session);
      if (updated.events.length != session.events.length + 1) {
        throw StateError(
          'Ogni comando d’asta deve produrre esattamente un evento.',
        );
      }

      final newEvent = updated.events.last;
      final previous = state;
      _pendingEventIds.add(newEvent.id);
      state = _derive(updated, myTeamId: myTeamId).copyWith(
        restoreStatus: previous.restoreStatus,
        persistenceStatus: AuctionPersistenceStatus.pending,
        persistenceError: previous.persistenceError,
        lastPersistedAt: previous.lastPersistedAt,
      );
      final snapshotAfterEvent = state.snapshot!;

      _schedulePersistence(
        () => _repository.appendEvent(
          sessionId: updated.id,
          event: newEvent,
          snapshotAfterEvent: snapshotAfterEvent,
        ),
        onFailure: (_) {
          _pendingEventIds.remove(newEvent.id);
          unawaited(_recoverAuthoritativeSession(updated.id));
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

  bool _ensureControllerForMutation() {
    if (!_liveStateResolved) {
      state = state.copyWith(
        errorMessage:
            'Controllo asta in allineamento. Riprova tra un istante.',
      );
      return false;
    }

    final live = _latestLiveState;
    if (live == null) {
      state = state.copyWith(
        errorMessage: 'Stato realtime non disponibile. Riprova.',
      );
      return false;
    }

    if (!live.isControlledBy(_repository.instanceId)) {
      state = state.copyWith(
        errorMessage:
            'Questo dispositivo è in modalità viewer. Prendi il controllo prima di modificare l’asta.',
      );
      return false;
    }

    return true;
  }

  Future<void> _recoverAuthoritativeSession(String sessionId) async {
    try {
      await _persistenceTail;
      if (state.session?.id != sessionId) return;
      final restored = await _repository.loadSession(
        sessionId: sessionId,
        players: const <PlayerEntity>[],
      );
      if (restored == null || state.session?.id != sessionId) return;

      _pendingEventIds.clear();
      final previous = state;
      state = _derive(
        restored.session,
        myTeamId: restored.myTeamId,
      ).copyWith(
        restoreStatus: previous.restoreStatus,
        persistenceStatus: AuctionPersistenceStatus.synced,
        persistenceError: null,
        errorMessage: previous.persistenceError,
        lastPersistedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      // Manteniamo il messaggio di errore della persistenza originale.
    }
  }

  Future<void> _subscribeAfterInitialSave(
    String sessionId,
    Future<void> initialSave,
  ) async {
    await initialSave;
    if (state.session?.id != sessionId ||
        state.persistenceStatus == AuctionPersistenceStatus.failed) {
      return;
    }
    _subscribeToEvents(sessionId);
  }

  void _subscribeToEvents(String sessionId) {
    if (_subscribedSessionId == sessionId && _eventsSubscription != null) {
      return;
    }

    _cancelEventSubscription();
    _subscribedSessionId = sessionId;
    _eventsSubscription = _repository
        .watchEvents(sessionId: sessionId)
        .listen(
          (events) => _mergeRemoteEvents(sessionId, events),
          onError: (Object error, StackTrace stackTrace) {
            if (state.session?.id != sessionId) return;
            state = state.copyWith(
              errorMessage: 'Sincronizzazione realtime interrotta: $error',
            );
          },
        );
    _liveStateSubscription = _repository
        .watchLiveState(sessionId: sessionId)
        .listen(
          (liveState) {
            if (state.session?.id != sessionId) return;
            _latestLiveState = liveState;
            _liveStateResolved = true;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (state.session?.id != sessionId) return;
            _latestLiveState = null;
            _liveStateResolved = false;
            state = state.copyWith(
              errorMessage: 'Controllo realtime interrotto: $error',
            );
          },
        );
  }

  void _mergeRemoteEvents(String sessionId, List<AuctionEvent> remoteEvents) {
    final session = state.session;
    final myTeamId = state.myTeamId;
    if (session == null || myTeamId == null || session.id != sessionId) return;

    final merge = _mergePolicy.merge(
      localEvents: session.events,
      remoteEvents: remoteEvents,
      pendingEventIds: _pendingEventIds,
    );
    _pendingEventIds
      ..clear()
      ..addAll(merge.pendingEventIds);
    final merged = merge.events;

    if (_sameEventSequence(session.events, merged)) return;

    final previous = state;
    try {
      state = _derive(
        session.copyWith(events: merged),
        myTeamId: myTeamId,
      ).copyWith(
        restoreStatus: previous.restoreStatus,
        persistenceStatus: previous.persistenceStatus,
        persistenceError: previous.persistenceError,
        lastPersistedAt: previous.lastPersistedAt,
      );
    } on StateError catch (error) {
      state = previous.copyWith(
        errorMessage: 'Conflitto di sincronizzazione: ${error.message}',
      );
    }
  }

  bool _sameEventSequence(List<AuctionEvent> a, List<AuctionEvent> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id ||
          a[index].serverRevision != b[index].serverRevision) {
        return false;
      }
    }
    return true;
  }

  void _cancelEventSubscription() {
    final eventSubscription = _eventsSubscription;
    final liveSubscription = _liveStateSubscription;
    _eventsSubscription = null;
    _liveStateSubscription = null;
    _subscribedSessionId = null;
    _latestLiveState = null;
    _liveStateResolved = false;
    if (eventSubscription != null) unawaited(eventSubscription.cancel());
    if (liveSubscription != null) unawaited(liveSubscription.cancel());
  }

  void _resetRealtimeTracking() {
    _pendingEventIds.clear();
    _latestLiveState = null;
    _liveStateResolved = false;
  }

  Future<void> _schedulePersistence(
    Future<void> Function() operation, {
    void Function()? onSuccess,
    void Function(Object error)? onFailure,
  }) {
    state = state.copyWith(
      persistenceStatus: AuctionPersistenceStatus.pending,
      persistenceError: null,
    );

    final queued = _persistenceTail.then((_) => operation());
    _persistenceTail = queued.catchError((Object _, StackTrace _) {});

    late final Future<void> tracked;
    tracked = queued
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
          state = state.copyWith(
            persistenceStatus: AuctionPersistenceStatus.failed,
            persistenceError: 'Salvataggio non riuscito: $error',
          );
          onFailure?.call(error);
        })
        .whenComplete(() {
          _pendingPersistence.remove(tracked);
          if (_pendingPersistence.isEmpty &&
              state.persistenceStatus == AuctionPersistenceStatus.pending) {
            state = state.copyWith(
              persistenceStatus: AuctionPersistenceStatus.synced,
              lastPersistedAt: DateTime.now().toUtc(),
            );
          }
        });

    _pendingPersistence.add(tracked);
    unawaited(tracked);
    return tracked;
  }

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
