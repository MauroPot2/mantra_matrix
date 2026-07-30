import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

enum StatisticalMetricSource {
  vorp,
  expectedPoints,
  adjustedPer90,
  insufficientData,
}

enum StatisticalQualityBand {
  belowAverage,
  average,
  slightlyAboveAverage,
  goodAdvantage,
  strongAdvantage,
  elite,
}

class StatisticalEvidence {
  final MantraRole comparisonRole;
  final StatisticalMetricSource metricSource;
  final StatisticalQualityBand qualityBand;
  final double percentile;
  final int peerCount;
  final int historicalMinutes;
  final double sampleReliability;
  final double dataCompleteness;
  final double peerGroupReliability;
  final double overallReliability;
  final double qualityMultiplier;
  final double rawScore;
  final double adjustedScore;
  final List<String> strengths;
  final List<String> caveats;

  const StatisticalEvidence({
    required this.comparisonRole,
    required this.metricSource,
    required this.qualityBand,
    required this.percentile,
    required this.peerCount,
    required this.historicalMinutes,
    required this.sampleReliability,
    required this.dataCompleteness,
    required this.peerGroupReliability,
    required this.overallReliability,
    required this.qualityMultiplier,
    required this.rawScore,
    required this.adjustedScore,
    this.strengths = const [],
    this.caveats = const [],
  });

  int get percentileRounded => (percentile * 100).round();

  String get metricSourceLabel => switch (metricSource) {
        StatisticalMetricSource.vorp => 'VORP',
        StatisticalMetricSource.expectedPoints => 'Punti attesi',
        StatisticalMetricSource.adjustedPer90 => 'xG/xA per 90 corretti',
        StatisticalMetricSource.insufficientData => 'Dati insufficienti',
      };

  String get qualityLabel => switch (qualityBand) {
        StatisticalQualityBand.belowAverage => 'Sotto la media',
        StatisticalQualityBand.average => 'In linea con i comparabili',
        StatisticalQualityBand.slightlyAboveAverage =>
          'Leggermente sopra la media',
        StatisticalQualityBand.goodAdvantage => 'Buon vantaggio statistico',
        StatisticalQualityBand.strongAdvantage => 'Vantaggio statistico forte',
        StatisticalQualityBand.elite => 'Profilo statistico élite',
      };

  String get reliabilityLabel {
    if (overallReliability >= 0.85) return 'Alta';
    if (overallReliability >= 0.68) return 'Buona';
    if (overallReliability >= 0.50) return 'Media';
    return 'Bassa';
  }
}
