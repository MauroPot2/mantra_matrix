// Parsing e normalizzazione dei formati di listone supportati.
import 'dart:convert';

import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';

class PlayerCatalogImportException implements Exception {
  final String message;

  const PlayerCatalogImportException(this.message);

  @override
  String toString() => message;
}

class PlayerCatalogImportService {
  const PlayerCatalogImportService();

  /// Accetta un array JSON, un oggetto con chiave `players`/`data`, oppure un
  /// CSV/TSV con intestazioni. Gli alias più comuni (`understat_id`,
  /// `position`, `base_price`) sono normalizzati da [PlayerModel].
  List<PlayerModel> parse(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      throw const PlayerCatalogImportException(
        'Incolla il contenuto JSON o CSV del listone.',
      );
    }

    try {
      final records = normalized.startsWith('[') || normalized.startsWith('{')
          ? _decodeJson(normalized)
          : _decodeDelimited(normalized);
      return _buildPlayers(records);
    } on PlayerCatalogImportException {
      rethrow;
    } on FormatException catch (error) {
      throw PlayerCatalogImportException(error.message.toString());
    } catch (error) {
      throw PlayerCatalogImportException('Listone non valido: $error');
    }
  }

  List<Map<String, dynamic>> _decodeJson(String source) {
    final decoded = jsonDecode(source);
    final Object? rawRecords;

    if (decoded is List) {
      rawRecords = decoded;
    } else if (decoded is Map) {
      rawRecords = decoded['players'] ?? decoded['data'] ?? decoded['items'];
    } else {
      rawRecords = null;
    }

    if (rawRecords is! List) {
      throw const PlayerCatalogImportException(
        'Il JSON deve essere un array oppure contenere la chiave "players".',
      );
    }

    return rawRecords.map((record) {
      if (record is! Map) {
        throw const PlayerCatalogImportException(
          'Ogni giocatore deve essere rappresentato da un oggetto JSON.',
        );
      }
      return Map<String, dynamic>.from(record);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _decodeDelimited(String source) {
    final lines = const LineSplitter()
        .convert(source)
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) {
      throw const PlayerCatalogImportException(
        'Il CSV deve contenere intestazioni e almeno un giocatore.',
      );
    }

    final delimiter = _detectDelimiter(lines.first);
    final rows = lines.map((line) => _parseRow(line, delimiter)).toList();
    final headers = rows.first.map(_normalizeHeader).toList(growable: false);

    return rows.skip(1).map((row) {
      final record = <String, dynamic>{};
      for (var index = 0; index < headers.length; index++) {
        if (headers[index].isEmpty) continue;
        record[headers[index]] = index < row.length ? row[index].trim() : '';
      }
      return record;
    }).toList(growable: false);
  }

  List<PlayerModel> _buildPlayers(List<Map<String, dynamic>> records) {
    final players = <PlayerModel>[];
    final ids = <String>{};

    for (var index = 0; index < records.length; index++) {
      final record = Map<String, dynamic>.from(records[index]);
      record['id'] ??= record['understat_id'] ?? record['player_id'];
      record['roles'] ??= record['role'] ?? record['position'];
      record['team'] ??= record['squadra'] ?? record['club'];
      record['name'] ??= record['nome'] ?? record['player_name'];
      record['fvm'] ??= record['base_price'] ?? record['quotazione'];

      final name = record['name']?.toString().trim() ?? '';
      final team = record['team']?.toString().trim() ?? '';
      record['id'] ??= _stableId(name: name, team: team);

      try {
        final player = PlayerModel.fromJson(record);
        if (!ids.add(player.id)) {
          throw PlayerCatalogImportException(
            'ID duplicato alla riga ${index + 1}: ${player.id}.',
          );
        }
        players.add(player);
      } on FormatException catch (error) {
        throw PlayerCatalogImportException(
          'Giocatore ${index + 1} non valido: ${error.message}',
        );
      }
    }

    if (players.isEmpty) {
      throw const PlayerCatalogImportException(
        'Il listone non contiene giocatori validi.',
      );
    }

    players.sort((a, b) => a.name.compareTo(b.name));
    return List<PlayerModel>.unmodifiable(players);
  }

  static String _stableId({required String name, required String team}) {
    final raw = '${name}_$team'.trim().toLowerCase();
    final id = raw
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (id.isEmpty) {
      throw const PlayerCatalogImportException(
        'Ogni giocatore deve avere almeno un ID oppure nome e squadra.',
      );
    }
    return id;
  }

  static String _normalizeHeader(String value) {
    final normalized = value
        .replaceFirst('\ufeff', '')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    return switch (normalized) {
      'nome' => 'name',
      'squadra' || 'club' => 'team',
      'ruolo' || 'ruoli' => 'roles',
      'quotazione' || 'qt.a' || 'qt_i' => 'fvm',
      _ => normalized,
    };
  }

  static String _detectDelimiter(String header) {
    final candidates = [',', ';', '\t'];
    var selected = ',';
    var maximum = -1;
    for (final candidate in candidates) {
      final count = _parseRow(header, candidate).length;
      if (count > maximum) {
        maximum = count;
        selected = candidate;
      }
    }
    return selected;
  }

  static List<String> _parseRow(String line, String delimiter) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (character == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && character == delimiter) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(character);
      }
    }
    if (quoted) {
      throw const FormatException('Virgolette non chiuse in una riga CSV.');
    }
    values.add(buffer.toString());
    return values;
  }
}
