class RosterAssignment {
  final String eventId;
  final String playerId;
  final String teamId;
  final int price;
  final DateTime assignedAt;

  const RosterAssignment({
    required this.eventId,
    required this.playerId,
    required this.teamId,
    required this.price,
    required this.assignedAt,
  });
}
