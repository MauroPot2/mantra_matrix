import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';

enum AuctionUndoClockAction { clear, preserve, restart }

class AuctionUndoClockDecision {
  final AuctionUndoClockAction action;
  final int extensionSeconds;

  const AuctionUndoClockDecision({
    required this.action,
    required this.extensionSeconds,
  });
}

class AuctionUndoClockPolicy {
  const AuctionUndoClockPolicy();

  AuctionUndoClockDecision decide({
    required AuctionEvent undoEvent,
    required AuctionSessionSnapshot snapshotAfterUndo,
    required AuctionClockPhase currentPhase,
    required String? currentActivePlayerId,
    required int currentExtensionSeconds,
  }) {
    if (undoEvent.type != AuctionEventType.eventReverted) {
      throw ArgumentError.value(
        undoEvent.type,
        'undoEvent.type',
        'La policy accetta solo eventi eventReverted.',
      );
    }

    final restoredPlayerId = snapshotAfterUndo.activePlayerId;
    if (restoredPlayerId == null) {
      return const AuctionUndoClockDecision(
        action: AuctionUndoClockAction.clear,
        extensionSeconds: 0,
      );
    }

    final sameRunningCall = currentPhase == AuctionClockPhase.running &&
        currentActivePlayerId == restoredPlayerId;
    if (sameRunningCall) {
      final compensated = currentExtensionSeconds +
          (undoEvent.clockExtensionSeconds ?? 0);
      return AuctionUndoClockDecision(
        action: AuctionUndoClockAction.preserve,
        extensionSeconds: compensated < 0 ? 0 : compensated,
      );
    }

    return const AuctionUndoClockDecision(
      action: AuctionUndoClockAction.restart,
      extensionSeconds: 0,
    );
  }
}
