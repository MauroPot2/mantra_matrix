import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';

class AuctionJoinPreview {
  final String sessionId;
  final String sessionName;
  final String joinCode;
  final List<FantasyTeamEntity> teams;
  final Set<String> claimedTeamIds;

  const AuctionJoinPreview({
    required this.sessionId,
    required this.sessionName,
    required this.joinCode,
    required this.teams,
    required this.claimedTeamIds,
  });

  List<FantasyTeamEntity> get availableTeams => teams
      .where((team) => !claimedTeamIds.contains(team.id))
      .toList(growable: false);
}
