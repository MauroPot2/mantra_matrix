import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';

void main() {
  test('serializza e ripristina strategia tattica e budget reparto', () {
    final original = AuctionConfig.standardMantra(
      initialCredits: 500,
      primaryFormationName: '4-3-3',
      secondaryFormationNames: const {'4-2-3-1', '4-4-2'},
      departmentBudgets: const {
        PlayerDepartment.goalkeepers: 30,
        PlayerDepartment.defenders: 105,
        PlayerDepartment.midfielders: 160,
        PlayerDepartment.forwards: 205,
      },
    );

    final restored = AuctionConfig.fromJson(original.toJson());

    expect(restored.primaryFormationName, '4-3-3');
    expect(restored.secondaryFormationNames, {'4-2-3-1', '4-4-2'});
    expect(restored.departmentBudgetFor(PlayerDepartment.goalkeepers), 30);
    expect(restored.departmentBudgetFor(PlayerDepartment.forwards), 205);
    expect(restored.plannedBudgetTotal, 500);
    expect(restored.isDepartmentBudgetPlanBalanced, isTrue);
    expect(restored.bidExtensionSeconds, 5);
  });

  test('una configurazione legacy riceve budget e moduli predefiniti', () {
    final restored = AuctionConfig.fromJson({
      'initial_credits': 500,
      'valuation_reference_credits': 1000,
      'roster_size': 25,
      'minimum_bid': 1,
      'target_coverage': <String, int>{},
    });

    expect(restored.primaryFormationName, '4-2-3-1');
    expect(restored.secondaryFormationNames, contains('4-3-3'));
    expect(restored.plannedBudgetTotal, 500);
    expect(restored.bidExtensionSeconds, 0);
  });

  test(
    'una configurazione temporizzata esistente riceve la proroga standard',
    () {
      final restored = AuctionConfig.fromJson({
        'initial_credits': 500,
        'roster_size': 25,
        'minimum_bid': 1,
        'bid_duration_seconds': 30,
      });

      expect(restored.bidDurationSeconds, 30);
      expect(restored.bidExtensionSeconds, 5);
    },
  );
}
