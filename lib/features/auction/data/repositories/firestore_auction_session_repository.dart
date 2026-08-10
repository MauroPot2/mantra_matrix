import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class FirestoreAuctionSessionRepository implements AuctionSessionRepository {
  static const _schemaVersion = 7;
  static const _sessionsCollection = 'auction_sessions';
  static const _eventsCollection = 'events';
  static const _playersCollection = 'players';
  static const _liveCollection = 'live';
  static const _liveDocument = 'current';
  static const _snapshotReady = 'ready';
  static const _snapshotWriting = 'writing';
  static const _batchSize = 400;

  final FirebaseFirestore _firestore;
  final String _ownerUid;

  @override
  final String instanceId;

  const FirestoreAuctionSessionRepository(
    this._firestore, {
    required String ownerUid,
    required this.instanceId,
  }) : _ownerUid = ownerUid;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(_sessionsCollection);

  @override
  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  }) async {
    final sessionRef = _sessions.doc(session.id);
    final playerIds = session.initialPlayers
        .map((player) => player.id)
        .toList(growable: false);

    final data = <String, dynamic>{
      'schema_version': _schemaVersion,
      'owner_uid': _ownerUid,
      'member_uids': [_ownerUid],
      'name': session.name,
      'status': session.status.name,
      'my_team_id': myTeamId,
      'created_at': Timestamp.fromDate(session.createdAt.toUtc()),
      'updated_at': FieldValue.serverTimestamp(),
      'config': session.config.toJson(),
      'initial_player_ids': playerIds,
      'player_count': playerIds.length,
      'player_snapshot_status': _snapshotWriting,
      'initial_teams': session.initialTeams
          .map(_teamToJson)
          .toList(growable: false),
    };

    await sessionRef.set(data, SetOptions(merge: true));
    await sessionRef.collection(_liveCollection).doc(_liveDocument).set({
      'schema_version': _schemaVersion,
      'phase': AuctionClockPhase.idle.name,
      'active_player_id': null,
      'current_bid': 0,
      'started_at': null,
      'extension_seconds': 0,
      'revision': 0,
      'controller_instance_id': instanceId,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _savePlayerSnapshot(sessionRef, session.initialPlayers);
    await sessionRef.set(
      {
        'schema_version': _schemaVersion,
        'player_snapshot_status': _snapshotReady,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _savePlayerSnapshot(
    DocumentReference<Map<String, dynamic>> sessionRef,
    List<PlayerEntity> players,
  ) async {
    for (var start = 0; start < players.length; start += _batchSize) {
      final end = (start + _batchSize < players.length)
          ? start + _batchSize
          : players.length;
      final batch = _firestore.batch();

      for (final player in players.sublist(start, end)) {
        final playerRef =
            sessionRef.collection(_playersCollection).doc(player.id);
        batch.set(playerRef, {
          ...PlayerModel.fromEntity(player).toJson(),
          'schema_version': _schemaVersion,
        });
      }

      await batch.commit();
    }
  }

  @override
  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
    required AuctionSessionSnapshot snapshotAfterEvent,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final eventRef = sessionRef.collection(_eventsCollection).doc(event.id);
    final liveRef = sessionRef.collection(_liveCollection).doc(_liveDocument);

    await _firestore.runTransaction((transaction) async {
      final liveSnapshot = await transaction.get(liveRef);
      final existingEvent = await transaction.get(eventRef);

      if (existingEvent.exists) return;

      final liveData = liveSnapshot.data();
      if (!liveSnapshot.exists || liveData == null) {
        throw const AuctionSessionPersistenceException(
          'Stato realtime dell’asta non disponibile.',
        );
      }

      if (liveData['controller_instance_id']?.toString() != instanceId) {
        throw const AuctionSessionPersistenceException(
          'Questo dispositivo è in modalità viewer. Prendi il controllo prima di modificare l’asta.',
        );
      }

      _validateLiveTransition(liveData, event);

      final nextRevision =
          ((liveData['revision'] as num?)?.toInt() ?? 0) + 1;

      transaction.set(eventRef, {
        ...event.toJson(),
        'schema_version': _schemaVersion,
        'server_revision': nextRevision,
        'created_by_uid': _ownerUid,
        'controller_instance_id': instanceId,
        'server_occurred_at': FieldValue.serverTimestamp(),
      });
      transaction.set(
        sessionRef,
        {
          'updated_at': FieldValue.serverTimestamp(),
          'last_event_id': event.id,
        },
        SetOptions(merge: true),
      );
      transaction.set(
        liveRef,
        _livePatchFor(
          event,
          snapshotAfterEvent,
          nextRevision: nextRevision,
        ),
        SetOptions(merge: true),
      );
    });
  }

  void _validateLiveTransition(
    Map<String, dynamic> liveData,
    AuctionEvent event,
  ) {
    final activePlayerId = liveData['active_player_id']?.toString();
    final currentBid = (liveData['current_bid'] as num?)?.toInt() ?? 0;
    final phase = liveData['phase']?.toString();

    switch (event.type) {
      case AuctionEventType.playerNominated:
        if (phase != AuctionClockPhase.idle.name || activePlayerId != null) {
          throw const AuctionSessionPersistenceException(
            'Esiste già una chiamata attiva su un altro dispositivo.',
          );
        }
        break;

      case AuctionEventType.bidRaised:
        if (activePlayerId != event.playerId) {
          throw const AuctionSessionPersistenceException(
            'La chiamata attiva è cambiata su un altro dispositivo.',
          );
        }
        final bid = event.amount ?? 0;
        if (bid <= currentBid) {
          throw AuctionSessionPersistenceException(
            'Rilancio superato: l’offerta live è già $currentBid crediti.',
          );
        }
        break;

      case AuctionEventType.bidChanged:
      case AuctionEventType.playerAssigned:
      case AuctionEventType.playerSkipped:
      case AuctionEventType.playerMarkedUnavailable:
        if (activePlayerId != event.playerId) {
          throw const AuctionSessionPersistenceException(
            'La chiamata attiva è cambiata su un altro dispositivo.',
          );
        }
        break;

      case AuctionEventType.eventReverted:
        break;
    }
  }

  Map<String, dynamic> _livePatchFor(
    AuctionEvent event,
    AuctionSessionSnapshot snapshot, {
    required int nextRevision,
  }) {
    final common = <String, dynamic>{
      'schema_version': _schemaVersion,
      'revision': nextRevision,
      'controller_instance_id': instanceId,
      'updated_at': FieldValue.serverTimestamp(),
    };

    switch (event.type) {
      case AuctionEventType.playerNominated:
        return {
          ...common,
          'phase': AuctionClockPhase.running.name,
          'active_player_id': snapshot.activePlayerId,
          'current_bid': snapshot.currentBid,
          'started_at': FieldValue.serverTimestamp(),
          'extension_seconds': 0,
        };

      case AuctionEventType.bidRaised:
        return {
          ...common,
          'phase': AuctionClockPhase.running.name,
          'active_player_id': snapshot.activePlayerId,
          'current_bid': snapshot.currentBid,
          'extension_seconds': FieldValue.increment(
            event.clockExtensionSeconds ?? 0,
          ),
        };

      case AuctionEventType.bidChanged:
        return {
          ...common,
          'phase': AuctionClockPhase.running.name,
          'active_player_id': snapshot.activePlayerId,
          'current_bid': snapshot.currentBid,
        };

      case AuctionEventType.playerAssigned:
      case AuctionEventType.playerSkipped:
      case AuctionEventType.playerMarkedUnavailable:
        return {
          ...common,
          'phase': AuctionClockPhase.idle.name,
          'active_player_id': null,
          'current_bid': 0,
          'started_at': null,
          'extension_seconds': 0,
        };

      case AuctionEventType.eventReverted:
        if (snapshot.activePlayerId == null) {
          return {
            ...common,
            'phase': AuctionClockPhase.idle.name,
            'active_player_id': null,
            'current_bid': 0,
            'started_at': null,
            'extension_seconds': 0,
          };
        }
        return {
          ...common,
          'phase': AuctionClockPhase.running.name,
          'active_player_id': snapshot.activePlayerId,
          'current_bid': snapshot.currentBid,
          'started_at': FieldValue.serverTimestamp(),
          'extension_seconds': 0,
        };
    }
  }

  @override
  Stream<List<AuctionEvent>> watchEvents({required String sessionId}) {
    return _sessions
        .doc(sessionId)
        .collection(_eventsCollection)
        .snapshots()
        .map((snapshot) {
          final events = snapshot.docs.map((document) {
            final raw = Map<String, dynamic>.from(document.data());
            raw['id'] ??= document.id;
            return AuctionEvent.fromJson(raw);
          }).toList(growable: false)
            ..sort(_compareEvents);
          return List<AuctionEvent>.unmodifiable(events);
        });
  }

  @override
  Stream<AuctionLiveState?> watchLiveState({required String sessionId}) {
    return _sessions
        .doc(sessionId)
        .collection(_liveCollection)
        .doc(_liveDocument)
        .snapshots()
        .map((document) {
          final data = document.data();
          if (!document.exists || data == null) return null;
          return _liveStateFromJson(data);
        });
  }

  @override
  Future<void> claimControl({required String sessionId}) async {
    final liveRef = _sessions
        .doc(sessionId)
        .collection(_liveCollection)
        .doc(_liveDocument);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(liveRef);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const AuctionSessionPersistenceException(
          'Impossibile acquisire il controllo: stato realtime assente.',
        );
      }

      final nextRevision = ((data['revision'] as num?)?.toInt() ?? 0) + 1;
      transaction.set(
        liveRef,
        {
          'controller_instance_id': instanceId,
          'revision': nextRevision,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  AuctionLiveState _liveStateFromJson(Map<String, dynamic> data) {
    final phaseName = data['phase']?.toString();
    final phase = AuctionClockPhase.values.firstWhere(
      (item) => item.name == phaseName,
      orElse: () => AuctionClockPhase.idle,
    );

    return AuctionLiveState(
      phase: phase,
      activePlayerId: data['active_player_id']?.toString(),
      currentBid: (data['current_bid'] as num?)?.toInt() ?? 0,
      startedAt: _readNullableDate(data['started_at']),
      extensionSeconds: (data['extension_seconds'] as num?)?.toInt() ?? 0,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      updatedAt: _readNullableDate(data['updated_at']),
      controllerInstanceId: data['controller_instance_id']?.toString(),
    );
  }

  @override
  Stream<List<AuctionSessionSummary>> watchOwnedSessions() {
    return _sessions
        .where('owner_uid', isEqualTo: _ownerUid)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs
              .map(_summaryFromDocument)
              .whereType<AuctionSessionSummary>()
              .toList(growable: false)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return List<AuctionSessionSummary>.unmodifiable(sessions);
        });
  }

  @override
  Future<RestoredAuctionSession?> loadSession({
    required String sessionId,
    required List<PlayerEntity> players,
  }) async {
    final document = await _sessions.doc(sessionId).get();
    if (!document.exists) return null;

    return _restoreAndMigrate(document, legacyPlayers: players);
  }

  @override
  Future<RestoredAuctionSession?> loadLatestActiveSession({
    required List<PlayerEntity> players,
  }) async {
    final query = await _sessions
        .where('owner_uid', isEqualTo: _ownerUid)
        .limit(50)
        .get();

    final liveDocuments = query.docs
        .where(
          (document) =>
              document.data()['status'] == AuctionSessionStatus.live.name,
        )
        .toList(growable: false);

    if (liveDocuments.isEmpty) return null;

    final documents = liveDocuments
      ..sort((a, b) {
        final aDate = _readDate(a.data()['created_at']);
        final bDate = _readDate(b.data()['created_at']);
        return bDate.compareTo(aDate);
      });

    return _restoreAndMigrate(documents.first, legacyPlayers: players);
  }

  Future<RestoredAuctionSession> _restoreAndMigrate(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<PlayerEntity> legacyPlayers,
  }) async {
    final data = document.data();
    final schemaVersion = (data?['schema_version'] as num?)?.toInt() ?? 0;
    final restored = await _restoreFromDocument(
      document,
      legacyPlayers: legacyPlayers,
    );

    if (schemaVersion < _schemaVersion) {
      await saveSession(
        session: restored.session,
        myTeamId: restored.myTeamId,
      );
    }

    return restored;
  }

  @override
  Future<void> updateStatus({
    required String sessionId,
    required AuctionSessionStatus status,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final liveRef = sessionRef.collection(_liveCollection).doc(_liveDocument);

    await _firestore.runTransaction((transaction) async {
      final liveSnapshot = await transaction.get(liveRef);
      final liveData = liveSnapshot.data();
      if (!liveSnapshot.exists || liveData == null) {
        throw const AuctionSessionPersistenceException(
          'Stato realtime dell’asta non disponibile.',
        );
      }
      if (liveData['controller_instance_id']?.toString() != instanceId) {
        throw const AuctionSessionPersistenceException(
          'Solo il dispositivo controller può concludere l’asta.',
        );
      }

      transaction.set(
        sessionRef,
        {
          'status': status.name,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (status != AuctionSessionStatus.live) {
        final nextRevision =
            ((liveData['revision'] as num?)?.toInt() ?? 0) + 1;
        transaction.set(
          liveRef,
          {
            'phase': AuctionClockPhase.idle.name,
            'active_player_id': null,
            'current_bid': 0,
            'started_at': null,
            'extension_seconds': 0,
            'revision': nextRevision,
            'controller_instance_id': instanceId,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  AuctionSessionSummary? _summaryFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data['owner_uid']?.toString() != _ownerUid) return null;

    final configRaw = data['config'];
    final config = configRaw is Map
        ? Map<String, dynamic>.from(configRaw)
        : const <String, dynamic>{};
    final initialTeams = data['initial_teams'];
    final createdAt = _readDate(data['created_at']);
    final updatedAt = _readNullableDate(data['updated_at']) ?? createdAt;

    return AuctionSessionSummary(
      id: document.id,
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : 'Asta Matrix',
      status: _readStatus(data['status']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      myTeamId: data['my_team_id']?.toString() ?? '',
      teamCount: initialTeams is List ? initialTeams.length : 0,
      initialCredits: (config['initial_credits'] as num?)?.toInt() ?? 0,
      rosterSize: (config['roster_size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<RestoredAuctionSession> _restoreFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<PlayerEntity> legacyPlayers,
  }) async {
    final data = document.data();
    if (data == null) {
      throw const AuctionSessionPersistenceException(
        'La sessione non contiene dati validi.',
      );
    }

    final ownerUid = data['owner_uid']?.toString();
    if (ownerUid != _ownerUid) {
      throw const AuctionSessionPersistenceException(
        'Questa asta appartiene a un altro account.',
      );
    }

    final schemaVersion = (data['schema_version'] as num?)?.toInt() ?? 0;
    if (schemaVersion > _schemaVersion) {
      throw AuctionSessionPersistenceException(
        'Sessione creata con uno schema più recente ($schemaVersion).',
      );
    }

    final initialPlayers = await _restorePlayers(
      document,
      data: data,
      schemaVersion: schemaVersion,
      legacyPlayers: legacyPlayers,
    );
    final initialTeams = _readTeams(data['initial_teams']);
    final myTeamId = data['my_team_id']?.toString();

    if (myTeamId == null ||
        !initialTeams.any((team) => team.id == myTeamId)) {
      throw const AuctionSessionPersistenceException(
        'La squadra personale della sessione non è valida.',
      );
    }

    final eventQuery = await document.reference.collection(_eventsCollection).get();
    final events = eventQuery.docs.map((eventDocument) {
      final raw = Map<String, dynamic>.from(eventDocument.data());
      raw['id'] ??= eventDocument.id;
      return AuctionEvent.fromJson(raw);
    }).toList(growable: false)
      ..sort(_compareEvents);

    final session = AuctionSession(
      id: document.id,
      name: data['name']?.toString() ?? 'Asta Matrix',
      config: AuctionConfig.fromJson(
        Map<String, dynamic>.from(data['config'] as Map),
      ),
      createdAt: _readDate(data['created_at']),
      status: _readStatus(data['status']),
      initialPlayers: initialPlayers,
      initialTeams: initialTeams,
      events: events,
    );

    return RestoredAuctionSession(session: session, myTeamId: myTeamId);
  }

  Future<List<PlayerEntity>> _restorePlayers(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required Map<String, dynamic> data,
    required int schemaVersion,
    required List<PlayerEntity> legacyPlayers,
  }) async {
    if (schemaVersion >= 7) {
      if (data['player_snapshot_status'] != _snapshotReady) {
        throw const AuctionSessionPersistenceException(
          'Il salvataggio del dataset dell’asta non è stato completato. '
          'Riprova tra pochi secondi.',
        );
      }
      return _readPlayerSubcollection(
        document,
        expectedIds: _readStringList(data['initial_player_ids']),
      );
    }

    final embeddedPlayers = _readEmbeddedPlayers(data['initial_players']);
    if (embeddedPlayers != null) return embeddedPlayers;

    return _restoreLegacyPlayers(
      data['initial_player_ids'],
      legacyPlayers: legacyPlayers,
    );
  }

  Future<List<PlayerEntity>> _readPlayerSubcollection(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<String> expectedIds,
  }) async {
    final snapshot =
        await document.reference.collection(_playersCollection).get();
    final playersById = <String, PlayerEntity>{};

    try {
      for (final playerDocument in snapshot.docs) {
        playersById[playerDocument.id] = PlayerModel.fromJson(
          playerDocument.data(),
          documentId: playerDocument.id,
        );
      }
    } on FormatException catch (error) {
      throw AuctionSessionPersistenceException(
        'Snapshot giocatori non valido: ${error.message}',
      );
    }

    final missingIds = expectedIds
        .where((id) => !playersById.containsKey(id))
        .toList(growable: false);
    if (missingIds.isNotEmpty) {
      final preview = missingIds.take(5).join(', ');
      throw AuctionSessionPersistenceException(
        'Dataset incompleto: mancano ${missingIds.length} giocatori ($preview).',
      );
    }

    return expectedIds
        .map((id) => playersById[id]!)
        .toList(growable: false);
  }

  static List<PlayerEntity>? _readEmbeddedPlayers(Object? rawPlayers) {
    if (rawPlayers == null) return null;
    if (rawPlayers is! List) {
      throw const AuctionSessionPersistenceException(
        'Lo snapshot dei giocatori salvato non è valido.',
      );
    }
    if (rawPlayers.isEmpty) {
      throw const AuctionSessionPersistenceException(
        'Lo snapshot dei giocatori salvato è vuoto.',
      );
    }

    try {
      return rawPlayers.map((rawPlayer) {
        if (rawPlayer is! Map) {
          throw const FormatException('record giocatore non valido');
        }
        return PlayerModel.fromJson(Map<String, dynamic>.from(rawPlayer));
      }).toList(growable: false);
    } on FormatException catch (error) {
      throw AuctionSessionPersistenceException(
        'Snapshot giocatori non valido: ${error.message}',
      );
    }
  }

  static List<PlayerEntity> _restoreLegacyPlayers(
    Object? rawPlayerIds, {
    required List<PlayerEntity> legacyPlayers,
  }) {
    final playerIds = _readStringList(rawPlayerIds);
    final playersById = {for (final player in legacyPlayers) player.id: player};
    final missingIds = playerIds
        .where((id) => !playersById.containsKey(id))
        .toList(growable: false);

    if (missingIds.isNotEmpty) {
      final preview = missingIds.take(5).join(', ');
      throw AuctionSessionPersistenceException(
        'Impossibile ripristinare la sessione legacy: '
        '${missingIds.length} giocatori non sono più nel vecchio catalogo '
        '($preview).',
      );
    }

    return playerIds
        .map((id) => playersById[id]!)
        .toList(growable: false);
  }

  static int _compareEvents(AuctionEvent a, AuctionEvent b) {
    final aRevision = a.serverRevision;
    final bRevision = b.serverRevision;

    if (aRevision != null && bRevision != null) {
      final byRevision = aRevision.compareTo(bRevision);
      if (byRevision != 0) return byRevision;
      return a.id.compareTo(b.id);
    }

    // Eventi senza revisione appartengono alla storia pre-migrazione e devono
    // precedere gli eventi creati dopo l'adozione del controller lease.
    if (aRevision == null && bRevision != null) return -1;
    if (aRevision != null && bRevision == null) return 1;

    final byDate = a.occurredAt.compareTo(b.occurredAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  static Map<String, dynamic> _teamToJson(FantasyTeamEntity team) {
    return {
      'id': team.id,
      'name': team.name,
      'credits_remaining': team.creditsRemaining,
    };
  }

  static List<FantasyTeamEntity> _readTeams(Object? rawTeams) {
    if (rawTeams is! List) {
      throw const AuctionSessionPersistenceException(
        'Le squadre salvate non sono valide.',
      );
    }

    return rawTeams.map((rawTeam) {
      if (rawTeam is! Map) {
        throw const AuctionSessionPersistenceException(
          'Una squadra salvata non è valida.',
        );
      }
      final team = Map<String, dynamic>.from(rawTeam);
      return FantasyTeamEntity(
        id: team['id'].toString(),
        name: team['name'].toString(),
        creditsRemaining: (team['credits_remaining'] as num).toInt(),
      );
    }).toList(growable: false);
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) {
      throw const AuctionSessionPersistenceException(
        'La lista iniziale dei giocatori non è valida.',
      );
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static AuctionSessionStatus _readStatus(Object? value) {
    final name = value?.toString();
    return AuctionSessionStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => AuctionSessionStatus.live,
    );
  }

  static DateTime? _readNullableDate(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
