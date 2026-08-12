import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  group('PlayerModel migration', () {
    test('reads legacy fvm but marks record as legacy catalog', () {
      final player = PlayerModel.fromJson({
        'id': 'legacy-1',
        'name': 'Legacy Player',
        'team': 'TEST',
        'roles': 'DC;B',
        'fvm': 42,
        'minutes': 900,
      });

      expect(player.basePrice, 42);
      expect(player.dataOrigin, PlayerDataOrigin.legacyCatalog);
    });

    test('new serialization writes base_price and never writes fvm', () {
      final player = PlayerModel(
        id: 'matrix-1',
        name: 'Matrix Player',
        team: 'TEST',
        roles: const [MantraRole.dc, MantraRole.b],
        basePrice: 12,
        dataOrigin: PlayerDataOrigin.matrix,
        expectedGoals: 1.2,
        expectedAssists: 0.7,
        expectedGoals90: 0.1,
        expectedAssists90: 0.06,
        expectedYellowCards: 3,
        historicalMinutes: 1100,
      );

      final json = player.toJson();

      expect(json['base_price'], 12);
      expect(json.containsKey('fvm'), isFalse);
      expect(json['data_origin'], PlayerDataOrigin.matrix.name);
    });

    test('round trip preserves user import provenance', () {
      final original = PlayerModel(
        id: 'import-1',
        name: 'Imported Player',
        team: 'TEST',
        roles: const [MantraRole.c, MantraRole.t],
        basePrice: 1,
        dataOrigin: PlayerDataOrigin.userImport,
        sourceLabel: 'csv-import',
        expectedGoals: 0,
        expectedAssists: 0,
        expectedGoals90: 0,
        expectedAssists90: 0,
        expectedYellowCards: 0,
        historicalMinutes: 0,
      );

      final restored = PlayerModel.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.roles, original.roles);
      expect(restored.dataOrigin, PlayerDataOrigin.userImport);
      expect(restored.sourceLabel, 'csv-import');
    });
  });
}
