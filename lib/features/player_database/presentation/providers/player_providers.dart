import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/player_database/data/repositories/firestore_player_repository.dart';
import 'package:mantra_matrix/features/player_database/data/services/player_catalog_import_service.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_catalog.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/repositories/player_repository.dart';

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  return FirestorePlayerRepository(ref.watch(firebaseFirestoreProvider));
});

final allPlayersProvider = FutureProvider<List<PlayerEntity>>((ref) async {
  final repository = ref.watch(playerRepositoryProvider);
  return repository.fetchAllPlayers();
});

final playerCatalogMetadataProvider =
    FutureProvider<PlayerCatalogMetadata?>((ref) async {
  return ref.watch(playerRepositoryProvider).fetchCatalogMetadata();
});

final playerCatalogImportServiceProvider = Provider((ref) {
  return const PlayerCatalogImportService();
});

final playerCatalogAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return false;
  final token = await user.getIdTokenResult();
  if (token.claims?['admin'] == true) return true;
  final profile = await ref
      .watch(firebaseFirestoreProvider)
      .collection('users')
      .doc(user.uid)
      .get();
  return profile.data()?['is_admin'] == true;
});
