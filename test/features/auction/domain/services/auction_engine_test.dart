import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_engine.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const engine = AuctionEngine();

  final config = AuctionConfig(
    initialCredits: 100,
    rosterSize: 5,
    minimumBid: 1,
    targetCoverage: const {MantraRole.dc: 2, MantraRole.c: 1, MantraRole.pc: 1},
  );

  test('non supera mai il tetto necessario a completare la rosa', () {
    final team = FantasyTeamEntity(
      id: 'me',
      name: 'Matrix FC',
      creditsRemaining: 20,
      roster: [
        player(id: 'a', role: MantraRole.dc),
        player(id: 'b', role: MantraRole.c),
      ],
    );

    final target = player(
      id: 'target',
      role: MantraRole.pc,
      basePrice: 500,
      expectedPoints: 90,
      vorp: 15,
    );

    final result = engine.evaluate(
      player: target,
      myTeam: team,
      config: config,
      availablePlayers: [target],
      currentBid: 1,
    );

    // Restano 3 slot: dopo questo acquisto servono almeno 2 crediti.
    expect(result.hardBudgetCeiling, 18);
    expect(result.maxBid, 18);
  });

  test('un infortunio riduce il valore rispetto allo stesso profilo sano', () {
    const team = FantasyTeamEntity(
      id: 'me',
      name: 'Matrix FC',
      creditsRemaining: 100,
    );

    final healthy = player(
      id: 'healthy',
      role: MantraRole.pc,
      basePrice: 30,
      expectedPoints: 70,
      vorp: 10,
    );
    final injured = player(
      id: 'injured',
      role: MantraRole.pc,
      basePrice: 30,
      expectedPoints: 70,
      vorp: 10,
      isInjured: true,
    );

    final healthyResult = engine.evaluate(
      player: healthy,
      myTeam: team,
      config: config,
      availablePlayers: [healthy, injured],
      currentBid: 1,
    );
    final injuredResult = engine.evaluate(
      player: injured,
      myTeam: team,
      config: config,
      availablePlayers: [healthy, injured],
      currentBid: 1,
    );

    expect(injuredResult.fairValue, lessThan(healthyResult.fairValue));
    expect(injuredResult.warnings, isNotEmpty);
  });

  test('consiglia di passare quando il prezzo supera il tetto', () {
    const team = FantasyTeamEntity(
      id: 'me',
      name: 'Matrix FC',
      creditsRemaining: 10,
    );

    final target = player(id: 'target', role: MantraRole.dc, basePrice: 4);

    final result = engine.evaluate(
      player: target,
      myTeam: team,
      config: config,
      availablePlayers: [target],
      currentBid: 9,
    );

    expect(result.decision, AuctionDecision.pass);
  });
}

PlayerEntity player({
  required String id,
  required MantraRole role,
  int basePrice = 10,
  double expectedPoints = 50,
  double vorp = 5,
  bool isInjured = false,
}) {
  return PlayerEntity(
    id: id,
    name: 'Player $id',
    team: 'TEST',
    roles: [role],
    basePrice: basePrice,
    expectedGoals: 0,
    expectedAssists: 0,
    expectedGoals90: 0.2,
    expectedAssists90: 0.1,
    expectedYellowCards: 2,
    historicalMinutes: 2400,
    expectedPoints: expectedPoints,
    vorp: vorp,
    isInjured: isInjured,
  );
}
