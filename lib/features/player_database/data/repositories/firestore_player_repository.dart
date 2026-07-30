import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/repositories/player_repository.dart';

class FirestorePlayerRepository implements PlayerRepository {
  final FirebaseFirestore firestore;

  const FirestorePlayerRepository(this.firestore);

  CollectionReference<Map<String, dynamic>> get _players =>
      firestore.collection('players');

  @override
  Future<List<PlayerEntity>> fetchAllPlayers() async {
    final snapshot = await _players.get();
    final players = <PlayerEntity>[];

    for (final document in snapshot.docs) {
      try {
        players.add(
          PlayerModel.fromJson(
            document.data(),
            documentId: document.id,
          ),
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
}
