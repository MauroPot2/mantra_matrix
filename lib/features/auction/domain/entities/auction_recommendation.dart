import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/auction/domain/entities/role_market_availability.dart';
import 'package:mantra_matrix/features/auction/domain/entities/statistical_evidence.dart';

enum AuctionDecision { strongBuy, buy, wait, pass, unavailable }

enum AuctionRisk { low, medium, high, critical }

class RecommendationFactor {
  final String key;
  final String label;
  final double multiplier;
  final String explanation;

  const RecommendationFactor({
    required this.key,
    required this.label,
    required this.multiplier,
    required this.explanation,
  });
}

class AuctionRecommendation {
  final String playerId;
  final AuctionDecision decision;
  final AuctionRisk risk;
  final int scaledCatalogValue;
  final int fairValue;
  final int maxBid;
  final int hardBudgetCeiling;
  final PlayerDepartment? department;
  final int departmentBudget;
  final int departmentSpent;
  final int departmentBudgetCeiling;
  final double strategicAdjustment;
  final double confidence;
  final List<String> reasons;
  final List<String> warnings;
  final List<RecommendationFactor> factors;
  final StatisticalEvidence? statisticalEvidence;
  final List<RoleMarketAvailability> roleMarkets;

  const AuctionRecommendation({
    required this.playerId,
    required this.decision,
    required this.risk,
    this.scaledCatalogValue = 0,
    required this.fairValue,
    required this.maxBid,
    required this.hardBudgetCeiling,
    this.department,
    this.departmentBudget = 0,
    this.departmentSpent = 0,
    this.departmentBudgetCeiling = 0,
    this.strategicAdjustment = 0,
    required this.confidence,
    required this.reasons,
    required this.warnings,
    required this.factors,
    this.statisticalEvidence,
    this.roleMarkets = const [],
  });
}
