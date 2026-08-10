import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_catalog.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/repositories/player_repository.dart';

class FirestorePlayerRepository implements PlayerRepository {
  final FirebaseFirestore firestore;

  const FirestorePlayerRepository(this.firestore);

  CollectionReference<Map<String, dynamic>> get _players =>
      firestore.collection('players');

  DocumentReference<Map<String, dynamic>> get _catalogMetadata =>
      firestore.collection('player_catalogs').doc('current');

  @override
  Future<List<PlayerEntity>> fetchAllPlayers() async {
    final snapshot = await _players.get();
    final players = <PlayerEntity>[];

    for (final document in snapshot.docs) {
      if (document.data()['active'] == false) continue;
      try {
        players.add(
          PlayerModel.fromJson(document.data(), documentId: document.id),
        );
      } on FormatException catch (error) {
        throw FormatException(
          'Documento players/${document.id} non valido: ${error.message}',
        );
      }
    }

    players.sort((a, b) => a.name.compareTo(b.name));
    return List<PlayerEntity>.unmodifiable(players);
  }

  @override
  Future<PlayerCatalogMetadata?> fetchCatalogMetadata() async {
    final document = await _catalogMetadata.get();
    final data = document.data();
    if (data == null) return null;

    return PlayerCatalogMetadata(
      version: data['version']?.toString() ?? 'legacy',
      activePlayerCount: (data['active_player_count'] as num?)?.toInt() ?? 0,
      sourceName: data['source_name']?.toString() ?? 'Non specificata',
      updatedAt: _readDate(data['updated_at']),
      updatedByUid: data['updated_by_uid']?.toString(),
    );
  }

  @override
  Future<PlayerCatalogUpdateResult> updateCatalog({
    required List<PlayerEntity> players,
    required String sourceName,
    required String updatedByUid,
    bool deactivateMissing = true,
  }) async {
    if (players.isEmpty) {
      throw const FormatException('Il listone importato è vuoto.');
    }

    final existingSnapshot = await _players.get();
    final importedIds = players.map((player) => player.id).toSet();
    final existingActiveIds = existingSnapshot.docs
        .where((document) => document.data()['active'] != false)
        .map((document) => document.id)
        .toSet();
    final missingIds = deactivateMissing
        ? existingActiveIds.difference(importedIds)
        : const <String>{};

    final now = DateTime.now().toUtc();
    final version = now.toIso8601String();
    var batch = firestore.batch();
    var pendingWrites = 0;

    Future<void> flush() async {
      if (pendingWrites == 0) return;
      await batch.commit();
      batch = firestore.batch();
      pendingWrites = 0;
    }

    Future<void> enqueue(
      DocumentReference<Map<String, dynamic>> reference,
      Map<String, dynamic> data, {
      required bool merge,
    }) async {
      batch.set(reference, data, SetOptions(merge: merge));
      pendingWrites++;
      if (pendingWrites >= 450) await flush();
    }

    for (final player in players) {
      final data = PlayerModel.fromEntity(
        player.copyWith(
          status: DraftStatus.available,
          draftedByTeamId: null,
          purchasePrice: null,
        ),
      ).toJson();
      await enqueue(_players.doc(player.id), {
        ...data,
        'active': true,
        'catalog_version': version,
        'catalog_updated_at': FieldValue.serverTimestamp(),
      }, merge: true);
    }

    for (final playerId in missingIds) {
      await enqueue(_players.doc(playerId), {
        'active': false,
        'catalog_version': version,
        'catalog_updated_at': FieldValue.serverTimestamp(),
      }, merge: true);
    }

    final activeCount = deactivateMissing
        ? importedIds.length
        : existingActiveIds.union(importedIds).length;
    await enqueue(_catalogMetadata, {
      'version': version,
      'active_player_count': activeCount,
      'source_name': sourceName.trim().isEmpty
          ? 'Import manuale'
          : sourceName.trim(),
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by_uid': updatedByUid,
    }, merge: true);
    await flush();

    return PlayerCatalogUpdateResult(
      version: version,
      importedCount: players.length,
      deactivatedCount: missingIds.length,
    );
  }

  @override
  Future<void> updatePlayerAuctionState(
    String playerId,
    DraftStatus status,
    String? teamId,
    int? price,
  ) async {
    await _players.doc(playerId).update({
      'status': status.name,
      'drafted_by_team_id': teamId,
      'purchase_price': price,
    });
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }
}
