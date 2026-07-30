import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

/// Fotografia del mercato residuo per uno specifico ruolo Mantra.
///
/// La fascia top viene calcolata sul catalogo iniziale e rimane stabile durante
/// tutta l'asta. Le liste [remainingPlayerEntries] e
/// [remainingTopPlayerEntries] contengono invece soltanto i giocatori ancora
/// disponibili nello snapshot corrente.
class RoleMarketAvailability {
  final MantraRole role;
  final int remainingPlayers;
  final int remainingAlternatives;
  final int remainingTopPlayers;
  final int remainingTopAlternatives;
  final int catalogPlayers;
  final int catalogTopPlayers;
  final int topCutoffCatalogValue;
  final bool candidateIsTop;

  /// Tutti i giocatori ancora disponibili per il ruolo, ordinati per FVM.
  final List<PlayerEntity> remainingPlayerEntries;

  /// I top ancora disponibili per il ruolo, ordinati per FVM.
  final List<PlayerEntity> remainingTopPlayerEntries;

  RoleMarketAvailability({
    required this.role,
    required this.remainingPlayers,
    required this.remainingAlternatives,
    required this.remainingTopPlayers,
    required this.remainingTopAlternatives,
    required this.catalogPlayers,
    required this.catalogTopPlayers,
    required this.topCutoffCatalogValue,
    required this.candidateIsTop,
    required List<PlayerEntity> remainingPlayerEntries,
    required List<PlayerEntity> remainingTopPlayerEntries,
  })  : remainingPlayerEntries =
            List<PlayerEntity>.unmodifiable(remainingPlayerEntries),
        remainingTopPlayerEntries =
            List<PlayerEntity>.unmodifiable(remainingTopPlayerEntries);

  double get remainingShare =>
      catalogPlayers == 0 ? 0 : remainingPlayers / catalogPlayers;

  bool get isTopScarce => remainingTopPlayers <= 2;

  bool isTopPlayer(String playerId) =>
      remainingTopPlayerEntries.any((player) => player.id == playerId);
}
