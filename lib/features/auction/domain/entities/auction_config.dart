import 'dart:math' as math;

import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionConfig {
  /// Budget reale della lega.
  final int initialCredits;

  /// Budget sul quale è espresso il valore FVM importato.
  /// Il listone Fantacalcio usa come riferimento 1000 crediti.
  final int valuationReferenceCredits;

  final int rosterSize;
  final int minimumBid;
  final Map<MantraRole, int> targetCoverage;

  /// Strategia tattica scelta nel setup.
  final String primaryFormationName;
  final Set<String> secondaryFormationNames;

  /// Piano economico iniziale per reparto.
  final Map<PlayerDepartment, int> departmentBudgets;

  /// Limiti di calibrazione del motore.
  final double maxStrategicPremium;
  final double maxStrategicDiscount;
  final double maxPlayerBudgetShare;

  const AuctionConfig({
    required this.initialCredits,
    required this.rosterSize,
    required this.minimumBid,
    this.valuationReferenceCredits = 1000,
    this.targetCoverage = const {},
    this.primaryFormationName = '4-2-3-1',
    this.secondaryFormationNames = const {'4-3-3', '4-4-2'},
    this.departmentBudgets = const {},
    this.maxStrategicPremium = 0.25,
    this.maxStrategicDiscount = 0.40,
    this.maxPlayerBudgetShare = 0.45,
  }) : assert(initialCredits > 0),
       assert(valuationReferenceCredits > 0),
       assert(rosterSize > 0),
       assert(minimumBid > 0),
       assert(maxStrategicPremium >= 0),
       assert(maxStrategicDiscount >= 0 && maxStrategicDiscount < 1),
       assert(maxPlayerBudgetShare > 0 && maxPlayerBudgetShare <= 1);

  double get valuationScale => initialCredits / valuationReferenceCredits;

  int scaleCatalogValue(int catalogValue) {
    if (catalogValue <= 0) return minimumBid;
    final scaled = (catalogValue * valuationScale).round();
    return math.max(minimumBid, scaled).toInt();
  }

  int get plannedBudgetTotal => departmentBudgets.values.fold(0, (a, b) => a + b);

  bool get isDepartmentBudgetPlanBalanced =>
      departmentBudgets.isNotEmpty && plannedBudgetTotal == initialCredits;

  int departmentBudgetFor(PlayerDepartment department) {
    if (departmentBudgets.isEmpty) {
      return defaultDepartmentBudgets(initialCredits)[department] ?? 0;
    }
    return departmentBudgets[department] ?? 0;
  }

  int get maxPlayerBudget => math.max(
        minimumBid,
        (initialCredits * maxPlayerBudgetShare).round(),
      ).toInt();

  factory AuctionConfig.standardMantra({
    int initialCredits = 500,
    int valuationReferenceCredits = 1000,
    int rosterSize = 25,
    int minimumBid = 1,
    String primaryFormationName = '4-2-3-1',
    Set<String> secondaryFormationNames = const {'4-3-3', '4-4-2'},
    Map<PlayerDepartment, int>? departmentBudgets,
  }) {
    return AuctionConfig(
      initialCredits: initialCredits,
      valuationReferenceCredits: valuationReferenceCredits,
      rosterSize: rosterSize,
      minimumBid: minimumBid,
      primaryFormationName: primaryFormationName,
      secondaryFormationNames: Set.unmodifiable(secondaryFormationNames),
      departmentBudgets: Map.unmodifiable(
        departmentBudgets ?? defaultDepartmentBudgets(initialCredits),
      ),
      targetCoverage: const {
        MantraRole.por: 3,
        MantraRole.dc: 5,
        MantraRole.b: 2,
        MantraRole.dd: 2,
        MantraRole.ds: 2,
        MantraRole.e: 2,
        MantraRole.m: 2,
        MantraRole.c: 3,
        MantraRole.t: 1,
        MantraRole.w: 2,
        MantraRole.a: 1,
        MantraRole.pc: 2,
      },
    );
  }

  static Map<PlayerDepartment, int> defaultDepartmentBudgets(int credits) {
    final goalkeepers = (credits * 0.07).round();
    final defenders = (credits * 0.20).round();
    final midfielders = (credits * 0.31).round();
    final forwards = credits - goalkeepers - defenders - midfielders;

    return {
      PlayerDepartment.goalkeepers: goalkeepers,
      PlayerDepartment.defenders: defenders,
      PlayerDepartment.midfielders: midfielders,
      PlayerDepartment.forwards: forwards,
    };
  }

  AuctionConfig copyWith({
    int? initialCredits,
    int? valuationReferenceCredits,
    int? rosterSize,
    int? minimumBid,
    Map<MantraRole, int>? targetCoverage,
    String? primaryFormationName,
    Set<String>? secondaryFormationNames,
    Map<PlayerDepartment, int>? departmentBudgets,
    double? maxStrategicPremium,
    double? maxStrategicDiscount,
    double? maxPlayerBudgetShare,
  }) {
    return AuctionConfig(
      initialCredits: initialCredits ?? this.initialCredits,
      valuationReferenceCredits:
          valuationReferenceCredits ?? this.valuationReferenceCredits,
      rosterSize: rosterSize ?? this.rosterSize,
      minimumBid: minimumBid ?? this.minimumBid,
      targetCoverage: targetCoverage ?? this.targetCoverage,
      primaryFormationName:
          primaryFormationName ?? this.primaryFormationName,
      secondaryFormationNames:
          secondaryFormationNames ?? this.secondaryFormationNames,
      departmentBudgets: departmentBudgets ?? this.departmentBudgets,
      maxStrategicPremium:
          maxStrategicPremium ?? this.maxStrategicPremium,
      maxStrategicDiscount:
          maxStrategicDiscount ?? this.maxStrategicDiscount,
      maxPlayerBudgetShare:
          maxPlayerBudgetShare ?? this.maxPlayerBudgetShare,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'initial_credits': initialCredits,
      'valuation_reference_credits': valuationReferenceCredits,
      'roster_size': rosterSize,
      'minimum_bid': minimumBid,
      'target_coverage': {
        for (final entry in targetCoverage.entries)
          entry.key.name: entry.value,
      },
      'primary_formation_name': primaryFormationName,
      'secondary_formation_names': secondaryFormationNames.toList(),
      'department_budgets': {
        for (final entry in departmentBudgets.entries)
          entry.key.name: entry.value,
      },
      'max_strategic_premium': maxStrategicPremium,
      'max_strategic_discount': maxStrategicDiscount,
      'max_player_budget_share': maxPlayerBudgetShare,
    };
  }

  factory AuctionConfig.fromJson(Map<String, dynamic> json) {
    final initialCredits = (json['initial_credits'] as num).toInt();
    final rawCoverage = json['target_coverage'];
    final coverage = <MantraRole, int>{};

    if (rawCoverage is Map) {
      for (final entry in rawCoverage.entries) {
        final roleName = entry.key.toString().toLowerCase();
        final roles = MantraRole.values.where((item) => item.name == roleName);
        if (roles.isNotEmpty && entry.value is num) {
          coverage[roles.first] = (entry.value as num).toInt();
        }
      }
    }

    final rawBudgets = json['department_budgets'];
    final budgets = <PlayerDepartment, int>{};
    if (rawBudgets is Map) {
      for (final entry in rawBudgets.entries) {
        final department = PlayerDepartment.values.where(
          (item) => item.name == entry.key.toString(),
        );
        if (department.isNotEmpty && entry.value is num) {
          budgets[department.first] = (entry.value as num).toInt();
        }
      }
    }

    final rawSecondary = json['secondary_formation_names'];
    final secondary = rawSecondary is List
        ? rawSecondary.map((item) => item.toString()).toSet()
        : const {'4-3-3', '4-4-2'};

    return AuctionConfig(
      initialCredits: initialCredits,
      valuationReferenceCredits:
          (json['valuation_reference_credits'] as num?)?.toInt() ?? 1000,
      rosterSize: (json['roster_size'] as num).toInt(),
      minimumBid: (json['minimum_bid'] as num).toInt(),
      targetCoverage: coverage,
      primaryFormationName:
          json['primary_formation_name']?.toString() ?? '4-2-3-1',
      secondaryFormationNames: Set.unmodifiable(secondary),
      departmentBudgets: Map.unmodifiable(
        budgets.isEmpty ? defaultDepartmentBudgets(initialCredits) : budgets,
      ),
      maxStrategicPremium:
          (json['max_strategic_premium'] as num?)?.toDouble() ?? 0.25,
      maxStrategicDiscount:
          (json['max_strategic_discount'] as num?)?.toDouble() ?? 0.40,
      maxPlayerBudgetShare:
          (json['max_player_budget_share'] as num?)?.toDouble() ?? 0.45,
    );
  }
}
