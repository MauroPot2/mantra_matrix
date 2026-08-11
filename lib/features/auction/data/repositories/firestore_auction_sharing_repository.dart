import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_sharing_repository.dart';

class FirestoreAuctionSharingRepository implements AuctionSharingRepository {
  static const _sessionsCollection = 'auction_sessions';
  static const _requestsCollection = 'auction_join_requests';
  static const _privateCollection = 'private';
  static const _sharingDocument = 'sharing';

  final FirebaseFirestore firestore;
  final String currentUid;
  final Random _secureRandom;

  FirestoreAuctionSharingRepository(
    this.firestore, {
    required this.currentUid,
    Random? secureRandom,
  }) : _secureRandom = secureRandom ?? Random.secure();

  CollectionReference<Map<String, dynamic>> get _sessions =>
      firestore.collection(_sessionsCollection);

  CollectionReference<Map<String, dynamic>> get _requests =>
      firestore.collection(_requestsCollection);

  @override
  Future<AuctionShareInvite> createInvite({required String sessionId}) async {
    final sessionRef = _sessions.doc(sessionId);
    final sharingRef = sessionRef
        .collection(_privateCollection)
        .doc(_sharingDocument);
    final token = _newToken();

    await firestore.runTransaction((transaction) async {
      final session = await transaction.get(sessionRef);
      final data = session.data();
      if (!session.exists || data == null) {
        throw const AuctionSharingException('Asta non trovata.');
      }
      if (data['owner_uid']?.toString() != currentUid) {
        throw const AuctionSharingException(
          'Solo il proprietario può creare un invito.',
        );
      }

      transaction.set(
        sharingRef,
        {
          'owner_uid': currentUid,
          'session_id': sessionId,
          'enabled': true,
          'token': token,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    return AuctionShareInvite(
      sessionId: sessionId,
      ownerUid: currentUid,
      token: token,
    );
  }

  @override
  Future<void> disableSharing({required String sessionId}) async {
    final sessionRef = _sessions.doc(sessionId);
    final sharingRef = sessionRef
        .collection(_privateCollection)
        .doc(_sharingDocument);

    await firestore.runTransaction((transaction) async {
      final session = await transaction.get(sessionRef);
      final data = session.data();
      if (!session.exists || data == null) {
        throw const AuctionSharingException('Asta non trovata.');
      }
      if (data['owner_uid']?.toString() != currentUid) {
        throw const AuctionSharingException(
          'Solo il proprietario può disattivare gli inviti.',
        );
      }

      transaction.set(
        sharingRef,
        {
          'owner_uid': currentUid,
          'session_id': sessionId,
          'enabled': false,
          'token': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Future<String> requestAccess({required AuctionShareInvite invite}) async {
    if (invite.ownerUid == currentUid) {
      throw const AuctionSharingException(
        'Sei già il proprietario di questa asta.',
      );
    }

    final requestId = '${invite.sessionId}--$currentUid';
    await _requests.doc(requestId).set({
      'session_id': invite.sessionId,
      'owner_uid': invite.ownerUid,
      'requester_uid': currentUid,
      'invite_token': invite.token,
      'status': AuctionJoinRequestStatus.pending.name,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return requestId;
  }

  @override
  Stream<List<AuctionJoinRequest>> watchPendingRequests() {
    return _requests
        .where('owner_uid', isEqualTo: currentUid)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map(_requestFromDocument)
              .where(
                (request) =>
                    request.status == AuctionJoinRequestStatus.pending,
              )
              .toList(growable: false)
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return List<AuctionJoinRequest>.unmodifiable(requests);
        });
  }

  @override
  Stream<AuctionJoinRequest?> watchRequest({required String requestId}) {
    return _requests.doc(requestId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return _requestFromSnapshot(snapshot);
    });
  }

  @override
  Future<void> approveRequest({
    required String requestId,
    String? assignedTeamId,
  }) async {
    final requestRef = _requests.doc(requestId);

    await firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      final requestData = request.data();
      if (!request.exists || requestData == null) {
        throw const AuctionSharingException('Richiesta di accesso non trovata.');
      }
      if (requestData['owner_uid']?.toString() != currentUid) {
        throw const AuctionSharingException(
          'Solo il proprietario può approvare questa richiesta.',
        );
      }
      if (requestData['status']?.toString() !=
          AuctionJoinRequestStatus.pending.name) {
        throw const AuctionSharingException(
          'La richiesta è già stata elaborata.',
        );
      }

      final sessionId = requestData['session_id']?.toString();
      final requesterUid = requestData['requester_uid']?.toString();
      final inviteToken = requestData['invite_token']?.toString();
      if (sessionId == null || requesterUid == null || inviteToken == null) {
        throw const AuctionSharingException('Richiesta di accesso non valida.');
      }

      final sessionRef = _sessions.doc(sessionId);
      final sharingRef = sessionRef
          .collection(_privateCollection)
          .doc(_sharingDocument);
      final session = await transaction.get(sessionRef);
      final sharing = await transaction.get(sharingRef);
      final sessionData = session.data();
      final sharingData = sharing.data();

      if (!session.exists ||
          sessionData == null ||
          sessionData['owner_uid']?.toString() != currentUid) {
        throw const AuctionSharingException('Asta non disponibile.');
      }
      if (!sharing.exists ||
          sharingData == null ||
          sharingData['enabled'] != true ||
          sharingData['token']?.toString() != inviteToken) {
        throw const AuctionSharingException(
          'Invito scaduto o non più valido. Generane uno nuovo.',
        );
      }

      final teams = sessionData['initial_teams'];
      if (assignedTeamId != null &&
          !_containsTeam(teams, assignedTeamId)) {
        throw AuctionSharingException(
          'La squadra $assignedTeamId non appartiene a questa asta.',
        );
      }

      final members = _stringList(sessionData['member_uids']);
      if (!members.contains(requesterUid)) members.add(requesterUid);

      final memberTeamIds = _stringMap(sessionData['member_team_ids']);
      final ownerTeamId = sessionData['my_team_id']?.toString();
      if (ownerTeamId != null && ownerTeamId.isNotEmpty) {
        memberTeamIds.putIfAbsent(currentUid, () => ownerTeamId);
      }
      if (assignedTeamId != null) {
        final alreadyAssigned = memberTeamIds.entries.any(
          (entry) =>
              entry.key != requesterUid && entry.value == assignedTeamId,
        );
        if (alreadyAssigned) {
          throw AuctionSharingException(
            'La squadra $assignedTeamId è già associata a un altro membro.',
          );
        }
        memberTeamIds[requesterUid] = assignedTeamId;
      }

      transaction.update(sessionRef, {
        'member_uids': members,
        'member_team_ids': memberTeamIds,
        'updated_at': FieldValue.serverTimestamp(),
      });
      transaction.update(requestRef, {
        'status': AuctionJoinRequestStatus.approved.name,
        if (assignedTeamId != null) 'assigned_team_id': assignedTeamId,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> rejectRequest({required String requestId}) async {
    final requestRef = _requests.doc(requestId);

    await firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      final data = request.data();
      if (!request.exists || data == null) {
        throw const AuctionSharingException('Richiesta di accesso non trovata.');
      }
      if (data['owner_uid']?.toString() != currentUid) {
        throw const AuctionSharingException(
          'Solo il proprietario può rifiutare questa richiesta.',
        );
      }
      if (data['status']?.toString() !=
          AuctionJoinRequestStatus.pending.name) {
        throw const AuctionSharingException(
          'La richiesta è già stata elaborata.',
        );
      }

      transaction.update(requestRef, {
        'status': AuctionJoinRequestStatus.rejected.name,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Stream<List<AuctionSessionSummary>> watchSharedSessions() {
    return _sessions
        .where('member_uids', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs
              .where(
                (document) =>
                    document.data()['owner_uid']?.toString() != currentUid,
              )
              .map(_sharedSummaryFromDocument)
              .toList(growable: false)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return List<AuctionSessionSummary>.unmodifiable(sessions);
        });
  }

  AuctionJoinRequest _requestFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return _requestFromSnapshot(document);
  }

  AuctionJoinRequest _requestFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    final statusName = data['status']?.toString();
    final status = AuctionJoinRequestStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => AuctionJoinRequestStatus.pending,
    );

    return AuctionJoinRequest(
      id: document.id,
      sessionId: data['session_id']?.toString() ?? '',
      ownerUid: data['owner_uid']?.toString() ?? '',
      requesterUid: data['requester_uid']?.toString() ?? '',
      inviteToken: data['invite_token']?.toString() ?? '',
      status: status,
      createdAt: _readDate(data['created_at']),
      updatedAt: _readNullableDate(data['updated_at']),
      assignedTeamId: data['assigned_team_id']?.toString(),
    );
  }

  AuctionSessionSummary _sharedSummaryFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final configRaw = data['config'];
    final config = configRaw is Map
        ? Map<String, dynamic>.from(configRaw)
        : const <String, dynamic>{};
    final teams = data['initial_teams'];
    final memberTeamIds = _stringMap(data['member_team_ids']);
    final createdAt = _readDate(data['created_at']);

    return AuctionSessionSummary(
      id: document.id,
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : 'Asta Matrix',
      status: _readStatus(data['status']),
      createdAt: createdAt,
      updatedAt: _readNullableDate(data['updated_at']) ?? createdAt,
      myTeamId: memberTeamIds[currentUid] ?? '',
      teamCount: teams is List ? teams.length : 0,
      initialCredits: (config['initial_credits'] as num?)?.toInt() ?? 0,
      rosterSize: (config['roster_size'] as num?)?.toInt() ?? 0,
    );
  }

  String _newToken() {
    final bytes = List<int>.generate(
      24,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool _containsTeam(Object? rawTeams, String teamId) {
    if (rawTeams is! List) return false;
    return rawTeams.any(
      (raw) => raw is Map && raw['id']?.toString() == teamId,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).toList(growable: true);
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return value.map(
      (key, item) => MapEntry(key.toString(), item.toString()),
    );
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
}
