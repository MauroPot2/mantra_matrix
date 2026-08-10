import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class PlayerModel extends PlayerEntity {
  const PlayerModel({
    required super.id,
    required super.name,
    required super.team,
    required super.roles,
    required super.basePrice,
    required super.expectedGoals,
    required super.expectedAssists,
    required super.expectedGoals90,
    required super.expectedAssists90,
    required super.expectedYellowCards,
    required super.historicalMinutes,
    super.expectedGoalsConceded,
    super.expectedCleanSheets,
    super.isPenaltyTaker,
    super.isFreeKickTaker,
    super.isInjured,
    super.isSuspended,
    super.expectedPoints,
    super.polyvalenceMultiplier,
    super.vorp,
    super.status,
    super.draftedByTeamId,
    super.purchasePrice,
  });

  /// Accetta sia il payload del backend sia i campi già presenti in Firestore.
  /// [documentId] evita di dover duplicare l'id dentro ogni documento Firestore.
  factory PlayerModel.fromJson(
    Map<String, dynamic> json, {
    String? documentId,
  }) {
    final id =
        _readString(json, const ['id', 'understat_id', 'player_id']) ??
        documentId;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('PlayerModel: id mancante');
    }

    return PlayerModel(
      id: id,
      name: _requiredString(json, const ['name']),
      team: _requiredString(json, const ['team']),
      roles: _parseRoles(json['roles'] ?? json['role'] ?? json['position']),
      basePrice: _readInt(json, const [
        'fvm',
        'base_price',
        'basePrice',
      ], fallback: 1),
      expectedGoals: _readDouble(json, const ['xG', 'expected_goals']),
      expectedAssists: _readDouble(json, const ['xA', 'expected_assists']),
      expectedGoals90: _readDouble(json, const ['xG90', 'expected_goals_90']),
      expectedAssists90: _readDouble(json, const [
        'xA90',
        'expected_assists_90',
      ]),
      expectedYellowCards: _readDouble(json, const [
        'xYC',
        'expected_yellow_cards',
      ]),
      historicalMinutes: _readInt(json, const [
        'minutes',
        'historical_minutes',
      ]),
      expectedGoalsConceded: _readDouble(json, const [
        'xGC',
        'expected_goals_conceded',
      ]),
      expectedCleanSheets: _readDouble(json, const [
        'xCS',
        'expected_clean_sheets',
      ]),
      isPenaltyTaker: _readBool(json, const [
        'is_penalty_taker',
        'isPenaltyTaker',
      ]),
      isFreeKickTaker: _readBool(json, const [
        'is_free_kick_taker',
        'isFreeKickTaker',
      ]),
      isInjured: _readBool(json, const ['is_injured', 'isInjured']),
      isSuspended: _readBool(json, const ['is_suspended', 'isSuspended']),
      expectedPoints: _readDouble(json, const [
        'expected_points',
        'expectedPoints',
      ]),
      polyvalenceMultiplier: _readDouble(json, const [
        'polyvalence_multiplier',
        'polyvalenceMultiplier',
      ], fallback: 1.0),
      vorp: _readDouble(json, const ['vorp']),
      status: _parseStatus(json['status']),
      draftedByTeamId: _readString(json, const [
        'drafted_by_team_id',
        'draftedByTeamId',
      ]),
      purchasePrice: _readNullableInt(json, const [
        'purchase_price',
        'purchasePrice',
      ]),
    );
  }

  factory PlayerModel.fromEntity(PlayerEntity player) {
    return PlayerModel(
      id: player.id,
      name: player.name,
      team: player.team,
      roles: player.roles,
      basePrice: player.basePrice,
      expectedGoals: player.expectedGoals,
      expectedAssists: player.expectedAssists,
      expectedGoals90: player.expectedGoals90,
      expectedAssists90: player.expectedAssists90,
      expectedYellowCards: player.expectedYellowCards,
      historicalMinutes: player.historicalMinutes,
      expectedGoalsConceded: player.expectedGoalsConceded,
      expectedCleanSheets: player.expectedCleanSheets,
      isPenaltyTaker: player.isPenaltyTaker,
      isFreeKickTaker: player.isFreeKickTaker,
      isInjured: player.isInjured,
      isSuspended: player.isSuspended,
      expectedPoints: player.expectedPoints,
      polyvalenceMultiplier: player.polyvalenceMultiplier,
      vorp: player.vorp,
      status: player.status,
      draftedByTeamId: player.draftedByTeamId,
      purchasePrice: player.purchasePrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'team': team,
      'roles': roles.map((role) => role.name.toUpperCase()).join(';'),
      'fvm': basePrice,
      'xG': expectedGoals,
      'xA': expectedAssists,
      'xG90': expectedGoals90,
      'xA90': expectedAssists90,
      'xYC': expectedYellowCards,
      'minutes': historicalMinutes,
      'xGC': expectedGoalsConceded,
      'xCS': expectedCleanSheets,
      'is_penalty_taker': isPenaltyTaker,
      'is_free_kick_taker': isFreeKickTaker,
      'is_injured': isInjured,
      'is_suspended': isSuspended,
      'expected_points': expectedPoints,
      'polyvalence_multiplier': polyvalenceMultiplier,
      'vorp': vorp,
      'status': status.name,
      'drafted_by_team_id': draftedByTeamId,
      'purchase_price': purchasePrice,
    };
  }

  static List<MantraRole> _parseRoles(dynamic rawRoles) {
    final values = switch (rawRoles) {
      String value => value.split(RegExp(r'[;,/\s]+')),
      Iterable value => value.map((item) => item.toString()).toList(),
      _ => <String>[],
    };

    final parsed = values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .map(_tryParseRole)
        .whereType<MantraRole>()
        .toSet()
        .toList(growable: false);

    if (parsed.isEmpty) {
      throw FormatException('PlayerModel: ruoli non validi: $rawRoles');
    }

    return parsed;
  }

  static MantraRole? _tryParseRole(String value) {
    for (final role in MantraRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  static DraftStatus _parseStatus(dynamic rawStatus) {
    final value = rawStatus?.toString().trim().toLowerCase();
    return DraftStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => DraftStatus.available,
    );
  }

  static String _requiredString(Map<String, dynamic> json, List<String> keys) {
    final value = _readString(json, keys);
    if (value == null || value.trim().isEmpty) {
      throw FormatException('PlayerModel: campo obbligatorio mancante: $keys');
    }
    return value;
  }

  static String? _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) return value.toString();
    }
    return null;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    List<String> keys, {
    double fallback = 0.0,
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> keys, {
    int fallback = 0,
  }) {
    return _readNullableInt(json, keys) ?? fallback;
  }

  static int? _readNullableInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = num.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) return parsed.round();
      }
    }
    return null;
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
    }
    return false;
  }
}
