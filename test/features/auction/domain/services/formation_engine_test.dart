import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/services/formation_engine.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const engine = FormationEngine();

  test('espone gli undici moduli ufficiali con undici slot', () {
    expect(FormationEngine.officialFormations, hasLength(11));
    expect(
      FormationEngine.officialFormations.every(
        (formation) => formation.requiredPlayers == 11,
      ),
      isTrue,
    );
  });

  test('riconosce un 4-2-3-1 completo senza contare due volte i giocatori', () {
    final roster = [
      p('por', MantraRole.por),
      p('dd', MantraRole.dd),
      p('dc1', MantraRole.dc),
      p('dc2', MantraRole.dc),
      p('ds', MantraRole.ds),
      p('m1', MantraRole.m),
      p('mc', MantraRole.m, extra: MantraRole.c),
      p('wt', MantraRole.w, extra: MantraRole.t),
      p('t', MantraRole.t),
      p('wa', MantraRole.w, extra: MantraRole.a),
      p('pc', MantraRole.pc),
    ];

    final formation = FormationEngine.officialFormations.firstWhere(
      (item) => item.name == '4-2-3-1',
    );
    final analysis = engine.analyzeFormation(formation, roster);

    expect(analysis.isPlayable, isTrue);
    expect(analysis.missingSlots, 0);
  });

  test('un solo M/C non può riempire contemporaneamente due slot', () {
    final roster = [
      p('por', MantraRole.por),
      p('dd', MantraRole.dd),
      p('dc1', MantraRole.dc),
      p('dc2', MantraRole.dc),
      p('ds', MantraRole.ds),
      p('mc', MantraRole.m, extra: MantraRole.c),
      p('wt', MantraRole.w, extra: MantraRole.t),
      p('t', MantraRole.t),
      p('wa', MantraRole.w, extra: MantraRole.a),
      p('pc', MantraRole.pc),
    ];

    final formation = FormationEngine.officialFormations.firstWhere(
      (item) => item.name == '4-2-3-1',
    );
    final analysis = engine.analyzeFormation(formation, roster);

    expect(analysis.isPlayable, isFalse);
    expect(analysis.missingSlots, 1);
  });

  test('il ruolo B copre DC/B ma non uno slot DC puro', () {
    final roster = [
      p('por', MantraRole.por),
      p('dc1', MantraRole.dc),
      p('dc2', MantraRole.dc),
      p('b', MantraRole.b),
      p('e1', MantraRole.e),
      p('mc', MantraRole.m, extra: MantraRole.c),
      p('c', MantraRole.c),
      p('e2', MantraRole.e),
      p('wa1', MantraRole.w, extra: MantraRole.a),
      p('pc', MantraRole.pc),
      p('wa2', MantraRole.w, extra: MantraRole.a),
    ];

    final formation = FormationEngine.officialFormations.firstWhere(
      (item) => item.name == '3-4-3',
    );

    expect(engine.analyzeFormation(formation, roster).isPlayable, isTrue);
  });
}

PlayerEntity p(String id, MantraRole role, {MantraRole? extra}) {
  return PlayerEntity(
    id: id,
    name: id,
    team: 'TEST',
    roles: [role, ?extra],
    basePrice: 1,
    expectedGoals: 0,
    expectedAssists: 0,
    expectedGoals90: 0,
    expectedAssists90: 0,
    expectedYellowCards: 0,
    historicalMinutes: 0,
  );
}
