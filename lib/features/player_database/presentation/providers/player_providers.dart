import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/player_database/data/repositories/firestore_player_repository.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/repositories/player_repository.dart';

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  return FirestorePlayerRepository(ref.watch(firebaseFirestoreProvider));
});

/// Caricato soltanto come compatibilità per le vecchie sessioni schema <= 5.
final legacyPlayersProvider = FutureProvider<List<PlayerEntity>>((ref) async {
  final repository = ref.watch(playerRepositoryProvider);
  return repository.fetchLegacyPlayers();
});
