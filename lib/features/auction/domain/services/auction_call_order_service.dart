import 'dart:math';

import 'package:mantra_matrix/features/auction/domain/entities/auction_call_order.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionCallOrderService {
  const AuctionCallOrderService();

  List<String> build({
    required List<PlayerEntity> players,
    required AuctionCallOrderMode mode,
    required int seed,
  }) {
    final ordered = switch (mode) {
      AuctionCallOrderMode.randomAll => _randomAll(players, seed),
      AuctionCallOrderMode.randomByRole => _randomByRole(players, seed),
      AuctionCallOrderMode.alphabeticalByRole => _alphabeticalByRole(players),
    };
    return List<String>.unmodifiable(
      ordered.map((player) => player.id),
    );
  }

  List<PlayerEntity> _randomAll(List<PlayerEntity> players, int seed) {
    return List<PlayerEntity>.of(players)..shuffle(Random(seed));
  }

  List<PlayerEntity> _randomByRole(List<PlayerEntity> players, int seed) {
    final random = Random(seed);
    final result = <PlayerEntity>[];
    for (final role in MantraRole.values) {
      final group = players
          .where((player) => _primaryRole(player) == role)
          .toList(growable: true)
        ..shuffle(random);
      result.addAll(group);
    }
    return result;
  }

  List<PlayerEntity> _alphabeticalByRole(List<PlayerEntity> players) {
    final result = List<PlayerEntity>.of(players);
    result.sort((a, b) {
      final roleComparison = MantraRole.values
          .indexOf(_primaryRole(a))
          .compareTo(MantraRole.values.indexOf(_primaryRole(b)));
      if (roleComparison != 0) return roleComparison;
      final nameComparison = a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          );
      return nameComparison != 0 ? nameComparison : a.id.compareTo(b.id);
    });
    return result;
  }

  MantraRole _primaryRole(PlayerEntity player) => player.roles.first;
}
