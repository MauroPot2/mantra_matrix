class BidSnapshot {
  final String playerId;
  final int currentBid;
  final DateTime updatedAt;
  final String sourceEventId;
  final String nominationEventId;
  final DateTime endsAt;
  final String? leadingTeamId;

  const BidSnapshot({
    required this.playerId,
    required this.currentBid,
    required this.updatedAt,
    required this.sourceEventId,
    required this.nominationEventId,
    required this.endsAt,
    this.leadingTeamId,
  });

  bool isExpiredAt(DateTime dateTime) => !dateTime.toUtc().isBefore(endsAt);
}
