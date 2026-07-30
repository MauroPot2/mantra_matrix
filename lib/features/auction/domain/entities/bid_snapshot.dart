class BidSnapshot {
  final String playerId;
  final int currentBid;
  final DateTime updatedAt;
  final String sourceEventId;

  const BidSnapshot({
    required this.playerId,
    required this.currentBid,
    required this.updatedAt,
    required this.sourceEventId,
  });
}
