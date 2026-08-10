import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_join_preview.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_session_repository.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class FirestoreAuctionSessionRepository implements AuctionSessionRepository {
  static const _schemaVersion = 6;
  static const _sessionsCollection = 'auction_sessions';
  static const _invitesCollection = 'auction_invites';
  static const _eventsCollection = 'events';

  final FirebaseFirestore _firestore;
  final String _currentUid;

  const FirestoreAuctionSessionRepository(
    this._firestore, {
    required String ownerUid,
  }) : _currentUid = ownerUid;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(_sessionsCollection);

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection(_invitesCollection);

  @override
  Future<void> saveSession({
    required AuctionSession session,
    required String myTeamId,
  }) async {
    final ownerUid = session.ownerUid.isEmpty ? _currentUid : session.ownerUid;
    final memberTeamIds = session.memberTeamIds.isEmpty
        ? {_currentUid: myTeamId}
        : session.memberTeamIds;
    final memberUids = memberTeamIds.keys.toList(growable: false);
    final sessionRef = _sessions.doc(session.id);
    final inviteRef = session.isShared && session.joinCode.isNotEmpty
        ? _invites.doc(session.joinCode)
        : null;

    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(sessionRef);
      DocumentSnapshot<Map<String, dynamic>>? invite;
      if (inviteRef != null) invite = await transaction.get(inviteRef);

      if (invite?.exists == true &&
          invite?.data()?['session_id']?.toString() != session.id) {
        throw const AuctionSessionPersistenceException(
          'Codice di condivisione già in uso. Crea nuovamente l’asta.',
        );
      }

      final data = <String, dynamic>{
        'schema_version': _schemaVersion,
        'owner_uid': ownerUid,
        'member_uids': memberUids,
        'member_team_ids': memberTeamIds,
        'name': session.name,
        'status': session.status.name,
        'my_team_id': myTeamId,
        'join_enabled': session.isShared,
        'join_code': session.joinCode,
        'created_at': Timestamp.fromDate(session.createdAt.toUtc()),
        'updated_at': FieldValue.serverTimestamp(),
        'config': session.config.toJson(),
        'initial_player_ids': session.initialPlayers
            .map((player) => player.id)
            .toList(growable: false),
        // Lo snapshot rende le aste storiche indipendenti dagli aggiornamenti
        // futuri del listone globale.
        'initial_players': session.initialPlayers
            .map((player) => PlayerModel.fromEntity(player).toJson())
            .toList(growable: false),
        'call_order_player_ids': session.callOrderPlayerIds,
        'initial_teams': session.initialTeams
            .map(_teamToJson)
            .toList(growable: false),
        'team_ids': session.initialTeams
            .map((team) => team.id)
            .toList(growable: false),
      };
      if (!current.exists) {
        data['last_event_id'] = null;
        data['last_event_sequence'] = 0;
      }
      transaction.set(sessionRef, data, SetOptions(merge: true));

      if (inviteRef != null) {
        transaction.set(inviteRef, {
          'session_id': session.id,
          'owner_uid': ownerUid,
          'session_name': session.name,
          'enabled': true,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  @override
  Future<void> appendEvent({
    required String sessionId,
    required AuctionEvent event,
    required String? expectedLastEventId,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final eventRef = sessionRef.collection(_eventsCollection).doc(event.id);

    await _firestore.runTransaction((transaction) async {
      final sessionDocument = await transaction.get(sessionRef);
      final sessionData = sessionDocument.data();
      if (sessionData == null) {
        throw const AuctionSessionPersistenceException(
          'La sessione non esiste più.',
        );
      }
      if (sessionData['status'] != AuctionSessionStatus.live.name) {
        throw const AuctionSessionPersistenceException(
          'L’asta è già conclusa.',
        );
      }

      final actualLastEventId = sessionData['last_event_id']?.toString();
      if (actualLastEventId != expectedLastEventId) {
        throw const AuctionSessionConflictException();
      }

      final schemaVersion =
          (sessionData['schema_version'] as num?)?.toInt() ?? 0;
      final nextSequence =
          ((sessionData['last_event_sequence'] as num?)?.toInt() ?? 0) + 1;
      final eventData = <String, dynamic>{
        ...event.toJson(),
        'schema_version': _schemaVersion,
        'created_by_uid': _currentUid,
        // Durante una scrittura locale il server timestamp può essere
        // temporaneamente nullo. Questo valore evita buchi nello stream; al
        // commit viene sostituito dall'ora autorevole del server.
        'client_occurred_at': Timestamp.fromDate(event.occurredAt.toUtc()),
      };
      if (schemaVersion >= _schemaVersion) {
        eventData
          ..['occurred_at'] = FieldValue.serverTimestamp()
          ..['sequence'] = nextSequence;
      }

      transaction.set(eventRef, eventData);
      transaction.set(sessionRef, {
        'updated_at': FieldValue.serverTimestamp(),
        'last_event_id': event.id,
        'last_event_sequence': nextSequence,
      }, SetOptions(merge: true));
    });
  }

  @override
  Stream<List<AuctionEvent>> watchEvents({required String sessionId}) {
    final sessionRef = _sessions.doc(sessionId);
    return Stream.fromFuture(sessionRef.get()).asyncExpand((sessionDocument) {
      final schemaVersion =
          (sessionDocument.data()?['schema_version'] as num?)?.toInt() ?? 0;
      final orderField = schemaVersion >= _schemaVersion
          ? 'sequence'
          : 'occurred_at';
      return sessionRef
          .collection(_eventsCollection)
          .orderBy(orderField)
          .snapshots()
          .map((snapshot) {
            return List<AuctionEvent>.unmodifiable(
              snapshot.docs.map(_eventFromDocument),
            );
          });
    });
  }

  @override
  Stream<AuctionSessionStatus> watchStatus({required String sessionId}) {
    return _sessions.doc(sessionId).snapshots().map((document) {
      final data = document.data();
      if (data == null) {
        throw const AuctionSessionPersistenceException(
          'La sessione non esiste più.',
        );
      }
      return _readStatus(data['status']);
    }).distinct();
  }

  @override
  Stream<List<AuctionSessionSummary>> watchOwnedSessions() {
    // La query owner mantiene accessibili le sessioni create con gli schemi
    // precedenti, che non avevano ancora `member_uids`.
    final controller = StreamController<List<AuctionSessionSummary>>();
    var memberDocuments =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var ownerDocuments =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
    memberSubscription;
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
    ownerSubscription;

    void emit() {
      final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        ...ownerDocuments,
        ...memberDocuments,
      };
      final sessions =
          documents.values
              .map(_summaryFromDocument)
              .whereType<AuctionSessionSummary>()
              .toList(growable: false)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      controller.add(List<AuctionSessionSummary>.unmodifiable(sessions));
    }

    void addError(Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
    }

    controller.onListen = () {
      memberSubscription = _sessions
          .where('member_uids', arrayContains: _currentUid)
          .snapshots()
          .listen((snapshot) {
            memberDocuments = {
              for (final document in snapshot.docs) document.id: document,
            };
            emit();
          }, onError: addError);
      ownerSubscription = _sessions
          .where('owner_uid', isEqualTo: _currentUid)
          .snapshots()
          .listen((snapshot) {
            ownerDocuments = {
              for (final document in snapshot.docs) document.id: document,
            };
            emit();
          }, onError: addError);
    };
    controller.onCancel = () async {
      await memberSubscription.cancel();
      await ownerSubscription.cancel();
    };
    return controller.stream;
  }

  @override
  Future<AuctionJoinPreview> loadJoinPreview({required String joinCode}) async {
    final normalizedCode = _normalizeJoinCode(joinCode);
    final invite = await _invites.doc(normalizedCode).get();
    final inviteData = invite.data();
    if (inviteData == null || inviteData['enabled'] != true) {
      throw const AuctionSessionPersistenceException(
        'Codice asta non valido o non più attivo.',
      );
    }

    final sessionId = inviteData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw const AuctionSessionPersistenceException(
        'Invito non collegato a una sessione valida.',
      );
    }
    final sessionDocument = await _sessions.doc(sessionId).get();
    final data = sessionDocument.data();
    if (data == null ||
        data['status'] != AuctionSessionStatus.live.name ||
        data['join_enabled'] != true) {
      throw const AuctionSessionPersistenceException(
        'Questa asta non accetta più partecipanti.',
      );
    }

    return AuctionJoinPreview(
      sessionId: sessionId,
      sessionName: data['name']?.toString() ?? 'Asta Mantra',
      joinCode: normalizedCode,
      teams: _readTeams(data['initial_teams']),
      claimedTeamIds: _readStringMap(data['member_team_ids']).values.toSet(),
    );
  }

  @override
  Future<String> joinSession({
    required String joinCode,
    required String teamId,
  }) async {
    final normalizedCode = _normalizeJoinCode(joinCode);
    final inviteRef = _invites.doc(normalizedCode);

    return _firestore.runTransaction((transaction) async {
      final invite = await transaction.get(inviteRef);
      final inviteData = invite.data();
      if (inviteData == null || inviteData['enabled'] != true) {
        throw const AuctionSessionPersistenceException(
          'Codice asta non valido o non più attivo.',
        );
      }

      final sessionId = inviteData['session_id']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw const AuctionSessionPersistenceException('Invito non valido.');
      }
      final sessionRef = _sessions.doc(sessionId);
      final session = await transaction.get(sessionRef);
      final data = session.data();
      if (data == null ||
          data['status'] != AuctionSessionStatus.live.name ||
          data['join_enabled'] != true) {
        throw const AuctionSessionPersistenceException(
          'Questa asta non accetta più partecipanti.',
        );
      }

      final teams = _readTeams(data['initial_teams']);
      if (!teams.any((team) => team.id == teamId)) {
        throw const AuctionSessionPersistenceException(
          'La squadra selezionata non esiste.',
        );
      }

      final memberTeamIds = _readStringMap(data['member_team_ids']);
      final existingTeamId = memberTeamIds[_currentUid];
      if (existingTeamId != null) return sessionId;
      if (memberTeamIds.values.contains(teamId)) {
        throw const AuctionSessionPersistenceException(
          'La squadra è stata appena scelta da un altro partecipante.',
        );
      }

      final memberUids = _readStringList(data['member_uids']).toSet()
        ..add(_currentUid);
      memberTeamIds[_currentUid] = teamId;
      transaction.update(sessionRef, {
        'member_uids': memberUids.toList(growable: false),
        'member_team_ids': memberTeamIds,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return sessionId;
    });
  }

  @override
  Future<RestoredAuctionSession?> loadSession({
    required String sessionId,
    required List<PlayerEntity> players,
  }) async {
    final document = await _sessions.doc(sessionId).get();
    if (!document.exists) return null;
    return _restoreFromDocument(document, players: players);
  }

  @override
  Future<RestoredAuctionSession?> loadLatestActiveSession({
    required List<PlayerEntity> players,
  }) async {
    final queries = await Future.wait([
      _sessions
          .where('member_uids', arrayContains: _currentUid)
          .limit(50)
          .get(),
      _sessions.where('owner_uid', isEqualTo: _currentUid).limit(50).get(),
    ]);
    final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final query in queries)
        for (final document in query.docs) document.id: document,
    };
    final liveDocuments = documents.values
        .where(
          (document) =>
              document.data()['status'] == AuctionSessionStatus.live.name,
        )
        .toList(growable: false);
    if (liveDocuments.isEmpty) return null;

    liveDocuments.sort((a, b) {
      final aDate = _readDate(a.data()['updated_at']);
      final bDate = _readDate(b.data()['updated_at']);
      return bDate.compareTo(aDate);
    });
    return _restoreFromDocument(liveDocuments.first, players: players);
  }

  @override
  Future<void> updateStatus({
    required String sessionId,
    required AuctionSessionStatus status,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final session = await sessionRef.get();
    final data = session.data();
    await sessionRef.set({
      'status': status.name,
      'join_enabled':
          status == AuctionSessionStatus.live && data?['join_enabled'] == true,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final joinCode = data?['join_code']?.toString();
    if (status == AuctionSessionStatus.completed &&
        joinCode != null &&
        joinCode.isNotEmpty) {
      await _invites.doc(joinCode).set({
        'enabled': false,
      }, SetOptions(merge: true));
    }
  }

  AuctionSessionSummary? _summaryFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final memberUids = _readStringList(data['member_uids']);
    final ownerUid = data['owner_uid']?.toString() ?? '';
    if (ownerUid != _currentUid && !memberUids.contains(_currentUid)) {
      return null;
    }

    final configRaw = data['config'];
    final config = configRaw is Map
        ? Map<String, dynamic>.from(configRaw)
        : const <String, dynamic>{};
    final initialTeams = data['initial_teams'];
    final createdAt = _readDate(data['created_at']);
    final updatedAt = _readNullableDate(data['updated_at']) ?? createdAt;
    final memberTeamIds = _readStringMap(data['member_team_ids']);

    return AuctionSessionSummary(
      id: document.id,
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : 'Asta Mantra',
      status: _readStatus(data['status']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      myTeamId:
          memberTeamIds[_currentUid] ??
          (ownerUid == _currentUid ? data['my_team_id']?.toString() ?? '' : ''),
      teamCount: initialTeams is List ? initialTeams.length : 0,
      initialCredits: (config['initial_credits'] as num?)?.toInt() ?? 0,
      rosterSize: (config['roster_size'] as num?)?.toInt() ?? 0,
      isOwner: ownerUid == _currentUid,
      isShared:
          data['join_enabled'] == true ||
          data['join_code']?.toString().isNotEmpty == true,
      joinCode: data['join_code']?.toString() ?? '',
      memberCount: memberUids.isEmpty ? 1 : memberUids.length,
    );
  }

  Future<RestoredAuctionSession> _restoreFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<PlayerEntity> players,
  }) async {
    final data = document.data();
    if (data == null) {
      throw const AuctionSessionPersistenceException(
        'La sessione non contiene dati validi.',
      );
    }

    final ownerUid = data['owner_uid']?.toString() ?? '';
    final memberUids = _readStringList(data['member_uids']);
    if (ownerUid != _currentUid && !memberUids.contains(_currentUid)) {
      throw const AuctionSessionPersistenceException(
        'Non fai parte di questa asta.',
      );
    }

    final schemaVersion = (data['schema_version'] as num?)?.toInt() ?? 0;
    if (schemaVersion > _schemaVersion) {
      throw AuctionSessionPersistenceException(
        'Sessione creata con uno schema più recente ($schemaVersion).',
      );
    }

    final initialPlayers = _readInitialPlayers(data, fallbackPlayers: players);
    final initialTeams = _readTeams(data['initial_teams']);
    final memberTeamIds = _readStringMap(data['member_team_ids']);
    final myTeamId =
        memberTeamIds[_currentUid] ??
        (ownerUid == _currentUid ? data['my_team_id']?.toString() : null);
    if (myTeamId == null || !initialTeams.any((team) => team.id == myTeamId)) {
      throw const AuctionSessionPersistenceException(
        'La squadra personale della sessione non è valida.',
      );
    }

    final orderField = schemaVersion >= _schemaVersion
        ? 'sequence'
        : 'occurred_at';
    final eventQuery = await document.reference
        .collection(_eventsCollection)
        .orderBy(orderField)
        .get();
    final events = eventQuery.docs
        .map(_eventFromDocument)
        .toList(growable: false);

    final session = AuctionSession(
      id: document.id,
      name: data['name']?.toString() ?? 'Asta Mantra',
      config: AuctionConfig.fromJson(
        Map<String, dynamic>.from(data['config'] as Map),
      ),
      createdAt: _readDate(data['created_at']),
      status: _readStatus(data['status']),
      initialPlayers: initialPlayers,
      initialTeams: initialTeams,
      callOrderPlayerIds: _readStringList(data['call_order_player_ids']),
      ownerUid: ownerUid,
      joinCode: data['join_code']?.toString() ?? '',
      isShared: data['join_code']?.toString().isNotEmpty == true,
      memberTeamIds: memberTeamIds,
      events: events,
    );
    return RestoredAuctionSession(session: session, myTeamId: myTeamId);
  }

  static List<PlayerEntity> _readInitialPlayers(
    Map<String, dynamic> data, {
    required List<PlayerEntity> fallbackPlayers,
  }) {
    final snapshot = data['initial_players'];
    if (snapshot is List && snapshot.isNotEmpty) {
      return snapshot
          .map((rawPlayer) {
            if (rawPlayer is! Map) {
              throw const AuctionSessionPersistenceException(
                'Snapshot giocatori non valido.',
              );
            }
            return PlayerModel.fromJson(Map<String, dynamic>.from(rawPlayer));
          })
          .toList(growable: false);
    }

    final playerIds = _readStringList(data['initial_player_ids']);
    final playersById = {
      for (final player in fallbackPlayers) player.id: player,
    };
    final missingIds = playerIds
        .where((id) => !playersById.containsKey(id))
        .toList(growable: false);
    if (missingIds.isNotEmpty) {
      throw AuctionSessionPersistenceException(
        'Impossibile ripristinare la sessione legacy: '
        '${missingIds.length} giocatori non sono più nel catalogo '
        '(${missingIds.take(5).join(', ')}).',
      );
    }
    return playerIds.map((id) => playersById[id]!).toList(growable: false);
  }

  static AuctionEvent _eventFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final raw = Map<String, dynamic>.from(document.data());
    raw['id'] ??= document.id;
    raw['occurred_at'] = _readDate(
      raw['occurred_at'] ?? raw['client_occurred_at'],
    );
    return AuctionEvent.fromJson(raw);
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
    return rawTeams
        .map((rawTeam) {
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
        })
        .toList(growable: false);
  }

  static List<String> _readStringList(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const AuctionSessionPersistenceException(
        'Una lista salvata non è valida.',
      );
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static Map<String, String> _readStringMap(Object? value) {
    if (value == null) return <String, String>{};
    if (value is! Map) {
      throw const AuctionSessionPersistenceException(
        'La mappa dei partecipanti non è valida.',
      );
    }
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value.toString(),
    };
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
    return _readNullableDate(value) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static String _normalizeJoinCode(String code) {
    final normalized = code.trim().toUpperCase().replaceAll(' ', '');
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(normalized)) {
      throw const AuctionSessionPersistenceException(
        'Il codice deve contenere 6 caratteri.',
      );
    }
    return normalized;
  }
}
