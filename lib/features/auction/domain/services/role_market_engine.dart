import 'dart:math' as math;

import 'package:mantra_matrix/features/auction/domain/entities/role_market_availability.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

/// Analizza la disponibilità residua per ruolo usando una fascia top stabile.
///
/// Un "top" è un giocatore nella fascia iniziale più alta del 15% per FVM
/// all'interno del singolo ruolo. Vengono inclusi almeno tre giocatori, quando
/// il catalogo lo consente, e tutti gli ex aequo sul valore di taglio.
class RoleMarketEngine {
  static const double topShare = 0.15;
  static const int minimumTopPlayers = 3;

  /// Ordine di lettura del listone Mantra nella sezione Mercato.
  static const List<MantraRole> displayOrder = [
    MantraRole.por,
    MantraRole.dc,
    MantraRole.dd,
    MantraRole.ds,
    MantraRole.b,
    MantraRole.e,
    MantraRole.m,
    MantraRole.c,
    MantraRole.t,
    MantraRole.w,
    MantraRole.a,
    MantraRole.pc,
  ];

  const RoleMarketEngine();

  List<RoleMarketAvailability> analyzeCandidate({
    required PlayerEntity candidate,
    required List<PlayerEntity> availablePlayers,
    required List<PlayerEntity> catalogPlayers,
  }) {
    return candidate.roles
        .map(
          (role) => analyzeRole(
            role: role,
            availablePlayers: availablePlayers,
            catalogPlayers: catalogPlayers,
            candidateId: candidate.id,
          ),
        )
        .toList(growable: false);
  }

  List<RoleMarketAvailability> analyzeAllRoles({
    required List<PlayerEntity> availablePlayers,
    required List<PlayerEntity> catalogPlayers,
  }) {
    return displayOrder
        .map(
          (role) => analyzeRole(
            role: role,
            availablePlayers: availablePlayers,
            catalogPlayers: catalogPlayers,
          ),
        )
        .toList(growable: false);
  }

  RoleMarketAvailability analyzeRole({
    required MantraRole role,
    required List<PlayerEntity> availablePlayers,
    required List<PlayerEntity> catalogPlayers,
    String? candidateId,
  }) {
    final catalog = _uniquePlayers(catalogPlayers)
        .where((player) => player.roles.contains(role))
        .toList(growable: false)
      ..sort(_comparePlayers);

    final available = _uniquePlayers(availablePlayers)
        .where(
          (player) =>
              player.status == DraftStatus.available &&
              player.roles.contains(role),
        )
        .toList(growable: false)
      ..sort(_comparePlayers);

    if (catalog.isEmpty) {
      return RoleMarketAvailability(
        role: role,
        remainingPlayers: available.length,
        remainingAlternatives:
            available.where((player) => player.id != candidateId).length,
        remainingTopPlayers: 0,
        remainingTopAlternatives: 0,
        catalogPlayers: 0,
        catalogTopPlayers: 0,
        topCutoffCatalogValue: 0,
        candidateIsTop: false,
        remainingPlayerEntries: available,
        remainingTopPlayerEntries: const [],
      );
    }

    final desiredTopCount = math
        .min(
          catalog.length,
          math.max(minimumTopPlayers, (catalog.length * topShare).ceil()),
        )
        .toInt();
    final cutoff = catalog[desiredTopCount - 1].basePrice;
    final topIds = catalog
        .where((player) => player.basePrice >= cutoff)
        .map((player) => player.id)
        .toSet();

    final remainingTop = available
        .where((player) => topIds.contains(player.id))
        .toList(growable: false)
      ..sort(_comparePlayers);

    return RoleMarketAvailability(
      role: role,
      remainingPlayers: available.length,
      remainingAlternatives:
          available.where((player) => player.id != candidateId).length,
      remainingTopPlayers: remainingTop.length,
      remainingTopAlternatives:
          remainingTop.where((player) => player.id != candidateId).length,
      catalogPlayers: catalog.length,
      catalogTopPlayers: topIds.length,
      topCutoffCatalogValue: cutoff,
      candidateIsTop: candidateId != null && topIds.contains(candidateId),
      remainingPlayerEntries: available,
      remainingTopPlayerEntries: remainingTop,
    );
  }

  int _comparePlayers(PlayerEntity a, PlayerEntity b) {
    final valueComparison = b.basePrice.compareTo(a.basePrice);
    if (valueComparison != 0) return valueComparison;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Iterable<PlayerEntity> _uniquePlayers(List<PlayerEntity> players) {
    final byId = <String, PlayerEntity>{};
    for (final player in players) {
      byId[player.id] = player;
    }
    return byId.values;
  }
}
