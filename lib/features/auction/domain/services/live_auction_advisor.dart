import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_engine.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';

/// Collega lo stato della sessione al motore decisionale.
///
/// La UI deve conoscere soltanto la sessione e l'id della propria squadra:
/// il giocatore chiamato, il prezzo e le alternative vengono ricavati dal log.
class LiveAuctionAdvisor {
  final AuctionEngine engine;
  final AuctionSessionService sessionService;

  const LiveAuctionAdvisor({
    this.engine = const AuctionEngine(),
    this.sessionService = const AuctionSessionService(),
  });

  AuctionRecommendation evaluate({
    required AuctionSession session,
    required String myTeamId,
  }) {
    final state = sessionService.snapshot(session);
    final player = state.activePlayer;
    final myTeam = state.teamsById[myTeamId];

    if (player == null) {
      throw const AuctionSessionException(
        'Nessun giocatore chiamato da valutare.',
      );
    }
    if (myTeam == null) {
      throw AuctionSessionException('Squadra $myTeamId inesistente.');
    }

    return engine.evaluate(
      player: player,
      myTeam: myTeam,
      config: session.config,
      availablePlayers: state.availablePlayers,
      catalogPlayers: session.initialPlayers,
      currentBid: state.currentBid,
    );
  }
}
