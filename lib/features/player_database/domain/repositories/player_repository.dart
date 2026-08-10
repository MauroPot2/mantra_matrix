import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

/// Ponte di sola lettura verso il catalogo storico.
///
/// Le nuove aste non usano questo repository: serve esclusivamente a
/// ripristinare sessioni legacy schema <= 5 finché non saranno migrate o
/// concluse. Non espone alcuna operazione di scrittura sul catalogo globale.
abstract class PlayerRepository {
  Future<List<PlayerEntity>> fetchLegacyPlayers();
}
