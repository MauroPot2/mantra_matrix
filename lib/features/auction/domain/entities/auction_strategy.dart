import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

enum PlayerDepartment { goalkeepers, defenders, midfielders, forwards }

extension PlayerDepartmentX on PlayerDepartment {
  String get label => switch (this) {
        PlayerDepartment.goalkeepers => 'Portieri',
        PlayerDepartment.defenders => 'Difensori',
        PlayerDepartment.midfielders => 'Centrocampisti',
        PlayerDepartment.forwards => 'Attaccanti',
      };

  String get shortLabel => switch (this) {
        PlayerDepartment.goalkeepers => 'POR',
        PlayerDepartment.defenders => 'DIF',
        PlayerDepartment.midfielders => 'CEN',
        PlayerDepartment.forwards => 'ATT',
      };

  static PlayerDepartment fromName(String? name) {
    return PlayerDepartment.values.firstWhere(
      (department) => department.name == name,
      orElse: () => PlayerDepartment.midfielders,
    );
  }

  /// Il primo ruolo del listone viene considerato il ruolo principale.
  /// Questo evita di addebitare un E/W contemporaneamente a due reparti.
  static PlayerDepartment forPlayer(PlayerEntity player) {
    if (player.roles.isEmpty) return PlayerDepartment.midfielders;
    return forRole(player.roles.first);
  }

  static PlayerDepartment forRole(MantraRole role) {
    switch (role) {
      case MantraRole.por:
        return PlayerDepartment.goalkeepers;
      case MantraRole.dc:
      case MantraRole.b:
      case MantraRole.dd:
      case MantraRole.ds:
        return PlayerDepartment.defenders;
      case MantraRole.e:
      case MantraRole.m:
      case MantraRole.c:
      case MantraRole.t:
        return PlayerDepartment.midfielders;
      case MantraRole.w:
      case MantraRole.a:
      case MantraRole.pc:
        return PlayerDepartment.forwards;
    }
  }
}
