import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/import/player_import.dart';

class DelimitedPlayerImporter {
  const DelimitedPlayerImporter();

  List<String> readHeaders(String contents) {
    final rows = _parse(contents);
    if (rows.isEmpty) {
      throw const PlayerImportException('Il file non contiene righe valide.');
    }
    return List<String>.unmodifiable(
      rows.first.map((value) => value.trim()).toList(growable: false),
    );
  }

  PlayerImportResult import(
    String contents, {
    required PlayerImportColumnMapping mapping,
    Map<String, MantraRole> roleAliases = const {},
  }) {
    final rows = _parse(contents);
    if (rows.length < 2) {
      throw const PlayerImportException(
        'Il file deve contenere un’intestazione e almeno un giocatore.',
      );
    }

    final headers = rows.first.map((value) => value.trim()).toList();
    final indexes = _resolveIndexes(headers, mapping);
    final normalizedAliases = {
      for (final entry in roleAliases.entries)
        entry.key.trim().toLowerCase(): entry.value,
    };

    final players = <PlayerEntity>[];
    final issues = <PlayerImportIssue>[];
    final usedIds = <String>{};

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.trim().isEmpty)) continue;
      final rowNumber = rowIndex + 1;

      try {
        final name = _requiredCell(row, indexes.name, 'nome');
        final team = _requiredCell(row, indexes.team, 'squadra');
        final rolesRaw = _requiredCell(row, indexes.roles, 'ruoli');
        final roles = _parseRoles(rolesRaw, aliases: normalizedAliases);
        if (roles.isEmpty) {
          throw PlayerImportException('Nessun ruolo riconosciuto: $rolesRaw');
        }

        final basePrice = indexes.basePrice == null
            ? 1
            : _parseBasePrice(_cell(row, indexes.basePrice!));
        final requestedId = indexes.id == null ? null : _cell(row, indexes.id!);
        final id = _uniqueId(
          requestedId?.trim().isNotEmpty == true
              ? requestedId!.trim()
              : _buildId(name, team),
          usedIds,
        );

        players.add(
          PlayerEntity(
            id: id,
            name: name,
            team: team,
            roles: roles,
            basePrice: basePrice,
            dataOrigin: PlayerDataOrigin.userImport,
            sourceLabel: 'delimited-import',
            expectedGoals: 0,
            expectedAssists: 0,
            expectedGoals90: 0,
            expectedAssists90: 0,
            expectedYellowCards: 0,
            historicalMinutes: 0,
          ),
        );
      } on PlayerImportException catch (error) {
        issues.add(
          PlayerImportIssue(rowNumber: rowNumber, message: error.message),
        );
      }
    }

    return PlayerImportResult(
      headers: List<String>.unmodifiable(headers),
      players: List<PlayerEntity>.unmodifiable(players),
      issues: List<PlayerImportIssue>.unmodifiable(issues),
    );
  }

  _ResolvedIndexes _resolveIndexes(
    List<String> headers,
    PlayerImportColumnMapping mapping,
  ) {
    final normalized = <String, int>{};
    for (var index = 0; index < headers.length; index++) {
      normalized.putIfAbsent(_normalizeHeader(headers[index]), () => index);
    }

    int requiredIndex(String column, String label) {
      final index = normalized[_normalizeHeader(column)];
      if (index == null) {
        throw PlayerImportException(
          'Colonna $label non trovata: "$column".',
        );
      }
      return index;
    }

    int? optionalIndex(String? column) {
      if (column == null || column.trim().isEmpty) return null;
      final index = normalized[_normalizeHeader(column)];
      if (index == null) {
        throw PlayerImportException('Colonna non trovata: "$column".');
      }
      return index;
    }

    return _ResolvedIndexes(
      name: requiredIndex(mapping.nameColumn, 'nome'),
      team: requiredIndex(mapping.teamColumn, 'squadra'),
      roles: requiredIndex(mapping.rolesColumn, 'ruoli'),
      id: optionalIndex(mapping.idColumn),
      basePrice: optionalIndex(mapping.basePriceColumn),
    );
  }

  List<MantraRole> _parseRoles(
    String value, {
    required Map<String, MantraRole> aliases,
  }) {
    final result = <MantraRole>[];
    final tokens = value
        .split(RegExp(r'[;,/|\s]+'))
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.isNotEmpty);

    for (final token in tokens) {
      final alias = aliases[token];
      final role = alias ?? _roleByName(token);
      if (role == null) {
        throw PlayerImportException('Ruolo non riconosciuto: "$token".');
      }
      if (!result.contains(role)) result.add(role);
    }
    return List<MantraRole>.unmodifiable(result);
  }

  MantraRole? _roleByName(String value) {
    for (final role in MantraRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  int _parseBasePrice(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 1;
    final parsed = num.tryParse(normalized.replaceAll(',', '.'))?.round();
    if (parsed == null || parsed < 0) {
      throw PlayerImportException('Prezzo base non valido: "$value".');
    }
    return parsed;
  }

  String _requiredCell(List<String> row, int index, String label) {
    final value = _cell(row, index)?.trim() ?? '';
    if (value.isEmpty) {
      throw PlayerImportException('Campo $label mancante.');
    }
    return value;
  }

  String? _cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index];
  }

  String _uniqueId(String requested, Set<String> usedIds) {
    final base = _slug(requested);
    var candidate = base.isEmpty ? 'player' : base;
    var suffix = 2;
    while (!usedIds.add(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  String _buildId(String name, String team) => '${_slug(team)}_${_slug(name)}';

  String _slug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized;
  }

  String _normalizeHeader(String value) => value.trim().toLowerCase();

  List<List<String>> _parse(String input) {
    var source = input;
    if (source.startsWith('\ufeff')) source = source.substring(1);
    source = source.trim();
    if (source.isEmpty) return const [];

    String? explicitDelimiter;
    final firstBreak = source.indexOf(RegExp(r'\r?\n'));
    final firstLine = firstBreak == -1 ? source : source.substring(0, firstBreak);
    final sepMatch = RegExp(r'^sep=(.)$', caseSensitive: false).firstMatch(
      firstLine.trim(),
    );
    if (sepMatch != null) {
      explicitDelimiter = sepMatch.group(1);
      source = firstBreak == -1 ? '' : source.substring(firstBreak + 1);
      if (source.startsWith('\n')) source = source.substring(1);
    }

    final delimiter = explicitDelimiter ?? _detectDelimiter(source);
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < source.length; index++) {
      final char = source[index];

      if (char == '"') {
        if (inQuotes && index + 1 < source.length && source[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (!inQuotes && char == delimiter) {
        row.add(field.toString());
        field.clear();
        continue;
      }

      if (!inQuotes && (char == '\n' || char == '\r')) {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        if (char == '\r' && index + 1 < source.length && source[index + 1] == '\n') {
          index++;
        }
        continue;
      }

      field.write(char);
    }

    if (inQuotes) {
      throw const PlayerImportException('Virgolette non chiuse nel file.');
    }

    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    return rows.where((candidate) {
      return candidate.any((value) => value.trim().isNotEmpty);
    }).toList(growable: false);
  }

  String _detectDelimiter(String source) {
    const candidates = [',', ';', '\t', '|'];
    final counts = {for (final candidate in candidates) candidate: 0};
    var inQuotes = false;

    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (char == '"') {
        if (inQuotes && index + 1 < source.length && source[index + 1] == '"') {
          index++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (!inQuotes && (char == '\n' || char == '\r')) break;
      if (!inQuotes && counts.containsKey(char)) {
        counts[char] = counts[char]! + 1;
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.first.value == 0) {
      throw const PlayerImportException(
        'Separatore non riconosciuto. Usa CSV, TSV o valori separati da ;.',
      );
    }
    return sorted.first.key;
  }
}

class _ResolvedIndexes {
  final int name;
  final int team;
  final int roles;
  final int? id;
  final int? basePrice;

  const _ResolvedIndexes({
    required this.name,
    required this.team,
    required this.roles,
    required this.id,
    required this.basePrice,
  });
}
