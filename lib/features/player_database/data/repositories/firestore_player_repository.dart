import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/repositories/player_repository.dart';

/// Adapter temporaneo di sola lettura per il vecchio `/players` globale.
class FirestorePlayerRepository implements PlayerRepository {
  final FirebaseFirestore firestore;

  const FirestorePlayerRepository(this.firestore);

  CollectionReference<Map<String, dynamic>> get _players =>
      firestore.collection('players');

  @override
  Future<List<PlayerEntity>> fetchLegacyPlayers() async {
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
          'Documento legacy players/${document.id} non valido: ${error.message}',
        );
      }
    }

    players.sort((a, b) => a.name.compareTo(b.name));
    return List<PlayerEntity>.unmodifiable(players);
  }
}
