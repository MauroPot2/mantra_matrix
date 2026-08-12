import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_session_service.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const service = AuctionSessionService();

  group('shared auction clock', () {
    test('config defaults to 15 seconds and +5 per raise', () {
      const config = AuctionConfig(
        initialCredits: 500,
        rosterSize: 25,
        minimumBid: 1,
      );

      expect(config.countdownSeconds, 15);
      expect(config.bidExtensionSeconds, 5);

      final restored = AuctionConfig.fromJson(config.toJson());
      expect(restored.countdownSeconds, 15);
      expect(restored.bidExtensionSeconds, 5);
    });

    test('old config json receives safe timer defaults', () {
      final config = AuctionConfig.fromJson({
        'initial_credits': 500,
        'valuation_reference_credits': 1000,
        'roster_size': 25,
        'minimum_bid': 1,
      });

      expect(config.countdownSeconds, 15);
      expect(config.bidExtensionSeconds, 5);
    });

    test('one real raise adds exactly one +5 extension event', () {
      var session = _session();
      session = service.nominatePlayer(
        session,
        playerId: 'p1',
        eventId: 'nomination',
        occurredAt: DateTime.utc(2026, 8, 10, 12),
      );
      session = service.raiseCurrentBid(
        session,
        bid: 10,
        eventId: 'raise',
        occurredAt: DateTime.utc(2026, 8, 10, 12, 0, 3),
      );

      final raise = session.events.last;
      expect(raise.type.name, 'bidRaised');
      expect(raise.amount, 10);
      expect(raise.clockExtensionSeconds, 5);
      expect(service.snapshot(session).currentBid, 10);
    });

    test('manual bid correction never extends the clock', () {
      var session = _session();
      session = service.nominatePlayer(
        session,
        playerId: 'p1',
        eventId: 'nomination',
        occurredAt: DateTime.utc(2026, 8, 10, 12),
      );
      session = service.changeCurrentBid(
        session,
        bid: 7,
        eventId: 'correction',
        occurredAt: DateTime.utc(2026, 8, 10, 12, 0, 2),
      );

      expect(session.events.last.clockExtensionSeconds, isNull);
    });

    test('clock deadline uses server start plus accumulated extensions', () {
      const config = AuctionConfig(
        initialCredits: 500,
        rosterSize: 25,
        minimumBid: 1,
        countdownSeconds: 15,
        bidExtensionSeconds: 5,
      );
      final start = DateTime.utc(2026, 8, 10, 12);
      final live = AuctionLiveState(
        phase: AuctionClockPhase.running,
        activePlayerId: 'p1',
        currentBid: 20,
        startedAt: start,
        extensionSeconds: 10,
        revision: 3,
        updatedAt: start,
        controllerInstanceId: 'controller-a',
      );

      expect(live.deadline(config), start.add(const Duration(seconds: 25)));
      expect(live.isControlledBy('controller-a'), isTrue);
      expect(live.isControlledBy('controller-b'), isFalse);
      expect(
        live.remaining(
          config,
          now: start.add(const Duration(seconds: 18)),
        ),
        const Duration(seconds: 7),
      );
      expect(
        live.remaining(
          config,
          now: start.add(const Duration(seconds: 30)),
        ),
        Duration.zero,
      );
    });
  });
}

AuctionSession _session() {
  return AuctionSession(
    id: 'clock-session',
    name: 'Clock test',
    config: const AuctionConfig(
      initialCredits: 500,
      rosterSize: 25,
      minimumBid: 1,
      countdownSeconds: 15,
      bidExtensionSeconds: 5,
    ),
    createdAt: DateTime.utc(2026, 8, 10),
    initialPlayers: [
      PlayerEntity(
        id: 'p1',
        name: 'Player One',
        team: 'TEST',
        roles: const [MantraRole.pc],
        basePrice: 1,
        expectedGoals: 0,
        expectedAssists: 0,
        expectedGoals90: 0,
        expectedAssists90: 0,
        expectedYellowCards: 0,
        historicalMinutes: 0,
      ),
    ],
    initialTeams: const [
      FantasyTeamEntity(
        id: 't1',
        name: 'Matrix FC',
        creditsRemaining: 500,
      ),
    ],
  );
}
