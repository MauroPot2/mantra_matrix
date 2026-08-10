import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/player_database/data/services/delimited_player_importer.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/import/player_import.dart';

void main() {
  const importer = DelimitedPlayerImporter();
  const mapping = PlayerImportColumnMapping(
    nameColumn: 'Nome',
    teamColumn: 'Squadra',
    rolesColumn: 'Ruoli',
    basePriceColumn: 'Prezzo',
  );

  group('DelimitedPlayerImporter', () {
    test('imports a generic semicolon separated file', () {
      const input = '''Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;DC/B;7
Luca Bianchi;ALT;C;1''';

      final result = importer.import(input, mapping: mapping);

      expect(result.issues, isEmpty);
      expect(result.players, hasLength(2));
      expect(result.players.first.name, 'Mario Rossi');
      expect(result.players.first.team, 'TEST');
      expect(result.players.first.roles, [MantraRole.dc, MantraRole.b]);
      expect(result.players.first.basePrice, 7);
      expect(result.players.first.dataOrigin, PlayerDataOrigin.userImport);
      expect(result.players.first.sourceLabel, 'delimited-import');
    });

    test('supports quoted fields and automatic comma detection', () {
      const input = '''Nome,Squadra,Ruoli,Prezzo
"Rossi, Mario",TEST,"DC;B",4''';

      final result = importer.import(input, mapping: mapping);

      expect(result.issues, isEmpty);
      expect(result.players.single.name, 'Rossi, Mario');
      expect(result.players.single.roles, [MantraRole.dc, MantraRole.b]);
    });

    test('supports explicit sep declaration', () {
      const input = '''sep=;
Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;DC;3''';

      expect(importer.readHeaders(input), ['Nome', 'Squadra', 'Ruoli', 'Prezzo']);

      final result = importer.import(input, mapping: mapping);
      expect(result.issues, isEmpty);
      expect(result.players.single.basePrice, 3);
    });

    test('maps external role labels through explicit aliases', () {
      const input = '''Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;CB;5''';

      final result = importer.import(
        input,
        mapping: mapping,
        roleAliases: const {'CB': MantraRole.dc},
      );

      expect(result.issues, isEmpty);
      expect(result.players.single.roles, [MantraRole.dc]);
    });

    test('keeps valid rows and reports invalid rows', () {
      const input = '''Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;DC;5
Giocatore Rotto;TEST;RUOLO_SCONOSCIUTO;2
Luca Bianchi;ALT;C;1''';

      final result = importer.import(input, mapping: mapping);

      expect(result.players, hasLength(2));
      expect(result.issues, hasLength(1));
      expect(result.issues.single.rowNumber, 3);
      expect(result.issues.single.message, contains('Ruolo non riconosciuto'));
      expect(result.isValid, isFalse);
    });

    test('creates unique ids when imported rows collide', () {
      const input = '''Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;DC;5
Mario Rossi;TEST;DC;6''';

      final result = importer.import(input, mapping: mapping);

      expect(result.issues, isEmpty);
      expect(result.players[0].id, 'test_mario_rossi');
      expect(result.players[1].id, 'test_mario_rossi_2');
    });

    test('fails when a mapped column does not exist', () {
      const input = '''Nome;Squadra;Ruoli
Mario Rossi;TEST;DC''';

      expect(
        () => importer.import(input, mapping: mapping),
        throwsA(
          isA<PlayerImportException>().having(
            (error) => error.message,
            'message',
            contains('Prezzo'),
          ),
        ),
      );
    });
  });
}
