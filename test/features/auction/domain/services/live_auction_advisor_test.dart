import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/auction/domain/services/live_auction_advisor.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const sessions = AuctionSessionService();
  const advisor = LiveAuctionAdvisor();

  test('usa giocatore e prezzo correnti della sessione', () {
    var session = AuctionSession(
      id: 's1',
      name: 'Asta',
      config: const AuctionConfig(
        initialCredits: 100,
        rosterSize: 3,
        minimumBid: 1,
        targetCoverage: {MantraRole.pc: 1},
      ),
      createdAt: DateTime.utc(2026, 7, 27),
      initialPlayers: [player('p1'), player('p2')],
      initialTeams: const [
        FantasyTeamEntity(id: 'me', name: 'Matrix FC', creditsRemaining: 100),
      ],
    );

    session = sessions.nominatePlayer(
      session,
      playerId: 'p1',
      eventId: 'e1',
      occurredAt: DateTime.utc(2026, 7, 27, 10),
    );
    session = sessions.changeCurrentBid(
      session,
      bid: 7,
      eventId: 'e2',
      occurredAt: DateTime.utc(2026, 7, 27, 10, 1),
    );

    final result = advisor.evaluate(session: session, myTeamId: 'me');

    expect(result.playerId, 'p1');
    expect(result.hardBudgetCeiling, 98);
    expect(result.maxBid, lessThan(7));
    expect(result.decision, AuctionDecision.pass);
    expect(result.risk, AuctionRisk.critical);
  });
}

PlayerEntity player(String id) {
  return PlayerEntity(
    id: id,
    name: 'Player $id',
    team: 'TEST',
    roles: const [MantraRole.pc],
    basePrice: 15,
    expectedGoals: 10,
    expectedAssists: 3,
    expectedGoals90: 0.4,
    expectedAssists90: 0.1,
    expectedYellowCards: 2,
    historicalMinutes: 2400,
    expectedPoints: 70,
    vorp: 8,
  );
}
