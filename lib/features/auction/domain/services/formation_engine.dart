import 'package:mantra_matrix/features/auction/domain/entities/mantra_formation.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class FormationEngine {
  const FormationEngine();

  static const List<MantraFormation> officialFormations = [
    MantraFormation(
      name: '3-4-3',
      slots: [
        _por,
        _dc,
        _dc,
        _dcOrB,
        _e,
        _mOrC,
        _c,
        _e,
        _wOrA,
        _aOrPc,
        _wOrA,
      ],
    ),
    MantraFormation(
      name: '3-4-1-2',
      slots: [
        _por,
        _dc,
        _dc,
        _dcOrB,
        _e,
        _mOrC,
        _c,
        _e,
        _t,
        _aOrPc,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '3-4-2-1',
      slots: [
        _por,
        _dc,
        _dc,
        _dcOrB,
        _eOrW,
        _m,
        _mOrC,
        _e,
        _t,
        _tOrA,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '3-5-2',
      slots: [
        _por,
        _dc,
        _dc,
        _dcOrB,
        _eOrW,
        _mOrC,
        _m,
        _c,
        _e,
        _aOrPc,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '3-5-1-1',
      slots: [
        _por,
        _dc,
        _dc,
        _dcOrB,
        _eOrW,
        _m,
        _c,
        _m,
        _eOrW,
        _tOrA,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '4-3-3',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _mOrC,
        _m,
        _c,
        _wOrA,
        _aOrPc,
        _wOrA,
      ],
    ),
    MantraFormation(
      name: '4-3-1-2',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _mOrC,
        _m,
        _c,
        _t,
        _tOrAOrPc,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '4-4-2',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _eOrW,
        _mOrC,
        _c,
        _e,
        _aOrPc,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '4-1-4-1',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _m,
        _eOrW,
        _cOrT,
        _t,
        _w,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '4-4-1-1',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _eOrW,
        _m,
        _c,
        _eOrW,
        _tOrA,
        _aOrPc,
      ],
    ),
    MantraFormation(
      name: '4-2-3-1',
      slots: [
        _por,
        _dd,
        _dc,
        _dc,
        _ds,
        _m,
        _mOrC,
        _wOrT,
        _t,
        _wOrA,
        _aOrPc,
      ],
    ),
  ];

  List<MantraFormationAnalysis> analyzeRoster(List<PlayerEntity> roster) {
    final analyses = officialFormations
        .map((formation) => analyzeFormation(formation, roster))
        .toList(growable: false);

    analyses.sort((a, b) {
      final missingComparison = a.missingSlots.compareTo(b.missingSlots);
      if (missingComparison != 0) return missingComparison;
      return a.formation.name.compareTo(b.formation.name);
    });
    return analyses;
  }


  MantraFormation? formationByName(String name) {
    for (final formation in officialFormations) {
      if (formation.name == name) return formation;
    }
    return null;
  }

  FormationImpact analyzePlayerImpact({
    required List<PlayerEntity> roster,
    required PlayerEntity candidate,
    String primaryFormationName = '4-2-3-1',
    Set<String> secondaryFormationNames = const {'4-3-3', '4-4-2'},
  }) {
    final before = analyzeRoster(roster);
    final after = analyzeRoster([...roster, candidate]);
    final beforeByName = {
      for (final analysis in before) analysis.formation.name: analysis,
    };
    final afterByName = {
      for (final analysis in after) analysis.formation.name: analysis,
    };

    final unlocked = <String>[];
    final improved = <String>[];
    for (final formation in officialFormations) {
      final previous = beforeByName[formation.name]!;
      final current = afterByName[formation.name]!;
      if (!previous.isPlayable && current.isPlayable) {
        unlocked.add(formation.name);
      } else if (current.missingSlots < previous.missingSlots) {
        improved.add(formation.name);
      }
    }

    final primaryBefore = beforeByName[primaryFormationName];
    final primaryAfter = afterByName[primaryFormationName];
    final primaryUnlocked = primaryBefore != null &&
        primaryAfter != null &&
        !primaryBefore.isPlayable &&
        primaryAfter.isPlayable;
    final primaryReduction = primaryBefore == null || primaryAfter == null
        ? 0
        : primaryBefore.missingSlots - primaryAfter.missingSlots;

    var secondaryUnlocked = 0;
    var secondaryReduction = 0;
    for (final name in secondaryFormationNames) {
      final previous = beforeByName[name];
      final current = afterByName[name];
      if (previous == null || current == null) continue;
      if (!previous.isPlayable && current.isPlayable) secondaryUnlocked++;
      secondaryReduction += previous.missingSlots - current.missingSlots;
    }

    final closestBefore = before.isEmpty ? 11 : before.first.missingSlots;
    final closestAfter = after.isEmpty ? 11 : after.first.missingSlots;

    return FormationImpact(
      before: List.unmodifiable(before),
      after: List.unmodifiable(after),
      unlockedFormationNames: List.unmodifiable(unlocked),
      improvedFormationNames: List.unmodifiable(improved),
      playableBefore: before.where((item) => item.isPlayable).length,
      playableAfter: after.where((item) => item.isPlayable).length,
      closestMissingBefore: closestBefore,
      closestMissingAfter: closestAfter,
      primaryUnlocked: primaryUnlocked,
      primaryMissingReduction: primaryReduction,
      secondaryUnlockedCount: secondaryUnlocked,
      secondaryMissingReduction: secondaryReduction,
    );
  }

  MantraFormationAnalysis analyzeFormation(
    MantraFormation formation,
    List<PlayerEntity> roster,
  ) {
    // Matching bipartito: ogni giocatore può occupare un solo slot e ogni
    // slot può ricevere un solo giocatore. In questo modo i multiruolo non
    // vengono conteggiati due volte.
    final playerIndexBySlot = List<int?>.filled(formation.slots.length, null);
    var matched = 0;

    final slotIndexes = List<int>.generate(formation.slots.length, (i) => i)
      ..sort((left, right) {
        final leftCandidates = _candidateCount(formation.slots[left], roster);
        final rightCandidates = _candidateCount(formation.slots[right], roster);
        return leftCandidates.compareTo(rightCandidates);
      });

    for (final slotIndex in slotIndexes) {
      final visitedPlayers = <int>{};
      if (_assignSlot(
        slotIndex: slotIndex,
        formation: formation,
        roster: roster,
        playerIndexBySlot: playerIndexBySlot,
        visitedPlayers: visitedPlayers,
      )) {
        matched++;
      }
    }

    final missingLabels = <String>[
      for (var index = 0; index < formation.slots.length; index++)
        if (playerIndexBySlot[index] == null) formation.slots[index].label,
    ];

    return MantraFormationAnalysis(
      formation: formation,
      filledSlots: matched,
      missingSlotLabels: List.unmodifiable(missingLabels),
    );
  }

  int _candidateCount(MantraFormationSlot slot, List<PlayerEntity> roster) {
    return roster.where(slot.accepts).length;
  }

  bool _assignSlot({
    required int slotIndex,
    required MantraFormation formation,
    required List<PlayerEntity> roster,
    required List<int?> playerIndexBySlot,
    required Set<int> visitedPlayers,
  }) {
    final slot = formation.slots[slotIndex];

    for (var playerIndex = 0; playerIndex < roster.length; playerIndex++) {
      if (visitedPlayers.contains(playerIndex)) continue;
      if (!slot.accepts(roster[playerIndex])) continue;
      visitedPlayers.add(playerIndex);

      final occupiedSlot = playerIndexBySlot.indexOf(playerIndex);
      if (occupiedSlot == -1 ||
          _assignSlot(
            slotIndex: occupiedSlot,
            formation: formation,
            roster: roster,
            playerIndexBySlot: playerIndexBySlot,
            visitedPlayers: visitedPlayers,
          )) {
        playerIndexBySlot[slotIndex] = playerIndex;
        return true;
      }
    }

    return false;
  }
}

const _por = MantraFormationSlot(
  label: 'POR',
  acceptedRoles: {MantraRole.por},
);
const _dc = MantraFormationSlot(
  label: 'DC',
  acceptedRoles: {MantraRole.dc},
);
const _dcOrB = MantraFormationSlot(
  label: 'DC/B',
  acceptedRoles: {MantraRole.dc, MantraRole.b},
);
const _dd = MantraFormationSlot(
  label: 'DD',
  acceptedRoles: {MantraRole.dd},
);
const _ds = MantraFormationSlot(
  label: 'DS',
  acceptedRoles: {MantraRole.ds},
);
const _e = MantraFormationSlot(
  label: 'E',
  acceptedRoles: {MantraRole.e},
);
const _m = MantraFormationSlot(
  label: 'M',
  acceptedRoles: {MantraRole.m},
);
const _c = MantraFormationSlot(
  label: 'C',
  acceptedRoles: {MantraRole.c},
);
const _t = MantraFormationSlot(
  label: 'T',
  acceptedRoles: {MantraRole.t},
);
const _w = MantraFormationSlot(
  label: 'W',
  acceptedRoles: {MantraRole.w},
);
const _mOrC = MantraFormationSlot(
  label: 'M/C',
  acceptedRoles: {MantraRole.m, MantraRole.c},
);
const _eOrW = MantraFormationSlot(
  label: 'E/W',
  acceptedRoles: {MantraRole.e, MantraRole.w},
);
const _wOrA = MantraFormationSlot(
  label: 'W/A',
  acceptedRoles: {MantraRole.w, MantraRole.a},
);
const _wOrT = MantraFormationSlot(
  label: 'W/T',
  acceptedRoles: {MantraRole.w, MantraRole.t},
);
const _cOrT = MantraFormationSlot(
  label: 'C/T',
  acceptedRoles: {MantraRole.c, MantraRole.t},
);
const _tOrA = MantraFormationSlot(
  label: 'T/A',
  acceptedRoles: {MantraRole.t, MantraRole.a},
);
const _tOrAOrPc = MantraFormationSlot(
  label: 'T/A/PC',
  acceptedRoles: {MantraRole.t, MantraRole.a, MantraRole.pc},
);
const _aOrPc = MantraFormationSlot(
  label: 'A/PC',
  acceptedRoles: {MantraRole.a, MantraRole.pc},
);
