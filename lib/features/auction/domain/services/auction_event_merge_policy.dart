import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';

class AuctionEventMergeResult {
  final List<AuctionEvent> events;
  final List<String> pendingEventIds;

  const AuctionEventMergeResult({
    required this.events,
    required this.pendingEventIds,
  });
}

/// Riconcilia il log autorevole Firestore con gli eventi ottimistici locali.
///
/// Gli eventi gia confermati dal server vengono sempre ordinati per
/// `serverRevision`. Gli eventi locali ancora pending restano invece in coda
/// nello stesso ordine in cui sono stati prodotti dal controller. In questo
/// modo una conferma Firestore intermedia non puo spostare un rilancio pending
/// davanti all'evento precedente e creare uno stato transitorio invalido.
class AuctionEventMergePolicy {
  const AuctionEventMergePolicy();

  AuctionEventMergeResult merge({
    required List<AuctionEvent> localEvents,
    required List<AuctionEvent> remoteEvents,
    required List<String> pendingEventIds,
  }) {
    final remoteById = <String, AuctionEvent>{
      for (final event in remoteEvents) event.id: event,
    };
    final localById = <String, AuctionEvent>{
      for (final event in localEvents) event.id: event,
    };

    final confirmed = remoteById.values.toList(growable: true)
      ..sort(compareConfirmedEvents);

    final remainingPendingIds = pendingEventIds
        .where((id) => !remoteById.containsKey(id) && localById.containsKey(id))
        .toList(growable: false);
    final pending = remainingPendingIds
        .map((id) => localById[id]!)
        .toList(growable: false);

    return AuctionEventMergeResult(
      events: List<AuctionEvent>.unmodifiable([...confirmed, ...pending]),
      pendingEventIds: List<String>.unmodifiable(remainingPendingIds),
    );
  }

  static int compareConfirmedEvents(AuctionEvent a, AuctionEvent b) {
    final aRevision = a.serverRevision;
    final bRevision = b.serverRevision;

    if (aRevision != null && bRevision != null) {
      final byRevision = aRevision.compareTo(bRevision);
      return byRevision != 0 ? byRevision : a.id.compareTo(b.id);
    }
    if (aRevision == null && bRevision != null) return -1;
    if (aRevision != null && bRevision == null) return 1;

    final byDate = a.occurredAt.compareTo(b.occurredAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }
}
