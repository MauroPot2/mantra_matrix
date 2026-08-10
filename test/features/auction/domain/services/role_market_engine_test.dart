import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/services/role_market_engine.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const engine = RoleMarketEngine();

  test('mantiene stabile la fascia top sul catalogo iniziale', () {
    final catalog = [
      for (var index = 0; index < 20; index++)
        player(id: 'pc-$index', role: MantraRole.pc, basePrice: 100 - index),
    ];
    final available = catalog
        .where((candidate) => candidate.id != 'pc-0')
        .toList(growable: false);

    final result = engine.analyzeRole(
      role: MantraRole.pc,
      availablePlayers: available,
      catalogPlayers: catalog,
      candidateId: 'pc-1',
    );

    expect(result.catalogPlayers, 20);
    expect(result.catalogTopPlayers, 3);
    expect(result.remainingPlayers, 19);
    expect(result.remainingTopPlayers, 2);
    expect(result.remainingTopAlternatives, 1);
    expect(result.candidateIsTop, isTrue);
    expect(result.topCutoffCatalogValue, 98);
  });

  test('espone i ruoli nell’ordine Mantra previsto dalla UI', () {
    final result = engine.analyzeAllRoles(
      availablePlayers: const [],
      catalogPlayers: const [],
    );

    expect(result.map((market) => market.role), RoleMarketEngine.displayOrder);
  });

  test('restituisce i nomi dei top rimasti ordinati per FVM', () {
    final catalog = [
      player(id: 'top-2', role: MantraRole.a, basePrice: 90),
      player(id: 'top-1', role: MantraRole.a, basePrice: 100),
      player(id: 'top-3', role: MantraRole.a, basePrice: 80),
      player(id: 'normal-1', role: MantraRole.a, basePrice: 40),
      player(id: 'normal-2', role: MantraRole.a, basePrice: 30),
      player(id: 'normal-3', role: MantraRole.a, basePrice: 20),
    ];
    final available = catalog
        .where((candidate) => candidate.id != 'top-2')
        .toList(growable: false);

    final result = engine.analyzeRole(
      role: MantraRole.a,
      availablePlayers: available,
      catalogPlayers: catalog,
    );

    expect(result.remainingTopPlayerEntries.map((player) => player.id), [
      'top-1',
      'top-3',
    ]);
    expect(result.remainingTopPlayers, 2);
    expect(result.isTopPlayer('top-1'), isTrue);
    expect(result.isTopPlayer('normal-1'), isFalse);
  });

  test('include gli ex aequo sul valore di taglio top', () {
    final catalog = [
      player(id: 'p1', role: MantraRole.c, basePrice: 100),
      player(id: 'p2', role: MantraRole.c, basePrice: 90),
      player(id: 'p3', role: MantraRole.c, basePrice: 80),
      player(id: 'p4', role: MantraRole.c, basePrice: 80),
      player(id: 'p5', role: MantraRole.c, basePrice: 50),
      player(id: 'p6', role: MantraRole.c, basePrice: 40),
    ];

    final result = engine.analyzeRole(
      role: MantraRole.c,
      availablePlayers: catalog,
      catalogPlayers: catalog,
    );

    expect(result.topCutoffCatalogValue, 80);
    expect(result.catalogTopPlayers, 4);
    expect(result.remainingTopPlayers, 4);
  });

  test('conta separatamente ogni ruolo di un multiruolo', () {
    final candidate = player(
      id: 'multi',
      role: MantraRole.a,
      extraRole: MantraRole.pc,
      basePrice: 50,
    );
    final catalog = [
      candidate,
      player(id: 'a-1', role: MantraRole.a, basePrice: 40),
      player(id: 'pc-1', role: MantraRole.pc, basePrice: 45),
      player(id: 'pc-2', role: MantraRole.pc, basePrice: 30),
    ];

    final result = engine.analyzeCandidate(
      candidate: candidate,
      availablePlayers: catalog,
      catalogPlayers: catalog,
    );

    expect(result, hasLength(2));
    expect(
      result
          .firstWhere((market) => market.role == MantraRole.a)
          .remainingPlayers,
      2,
    );
    expect(
      result
          .firstWhere((market) => market.role == MantraRole.pc)
          .remainingPlayers,
      3,
    );
  });
}

PlayerEntity player({
  required String id,
  required MantraRole role,
  MantraRole? extraRole,
  required int basePrice,
}) {
  return PlayerEntity(
    id: id,
    name: id,
    team: 'TEST',
    roles: [role, ?extraRole],
    basePrice: basePrice,
    expectedGoals: 0,
    expectedAssists: 0,
    expectedGoals90: 0.2,
    expectedAssists90: 0.1,
    expectedYellowCards: 0,
    historicalMinutes: 1800,
    expectedPoints: 50,
    vorp: 5,
  );
}
