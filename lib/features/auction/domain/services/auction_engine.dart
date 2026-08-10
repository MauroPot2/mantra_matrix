import 'dart:math' as math;

import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/entities/mantra_formation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/role_market_availability.dart';
import 'package:mantra_matrix/features/auction/domain/services/formation_engine.dart';
import 'package:mantra_matrix/features/auction/domain/services/role_market_engine.dart';
import 'package:mantra_matrix/features/auction/domain/services/statistical_evidence_engine.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionEngine {
  final FormationEngine formationEngine;
  final StatisticalEvidenceEngine statisticalEvidenceEngine;
  final RoleMarketEngine roleMarketEngine;

  const AuctionEngine({
    this.formationEngine = const FormationEngine(),
    this.statisticalEvidenceEngine = const StatisticalEvidenceEngine(),
    this.roleMarketEngine = const RoleMarketEngine(),
  });

  AuctionRecommendation evaluate({
    required PlayerEntity player,
    required FantasyTeamEntity myTeam,
    required AuctionConfig config,
    required List<PlayerEntity> availablePlayers,
    required int currentBid,
    List<PlayerEntity>? catalogPlayers,
  }) {
    if (currentBid < config.minimumBid) {
      throw ArgumentError.value(
        currentBid,
        'currentBid',
        'Non può essere inferiore all’offerta minima',
      );
    }

    final catalog = catalogPlayers ?? availablePlayers;
    final hardCeiling = myTeam.maxAffordableBid(config);
    final scaledCatalogValue = config.scaleCatalogValue(player.basePrice);
    final department = PlayerDepartmentX.forPlayer(player);
    final departmentBudget = config.departmentBudgetFor(department);
    final departmentSpent = _departmentSpent(myTeam, department);
    final departmentBudgetCeiling = math
        .max(config.minimumBid, departmentBudget - departmentSpent)
        .toInt();

    if (player.status != DraftStatus.available) {
      return AuctionRecommendation(
        playerId: player.id,
        decision: AuctionDecision.unavailable,
        risk: AuctionRisk.critical,
        scaledCatalogValue: scaledCatalogValue,
        fairValue: 0,
        maxBid: 0,
        hardBudgetCeiling: hardCeiling,
        department: department,
        departmentBudget: departmentBudget,
        departmentSpent: departmentSpent,
        departmentBudgetCeiling: departmentBudgetCeiling,
        confidence: 1,
        reasons: const ['Il giocatore non è disponibile.'],
        warnings: const ['Non effettuare rilanci.'],
        factors: const [],
      );
    }

    final evidence = statisticalEvidenceEngine.analyze(
      player: player,
      catalogPlayers: catalog,
    );
    final roleMarkets = roleMarketEngine.analyzeCandidate(
      candidate: player,
      availablePlayers: availablePlayers,
      catalogPlayers: catalog,
    );
    final formationImpact = formationEngine.analyzePlayerImpact(
      roster: myTeam.roster,
      candidate: player,
      primaryFormationName: config.primaryFormationName,
      secondaryFormationNames: config.secondaryFormationNames,
    );

    final factors = <RecommendationFactor>[];
    final reasons = <String>[];
    final warnings = <String>[];

    final roleNeed = _roleNeedMultiplier(player, myTeam, config);
    factors.add(
      RecommendationFactor(
        key: 'role_need',
        label: 'Bisogno rosa',
        multiplier: roleNeed,
        explanation: roleNeed > 1
            ? 'Copre almeno un ruolo ancora sotto obiettivo.'
            : 'I suoi ruoli sono già coperti dalla rosa.',
      ),
    );

    final scarcity = _scarcityMultiplier(roleMarkets);
    factors.add(
      RecommendationFactor(
        key: 'scarcity',
        label: 'Scarsità mercato',
        multiplier: scarcity,
        explanation: _scarcityExplanation(roleMarkets),
      ),
    );

    final quality = evidence.qualityMultiplier;
    factors.add(
      RecommendationFactor(
        key: 'relative_quality',
        label: 'Qualità relativa',
        multiplier: quality,
        explanation:
            '${evidence.qualityLabel} · ${evidence.percentileRounded}° percentile.',
      ),
    );

    final versatility = _versatilityMultiplier(player);
    factors.add(
      RecommendationFactor(
        key: 'versatility',
        label: 'Polivalenza',
        multiplier: versatility,
        explanation: player.roles.length > 1
            ? 'Copre ${player.roles.length} ruoli Mantra.'
            : 'Copre un solo ruolo Mantra.',
      ),
    );

    final tacticalImpact = _tacticalImpactMultiplier(
      formationImpact,
      rosterProgress: myTeam.roster.length / config.rosterSize,
    );
    factors.add(
      RecommendationFactor(
        key: 'tactical_impact',
        label: 'Impatto tattico',
        multiplier: tacticalImpact,
        explanation: _tacticalExplanation(
          formationImpact,
          config.primaryFormationName,
        ),
      ),
    );

    final specialist = _specialistMultiplier(player);
    factors.add(
      RecommendationFactor(
        key: 'specialist',
        label: 'Specialista',
        multiplier: specialist,
        explanation: player.isPenaltyTaker
            ? 'Rigorista indicato nel dataset.'
            : player.isFreeKickTaker
            ? 'Specialista sui calci piazzati.'
            : 'Nessun bonus specialista rilevato.',
      ),
    );

    final reliability = _reliabilityMultiplier(
      player,
      evidence.overallReliability,
    );
    factors.add(
      RecommendationFactor(
        key: 'reliability',
        label: 'Affidabilità dati',
        multiplier: reliability,
        explanation:
            '${evidence.reliabilityLabel} · ${evidence.historicalMinutes} minuti nel campione.',
      ),
    );

    final rawStrategicAdjustment =
        ((roleNeed - 1) * 0.80) +
        ((scarcity - 1) * 0.70) +
        ((quality - 1) * 0.90) +
        ((versatility - 1) * 0.50) +
        ((tacticalImpact - 1) * 1.00) +
        ((specialist - 1) * 0.50);

    final rosterProgress = (myTeam.roster.length / config.rosterSize)
        .clamp(0.0, 1.0)
        .toDouble();
    final positiveSignalWeight = 0.25 + (rosterProgress * 0.75);
    final phasedAdjustment = rawStrategicAdjustment > 0
        ? rawStrategicAdjustment * positiveSignalWeight
        : rawStrategicAdjustment;
    final strategicAdjustment = phasedAdjustment
        .clamp(-config.maxStrategicDiscount, config.maxStrategicPremium)
        .toDouble();

    final calibratedValue = scaledCatalogValue * (1 + strategicAdjustment);
    final fairValue = math
        .max(config.minimumBid, (calibratedValue * reliability).round())
        .toInt();
    var maxBid = fairValue;
    maxBid = math.min(maxBid, hardCeiling).toInt();
    maxBid = math.min(maxBid, departmentBudgetCeiling).toInt();
    maxBid = math.min(maxBid, config.maxPlayerBudget).toInt();

    if (roleNeed > 1.02) {
      reasons.add('Copre un bisogno attuale della rosa.');
    }
    if (formationImpact.primaryUnlocked) {
      reasons.add('Rende schierabile il ${config.primaryFormationName}.');
    } else if (formationImpact.primaryMissingReduction > 0) {
      reasons.add(
        'Avvicina il modulo principale ${config.primaryFormationName}.',
      );
    }
    if (formationImpact.secondaryUnlockedCount > 0) {
      reasons.add(
        'Sblocca ${formationImpact.secondaryUnlockedCount} modulo/i alternativo/i.',
      );
    }
    if (evidence.percentile >= 0.75) {
      reasons.add(
        '${evidence.qualityLabel} tra i ${evidence.peerCount} comparabili.',
      );
    }
    final scarceTopRoles = roleMarkets
        .where(
          (market) =>
              market.candidateIsTop && market.remainingTopAlternatives <= 2,
        )
        .map((market) => market.role.name.toUpperCase())
        .toList(growable: false);
    if (scarceTopRoles.isNotEmpty) {
      reasons.add(
        'Pochi top alternativi rimasti in ${scarceTopRoles.join('/')}.',
      );
    }
    if (player.isPenaltyTaker) reasons.add('È indicato come rigorista.');

    warnings.addAll(evidence.caveats);
    if (player.isInjured) warnings.add('Il giocatore risulta infortunato.');
    if (player.isSuspended) warnings.add('Il giocatore risulta squalificato.');
    if (fairValue > hardCeiling) {
      warnings.add(
        'Il valore supera il tetto necessario per completare la rosa.',
      );
    }
    if (fairValue > departmentBudgetCeiling) {
      warnings.add(
        'Il piano ${department.shortLabel} consente ancora $departmentBudgetCeiling crediti.',
      );
    }
    if (fairValue > config.maxPlayerBudget) {
      warnings.add(
        'Applicato il limite del ${(config.maxPlayerBudgetShare * 100).round()}% del budget iniziale.',
      );
    }

    final decision = _decisionFor(
      currentBid: currentBid,
      maxBid: maxBid,
      roleNeedMultiplier: roleNeed,
      tacticalImpactMultiplier: tacticalImpact,
      roleMarkets: roleMarkets,
    );
    final risk = _riskFor(
      currentBid: currentBid,
      maxBid: maxBid,
      player: player,
      confidence: evidence.overallReliability,
    );

    return AuctionRecommendation(
      playerId: player.id,
      decision: decision,
      risk: risk,
      scaledCatalogValue: scaledCatalogValue,
      fairValue: fairValue,
      maxBid: maxBid,
      hardBudgetCeiling: hardCeiling,
      department: department,
      departmentBudget: departmentBudget,
      departmentSpent: departmentSpent,
      departmentBudgetCeiling: departmentBudgetCeiling,
      strategicAdjustment: strategicAdjustment,
      confidence: evidence.overallReliability,
      reasons: reasons.isEmpty
          ? const [
              'Valutazione coerente con FVM, dati e composizione della rosa.',
            ]
          : List.unmodifiable(reasons),
      warnings: List.unmodifiable(warnings.toSet()),
      factors: List.unmodifiable(factors),
      statisticalEvidence: evidence,
      roleMarkets: List.unmodifiable(roleMarkets),
    );
  }

  int _departmentSpent(FantasyTeamEntity team, PlayerDepartment department) {
    return team.roster
        .where((player) => PlayerDepartmentX.forPlayer(player) == department)
        .fold(0, (sum, player) => sum + (player.purchasePrice ?? 0));
  }

  double _roleNeedMultiplier(
    PlayerEntity player,
    FantasyTeamEntity team,
    AuctionConfig config,
  ) {
    var highestNeedRatio = 0.0;
    for (final role in player.roles) {
      final target = config.targetCoverage[role] ?? 0;
      if (target <= 0) continue;
      highestNeedRatio = math.max(
        highestNeedRatio,
        team.missingCoverageFor(role, config) / target,
      );
    }
    if (highestNeedRatio == 0) return 0.97;
    return (1 + (highestNeedRatio * 0.10)).clamp(1.0, 1.10).toDouble();
  }

  double _scarcityMultiplier(List<RoleMarketAvailability> markets) {
    if (markets.isEmpty) return 1.0;
    var multiplier = 0.99;
    for (final market in markets) {
      var candidateValue = 1.0;
      if (market.candidateIsTop && market.remainingTopAlternatives <= 1) {
        candidateValue = 1.08;
      } else if (market.candidateIsTop &&
          market.remainingTopAlternatives <= 3) {
        candidateValue = 1.05;
      } else if (market.remainingAlternatives <= 5) {
        candidateValue = 1.04;
      } else if (market.remainingAlternatives <= 10) {
        candidateValue = 1.02;
      }
      multiplier = math.max(multiplier, candidateValue);
    }
    return multiplier;
  }

  String _scarcityExplanation(List<RoleMarketAvailability> markets) {
    if (markets.isEmpty) return 'Mercato del ruolo non disponibile.';
    final mostScarce = markets.reduce((a, b) {
      if (a.remainingTopAlternatives != b.remainingTopAlternatives) {
        return a.remainingTopAlternatives < b.remainingTopAlternatives ? a : b;
      }
      return a.remainingAlternatives < b.remainingAlternatives ? a : b;
    });
    return '${mostScarce.role.name.toUpperCase()}: '
        '${mostScarce.remainingAlternatives} alternative, '
        '${mostScarce.remainingTopAlternatives} top alternative.';
  }

  double _versatilityMultiplier(PlayerEntity player) {
    if (player.polyvalenceMultiplier != 1.0) {
      return player.polyvalenceMultiplier.clamp(0.95, 1.06).toDouble();
    }
    return (1 + ((player.roles.length - 1) * 0.025))
        .clamp(1.0, 1.06)
        .toDouble();
  }

  double _tacticalImpactMultiplier(
    FormationImpact impact, {
    required double rosterProgress,
  }) {
    if (impact.primaryUnlocked) return 1.10;
    if (impact.secondaryUnlockedCount > 0) return 1.06;
    if (impact.primaryMissingReduction > 0) return 1.05;
    if (impact.secondaryMissingReduction > 0) return 1.03;
    if (impact.improvesAnything) return 1.02;
    return rosterProgress >= 0.40 ? 0.98 : 1.0;
  }

  String _tacticalExplanation(FormationImpact impact, String primary) {
    if (impact.primaryUnlocked) return 'Sblocca il modulo principale $primary.';
    if (impact.secondaryUnlockedCount > 0) {
      return 'Sblocca ${impact.secondaryUnlockedCount} modulo/i alternativo/i.';
    }
    if (impact.primaryMissingReduction > 0) {
      return 'Riduce di ${impact.primaryMissingReduction} gli slot mancanti nel $primary.';
    }
    if (impact.improvedFormationNames.isNotEmpty) {
      final preview = impact.improvedFormationNames.take(3).join(', ');
      return 'Migliora la costruzione di $preview.';
    }
    return 'Non migliora i moduli con la rosa attuale.';
  }

  double _specialistMultiplier(PlayerEntity player) {
    var multiplier = 1.0;
    if (player.isPenaltyTaker) multiplier += 0.03;
    if (player.isFreeKickTaker) multiplier += 0.01;
    return multiplier.clamp(1.0, 1.04).toDouble();
  }

  double _reliabilityMultiplier(PlayerEntity player, double confidence) {
    var multiplier = 0.82 + (confidence.clamp(0.0, 1.0) * 0.18);
    if (player.isInjured) multiplier *= 0.78;
    if (player.isSuspended) multiplier *= 0.90;
    return multiplier.clamp(0.55, 1.0).toDouble();
  }

  AuctionDecision _decisionFor({
    required int currentBid,
    required int maxBid,
    required double roleNeedMultiplier,
    required double tacticalImpactMultiplier,
    required List<RoleMarketAvailability> roleMarkets,
  }) {
    if (maxBid <= 0 || currentBid > maxBid) return AuctionDecision.pass;
    final scarceTop = roleMarkets.any(
      (market) => market.candidateIsTop && market.remainingTopAlternatives <= 2,
    );
    if (currentBid <= maxBid * 0.65 &&
        (roleNeedMultiplier > 1.03 ||
            tacticalImpactMultiplier > 1.03 ||
            scarceTop)) {
      return AuctionDecision.strongBuy;
    }
    if (currentBid <= maxBid * 0.85) return AuctionDecision.buy;
    return AuctionDecision.wait;
  }

  AuctionRisk _riskFor({
    required int currentBid,
    required int maxBid,
    required PlayerEntity player,
    required double confidence,
  }) {
    if (maxBid <= 0 || currentBid > maxBid) return AuctionRisk.critical;
    if (player.isInjured || currentBid >= maxBid) return AuctionRisk.high;
    if (currentBid >= maxBid * 0.85 || confidence < 0.50) {
      return AuctionRisk.medium;
    }
    return AuctionRisk.low;
  }
}
