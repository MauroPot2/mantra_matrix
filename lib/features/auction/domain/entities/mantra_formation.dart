import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class MantraFormationSlot {
  final String label;
  final Set<MantraRole> acceptedRoles;

  const MantraFormationSlot({
    required this.label,
    required this.acceptedRoles,
  });

  bool accepts(PlayerEntity player) {
    assert(
      acceptedRoles.isNotEmpty,
      'Uno slot Mantra deve accettare almeno un ruolo.',
    );
    return player.roles.any(acceptedRoles.contains);
  }
}

class MantraFormation {
  final String name;
  final List<MantraFormationSlot> slots;

  const MantraFormation({required this.name, required this.slots});

  int get requiredPlayers => slots.length;
}

class MantraFormationAnalysis {
  final MantraFormation formation;
  final int filledSlots;
  final List<String> missingSlotLabels;

  const MantraFormationAnalysis({
    required this.formation,
    required this.filledSlots,
    required this.missingSlotLabels,
  });

  int get missingSlots => formation.requiredPlayers - filledSlots;
  bool get isPlayable => missingSlots == 0;
  double get completion => formation.requiredPlayers == 0
      ? 0
      : filledSlots / formation.requiredPlayers;
}

class FormationImpact {
  final List<MantraFormationAnalysis> before;
  final List<MantraFormationAnalysis> after;
  final List<String> unlockedFormationNames;
  final List<String> improvedFormationNames;
  final int playableBefore;
  final int playableAfter;
  final int closestMissingBefore;
  final int closestMissingAfter;
  final bool primaryUnlocked;
  final int primaryMissingReduction;
  final int secondaryUnlockedCount;
  final int secondaryMissingReduction;

  const FormationImpact({
    required this.before,
    required this.after,
    required this.unlockedFormationNames,
    required this.improvedFormationNames,
    required this.playableBefore,
    required this.playableAfter,
    required this.closestMissingBefore,
    required this.closestMissingAfter,
    required this.primaryUnlocked,
    required this.primaryMissingReduction,
    required this.secondaryUnlockedCount,
    required this.secondaryMissingReduction,
  });

  int get bestMissingReduction =>
      closestMissingBefore - closestMissingAfter;

  bool get improvesAnything =>
      unlockedFormationNames.isNotEmpty ||
      improvedFormationNames.isNotEmpty ||
      bestMissingReduction > 0;
}
