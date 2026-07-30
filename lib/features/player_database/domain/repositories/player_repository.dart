import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

abstract class PlayerRepository {
  Future<List<PlayerEntity>> fetchAllPlayers();

  Future<void> updatePlayerAuctionState(
    String playerId,
    DraftStatus status,
    String? teamId,
    int? price,
  );
}
