import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/player_database/data/services/player_catalog_import_service.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const service = PlayerCatalogImportService();

  test('importa il JSON Understat già usato dal progetto', () {
    final players = service.parse('''
      [
        {
          "understat_id": "7006",
          "name": "Lautaro Martinez",
          "team": "Inter",
          "position": "A;PC",
          "fvm": 120,
          "xG": 17.1
        }
      ]
    ''');

    expect(players.single.id, '7006');
    expect(players.single.roles, [MantraRole.a, MantraRole.pc]);
    expect(players.single.basePrice, 120);
  });

  test('importa CSV e genera un id stabile se assente', () {
    final players = service.parse(
      'nome,squadra,ruoli,quotazione\n'
      'Nico Paz,Como,"T;A",35',
    );

    expect(players.single.id, 'nico-paz-como');
    expect(players.single.roles, [MantraRole.t, MantraRole.a]);
    expect(players.single.basePrice, 35);
  });

  test('rifiuta identificativi duplicati', () {
    expect(
      () => service.parse('''
        [
          {"id":"1","name":"A","team":"X","roles":"C"},
          {"id":"1","name":"B","team":"Y","roles":"PC"}
        ]
      '''),
      throwsA(isA<PlayerCatalogImportException>()),
    );
  });
}
