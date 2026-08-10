import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class PlayerImportColumnMapping {
  final String nameColumn;
  final String teamColumn;
  final String rolesColumn;
  final String? idColumn;
  final String? basePriceColumn;

  const PlayerImportColumnMapping({
    required this.nameColumn,
    required this.teamColumn,
    required this.rolesColumn,
    this.idColumn,
    this.basePriceColumn,
  });
}

class PlayerImportIssue {
  /// Numero di riga del file, contando l'intestazione come riga 1.
  final int rowNumber;
  final String message;

  const PlayerImportIssue({
    required this.rowNumber,
    required this.message,
  });
}

class PlayerImportResult {
  final List<String> headers;
  final List<PlayerEntity> players;
  final List<PlayerImportIssue> issues;

  const PlayerImportResult({
    required this.headers,
    required this.players,
    required this.issues,
  });

  bool get isValid => players.isNotEmpty && issues.isEmpty;
}

class PlayerImportException implements Exception {
  final String message;

  const PlayerImportException(this.message);

  @override
  String toString() => message;
}
