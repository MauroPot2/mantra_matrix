import 'dart:math' as math;

import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class FantasyTeamEntity {
  final String id;
  final String name;
  final int creditsRemaining;
  final List<PlayerEntity> roster;

  const FantasyTeamEntity({
    required this.id,
    required this.name,
    required this.creditsRemaining,
    this.roster = const [],
  }) : assert(id != ''),
       assert(name != ''),
       assert(creditsRemaining >= 0);

  int slotsRemaining(AuctionConfig config) {
    return math.max(0, config.rosterSize - roster.length);
  }

  /// Importo massimo spendibile ora, conservando l'offerta minima per ogni
  /// slot che resterà vuoto dopo l'acquisto corrente.
  int maxAffordableBid(AuctionConfig config) {
    final emptySlots = slotsRemaining(config);
    if (emptySlots <= 0) return 0;

    final reserveForLater = (emptySlots - 1) * config.minimumBid;
    return math.max(0, creditsRemaining - reserveForLater);
  }

  int coverageFor(MantraRole role) {
    return roster.where((player) => player.roles.contains(role)).length;
  }

  int missingCoverageFor(MantraRole role, AuctionConfig config) {
    final target = config.targetCoverage[role] ?? 0;
    return math.max(0, target - coverageFor(role));
  }

  FantasyTeamEntity copyWith({
    String? id,
    String? name,
    int? creditsRemaining,
    List<PlayerEntity>? roster,
  }) {
    return FantasyTeamEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      creditsRemaining: creditsRemaining ?? this.creditsRemaining,
      roster: roster ?? this.roster,
    );
  }
}
