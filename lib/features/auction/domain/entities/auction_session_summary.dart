import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';

class AuctionSessionSummary {
  final String id;
  final String name;
  final AuctionSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String myTeamId;
  final int teamCount;
  final int initialCredits;
  final int rosterSize;

  const AuctionSessionSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.myTeamId,
    required this.teamCount,
    required this.initialCredits,
    required this.rosterSize,
  });

  bool get canResume => status == AuctionSessionStatus.live;
  bool get isCompleted => status == AuctionSessionStatus.completed;
}
