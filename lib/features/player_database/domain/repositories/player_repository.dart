import 'package:mantra_matrix/features/player_database/domain/entities/player_catalog.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

abstract class PlayerRepository {
  Future<List<PlayerEntity>> fetchAllPlayers();

  Future<PlayerCatalogMetadata?> fetchCatalogMetadata();

  /// Aggiorna il catalogo globale. Le regole Firestore consentono questa
  /// operazione esclusivamente agli account con custom claim `admin: true`.
  Future<PlayerCatalogUpdateResult> updateCatalog({
    required List<PlayerEntity> players,
    required String sourceName,
    required String updatedByUid,
    bool deactivateMissing = true,
  });

  Future<void> updatePlayerAuctionState(
    String playerId,
    DraftStatus status,
    String? teamId,
    int? price,
  );
}
