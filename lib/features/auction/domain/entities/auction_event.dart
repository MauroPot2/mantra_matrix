enum AuctionEventType {
  playerNominated,
  bidChanged,
  playerAssigned,
  playerSkipped,
  playerMarkedUnavailable,
  eventReverted,
}

class AuctionEvent {
  final String id;
  final AuctionEventType type;
  final DateTime occurredAt;
  final String? playerId;
  final String? teamId;
  final int? amount;
  final String? targetEventId;
  final String? note;

  const AuctionEvent._({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.playerId,
    this.teamId,
    this.amount,
    this.targetEventId,
    this.note,
  });

  bool get isReversion => type == AuctionEventType.eventReverted;

  factory AuctionEvent.playerNominated({
    required String id,
    required DateTime occurredAt,
    required String playerId,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.playerNominated,
      occurredAt: occurredAt,
      playerId: playerId,
    );
  }

  factory AuctionEvent.bidChanged({
    required String id,
    required DateTime occurredAt,
    required String playerId,
    required int bid,
    String? teamId,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.bidChanged,
      occurredAt: occurredAt,
      playerId: playerId,
      teamId: teamId,
      amount: bid,
    );
  }

  factory AuctionEvent.playerAssigned({
    required String id,
    required DateTime occurredAt,
    required String playerId,
    required String teamId,
    required int price,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.playerAssigned,
      occurredAt: occurredAt,
      playerId: playerId,
      teamId: teamId,
      amount: price,
    );
  }

  factory AuctionEvent.playerSkipped({
    required String id,
    required DateTime occurredAt,
    required String playerId,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.playerSkipped,
      occurredAt: occurredAt,
      playerId: playerId,
    );
  }

  factory AuctionEvent.playerMarkedUnavailable({
    required String id,
    required DateTime occurredAt,
    required String playerId,
    String? note,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.playerMarkedUnavailable,
      occurredAt: occurredAt,
      playerId: playerId,
      note: note,
    );
  }

  factory AuctionEvent.eventReverted({
    required String id,
    required DateTime occurredAt,
    required String targetEventId,
  }) {
    return AuctionEvent._(
      id: id,
      type: AuctionEventType.eventReverted,
      occurredAt: occurredAt,
      targetEventId: targetEventId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      if (playerId != null) 'player_id': playerId,
      if (teamId != null) 'team_id': teamId,
      if (amount != null) 'amount': amount,
      if (targetEventId != null) 'target_event_id': targetEventId,
      if (note != null) 'note': note,
    };
  }

  factory AuctionEvent.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final type = AuctionEventType.values.where((item) => item.name == rawType);
    if (type.isEmpty) {
      throw FormatException('Tipo evento non valido: $rawType');
    }

    final rawDate = json['occurred_at'];
    final occurredAt = rawDate is DateTime
        ? rawDate.toUtc()
        : DateTime.parse(rawDate.toString()).toUtc();

    return AuctionEvent._(
      id: json['id'].toString(),
      type: type.first,
      occurredAt: occurredAt,
      playerId: json['player_id']?.toString(),
      teamId: json['team_id']?.toString(),
      amount: (json['amount'] as num?)?.toInt(),
      targetEventId: json['target_event_id']?.toString(),
      note: json['note']?.toString(),
    );
  }
}
