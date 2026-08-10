import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/statistical_evidence.dart';
import 'package:mantra_matrix/features/auction/domain/services/statistical_evidence_engine.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const engine = StatisticalEvidenceEngine();

  test('espone percentile, comparabili e affidabilità del campione', () {
    final target = player(id: 'target', vorp: 9, minutes: 2400);
    final catalog = [
      target,
      for (var index = 1; index <= 9; index++)
        player(id: 'peer-$index', vorp: index.toDouble(), minutes: 2200),
    ];

    final result = engine.analyze(player: target, catalogPlayers: catalog);

    expect(result.metricSource, StatisticalMetricSource.vorp);
    expect(result.peerCount, 9);
    expect(result.percentile, greaterThanOrEqualTo(0.85));
    expect(result.qualityBand, StatisticalQualityBand.strongAdvantage);
    expect(result.overallReliability, greaterThan(0.75));
  });

  test('riduce verso la media le metriche per 90 su pochi minuti', () {
    final target = player(
      id: 'target',
      vorp: 0,
      expectedPoints: 0,
      minutes: 180,
      xG90: 1.2,
    );
    final catalog = [
      target,
      for (var index = 0; index < 9; index++)
        player(
          id: 'peer-$index',
          vorp: 0,
          expectedPoints: 0,
          minutes: 1800,
          xG90: 0.2,
        ),
    ];

    final result = engine.analyze(player: target, catalogPlayers: catalog);

    expect(result.metricSource, StatisticalMetricSource.adjustedPer90);
    expect(result.adjustedScore, lessThan(result.rawScore));
    expect(result.sampleReliability, 0.1);
    expect(result.caveats, isNotEmpty);
  });

  test('non definisce forte un semplice profilo appena sopra la media', () {
    final target = player(id: 'target', vorp: 6, minutes: 2200);
    final catalog = [
      target,
      for (var index = 1; index <= 10; index++)
        player(id: 'peer-$index', vorp: index.toDouble(), minutes: 2200),
    ];

    final result = engine.analyze(player: target, catalogPlayers: catalog);

    expect(result.percentile, inInclusiveRange(0.45, 0.65));
    expect(result.qualityBand, isNot(StatisticalQualityBand.strongAdvantage));
  });
}

PlayerEntity player({
  required String id,
  double vorp = 5,
  double expectedPoints = 50,
  int minutes = 1800,
  double xG90 = 0.3,
}) {
  return PlayerEntity(
    id: id,
    name: id,
    team: 'TEST',
    roles: const [MantraRole.pc],
    basePrice: 20,
    expectedGoals: 0,
    expectedAssists: 0,
    expectedGoals90: xG90,
    expectedAssists90: 0.1,
    expectedYellowCards: 0,
    historicalMinutes: minutes,
    expectedPoints: expectedPoints,
    vorp: vorp,
  );
}
