import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
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
  static const _snapshotReady = 'ready';
  static const _snapshotWriting = 'writing';
  static const _batchSize = 400;

  final FirebaseFirestore _firestore;
  final String _ownerUid;

  const FirestoreAuctionSessionRepository(
    this._firestore, {
    required String ownerUid,
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

    // Il documento sessione resta piccolo. I giocatori vengono persistiti in
    // una subcollection dedicata, evitando il limite Firestore di 1 MiB per
    // documento e rendendo il dataset scalabile e indipendente dal catalogo.
    await sessionRef.set(data, SetOptions(merge: true));
    await _savePlayerSnapshot(sessionRef, session.initialPlayers);
    await sessionRef.set(
      {
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
        final playerRef = sessionRef.collection(_playersCollection).doc(player.id);
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
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final eventRef = sessionRef.collection(_eventsCollection).doc(event.id);
    final batch = _firestore.batch();

    batch.set(eventRef, {
      ...event.toJson(),
      'schema_version': _schemaVersion,
      'created_by_uid': _ownerUid,
    });
    batch.set(
      sessionRef,
      {
        'updated_at': FieldValue.serverTimestamp(),
        'last_event_id': event.id,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
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

    return _restoreFromDocument(document, legacyPlayers: players);
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

    return _restoreFromDocument(documents.first, legacyPlayers: players);
  }

  @override
  Future<void> updateStatus({
    required String sessionId,
    required AuctionSessionStatus status,
  }) {
    return _sessions.doc(sessionId).set(
      {
        'status': status.name,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

    final eventQuery = await document.reference
        .collection(_eventsCollection)
        .orderBy('occurred_at')
        .get();
    final events = eventQuery.docs
        .map((eventDocument) {
          final raw = Map<String, dynamic>.from(eventDocument.data());
          raw['id'] ??= eventDocument.id;
          return AuctionEvent.fromJson(raw);
        })
        .toList(growable: false);

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

    // Compatibilità con la breve versione intermedia v6 che salvava lo
    // snapshot nel documento sessione.
    final embeddedPlayers = _readEmbeddedPlayers(data['initial_players']);
    if (embeddedPlayers != null) return embeddedPlayers;

    // Schema <= 5: ultimo ponte di compatibilità con il vecchio catalogo.
    return _restoreLegacyPlayers(
      data['initial_player_ids'],
      legacyPlayers: legacyPlayers,
    );
  }

  Future<List<PlayerEntity>> _readPlayerSubcollection(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<String> expectedIds,
  }) async {
    final snapshot = await document.reference.collection(_playersCollection).get();
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
