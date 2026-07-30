import 'package:mantra_matrix/features/auction/domain/entities/statistical_evidence.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class StatisticalEvidenceEngine {
  const StatisticalEvidenceEngine();

  StatisticalEvidence analyze({
    required PlayerEntity player,
    required List<PlayerEntity> catalogPlayers,
  }) {
    final comparisonRole = player.roles.first;
    final group = _uniquePlayers(catalogPlayers)
        .where((candidate) => candidate.roles.contains(comparisonRole))
        .toList();

    if (group.every((candidate) => candidate.id != player.id)) {
      group.add(player);
    }

    final source = _selectMetricSource(player, group);
    final rawScores = <String, double>{
      for (final candidate in group)
        candidate.id: _rawScore(candidate, source),
    };
    final roleMean = rawScores.isEmpty
        ? 0.0
        : rawScores.values.reduce((a, b) => a + b) / rawScores.length;

    final adjustedScores = <String, double>{};
    for (final candidate in group) {
      final raw = rawScores[candidate.id] ?? 0;
      adjustedScores[candidate.id] = _adjustScore(
        candidate: candidate,
        source: source,
        rawScore: raw,
        roleMean: roleMean,
      );
    }

    final rawScore = rawScores[player.id] ?? 0;
    final adjustedScore = adjustedScores[player.id] ?? rawScore;
    final percentile = _percentile(
      playerId: player.id,
      playerScore: adjustedScore,
      scores: adjustedScores,
    );
    final peerCount = group.length > 1 ? group.length - 1 : 0;
    final sampleReliability = (player.historicalMinutes / 1800)
        .clamp(0.0, 1.0)
        .toDouble();
    final completeness = _dataCompleteness(player, source);
    final peerReliability = (peerCount / 20).clamp(0.0, 1.0).toDouble();
    var overallReliability = (
      (sampleReliability * 0.45) +
      (completeness * 0.30) +
      (peerReliability * 0.25)
    ).clamp(0.0, 1.0).toDouble();
    if (peerCount < 3) {
      overallReliability = overallReliability.clamp(0.0, 0.45).toDouble();
    } else if (peerCount < 8) {
      overallReliability = overallReliability.clamp(0.0, 0.65).toDouble();
    }
    if (source == StatisticalMetricSource.insufficientData) {
      overallReliability = overallReliability.clamp(0.0, 0.35).toDouble();
    }
    final qualityBand = _qualityBand(percentile);
    final qualityMultiplier = (1 + ((percentile - 0.50) * 0.16))
        .clamp(0.92, 1.08)
        .toDouble();

    final strengths = <String>[];
    final caveats = <String>[];

    if (percentile >= 0.85) {
      strengths.add(
        'È nel ${(percentile * 100).round()}° percentile del gruppo di confronto.',
      );
    }
    if (sampleReliability >= 0.85) {
      strengths.add('Il minutaggio offre un campione ampio.');
    }
    if (source == StatisticalMetricSource.vorp ||
        source == StatisticalMetricSource.expectedPoints) {
      strengths.add('Il confronto usa una metrica aggregata omogenea.');
    }

    if (player.historicalMinutes < 900) {
      caveats.add(
        'Campione ridotto: le metriche per 90 sono state avvicinate alla media del ruolo.',
      );
    } else if (player.historicalMinutes < 1500) {
      caveats.add('Campione intermedio: interpretare il percentile con prudenza.');
    }
    if (peerCount < 8) {
      caveats.add('Gruppo di confronto piccolo: percentile poco stabile.');
    }
    if (source == StatisticalMetricSource.adjustedPer90) {
      caveats.add(
        'VORP e punti attesi non sono abbastanza completi: confronto basato su xG/xA per 90 corretti.',
      );
    }
    if (source == StatisticalMetricSource.insufficientData) {
      caveats.add('Dati insufficienti per un confronto statistico robusto.');
    }

    return StatisticalEvidence(
      comparisonRole: comparisonRole,
      metricSource: source,
      qualityBand: qualityBand,
      percentile: percentile,
      peerCount: peerCount,
      historicalMinutes: player.historicalMinutes,
      sampleReliability: sampleReliability,
      dataCompleteness: completeness,
      peerGroupReliability: peerReliability,
      overallReliability: overallReliability,
      qualityMultiplier: qualityMultiplier,
      rawScore: rawScore,
      adjustedScore: adjustedScore,
      strengths: List.unmodifiable(strengths),
      caveats: List.unmodifiable(caveats),
    );
  }

  StatisticalMetricSource _selectMetricSource(
    PlayerEntity player,
    List<PlayerEntity> group,
  ) {
    if (group.isEmpty) return StatisticalMetricSource.insufficientData;

    final vorpCoverage = group.where((candidate) => candidate.vorp != 0).length /
        group.length;
    if (player.vorp != 0 && vorpCoverage >= 0.70) {
      return StatisticalMetricSource.vorp;
    }

    final expectedPointsCoverage = group
            .where((candidate) => candidate.expectedPoints != 0)
            .length /
        group.length;
    if (player.expectedPoints != 0 && expectedPointsCoverage >= 0.70) {
      return StatisticalMetricSource.expectedPoints;
    }

    final hasPer90 = player.expectedGoals90 != 0 ||
        player.expectedAssists90 != 0 ||
        player.expectedCleanSheets != 0 ||
        player.expectedGoalsConceded != 0;
    if (hasPer90) return StatisticalMetricSource.adjustedPer90;

    return StatisticalMetricSource.insufficientData;
  }

  double _rawScore(
    PlayerEntity player,
    StatisticalMetricSource source,
  ) {
    return switch (source) {
      StatisticalMetricSource.vorp => player.vorp,
      StatisticalMetricSource.expectedPoints => player.expectedPoints,
      StatisticalMetricSource.adjustedPer90 => _per90Score(player),
      StatisticalMetricSource.insufficientData => 0,
    };
  }

  double _per90Score(PlayerEntity player) {
    if (player.roles.contains(MantraRole.por)) {
      return (player.expectedCleanSheets * 2) -
          (player.expectedGoalsConceded * 0.35);
    }
    return (player.expectedGoals90 * 3) +
        (player.expectedAssists90 * 1.75);
  }

  double _adjustScore({
    required PlayerEntity candidate,
    required StatisticalMetricSource source,
    required double rawScore,
    required double roleMean,
  }) {
    if (source != StatisticalMetricSource.adjustedPer90) return rawScore;

    final sampleWeight = (candidate.historicalMinutes / 1800)
        .clamp(0.0, 1.0)
        .toDouble();
    return (rawScore * sampleWeight) + (roleMean * (1 - sampleWeight));
  }

  double _percentile({
    required String playerId,
    required double playerScore,
    required Map<String, double> scores,
  }) {
    if (scores.length < 2) return 0.50;

    var lower = 0;
    var equal = 0;
    for (final entry in scores.entries) {
      if (entry.key == playerId) continue;
      final difference = entry.value - playerScore;
      if (difference < -0.000001) {
        lower++;
      } else if (difference.abs() <= 0.000001) {
        equal++;
      }
    }

    final peers = scores.length - 1;
    return ((lower + (equal * 0.5)) / peers).clamp(0.0, 1.0).toDouble();
  }

  double _dataCompleteness(
    PlayerEntity player,
    StatisticalMetricSource source,
  ) {
    final checks = <bool>[
      player.basePrice > 0,
      player.historicalMinutes > 0,
      player.team.trim().isNotEmpty,
      player.roles.isNotEmpty,
      source != StatisticalMetricSource.insufficientData,
      player.expectedGoals90 != 0 ||
          player.expectedAssists90 != 0 ||
          player.expectedPoints != 0 ||
          player.vorp != 0 ||
          player.expectedCleanSheets != 0 ||
          player.expectedGoalsConceded != 0,
    ];
    return checks.where((value) => value).length / checks.length;
  }

  StatisticalQualityBand _qualityBand(double percentile) {
    if (percentile < 0.40) return StatisticalQualityBand.belowAverage;
    if (percentile < 0.60) return StatisticalQualityBand.average;
    if (percentile < 0.75) {
      return StatisticalQualityBand.slightlyAboveAverage;
    }
    if (percentile < 0.85) return StatisticalQualityBand.goodAdvantage;
    if (percentile < 0.95) return StatisticalQualityBand.strongAdvantage;
    return StatisticalQualityBand.elite;
  }

  Iterable<PlayerEntity> _uniquePlayers(List<PlayerEntity> players) {
    final byId = <String, PlayerEntity>{};
    for (final player in players) {
      byId[player.id] = player;
    }
    return byId.values;
  }
}
