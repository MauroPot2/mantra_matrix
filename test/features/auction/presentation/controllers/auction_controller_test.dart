import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import '../../../../helpers/in_memory_auction_session_repository.dart';

void main() {
  test('controller coordina chiamata, consiglio, assegnazione e undo', () async {
    final repository = InMemoryAuctionSessionRepository();
    final container = ProviderContainer(
      overrides: [
        auctionSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auctionControllerProvider.notifier);
    controller.startSession(
      sessionName: 'Asta test',
      myTeamId: 'me',
      config: const AuctionConfig(
        initialCredits: 100,
        rosterSize: 3,
        minimumBid: 1,
        targetCoverage: {MantraRole.pc: 1},
      ),
      players: [player('p1'), player('p2')],
      teams: const [
        FantasyTeamEntity(
          id: 'me',
          name: 'Matrix FC',
          creditsRemaining: 100,
        ),
        FantasyTeamEntity(
          id: 'rival',
          name: 'Rival FC',
          creditsRemaining: 100,
        ),
      ],
    );
    await readyForCommands(controller);

    controller.nominatePlayer('p1');
    expect(container.read(auctionControllerProvider).snapshot!.activePlayerId, 'p1');
    expect(container.read(auctionControllerProvider).recommendation, isNotNull);

    controller.setCurrentBid(12);
    controller.assignActivePlayer('me');

    var state = container.read(auctionControllerProvider);
    expect(state.snapshot!.teamsById['me']!.creditsRemaining, 88);
    expect(state.snapshot!.playersById['p1']!.status, DraftStatus.drafted);
    expect(state.recommendation, isNull);

    controller.undoLast();
    state = container.read(auctionControllerProvider);
    expect(state.snapshot!.teamsById['me']!.creditsRemaining, 100);
    expect(state.snapshot!.activePlayerId, 'p1');
    expect(state.snapshot!.currentBid, 12);
    expect(state.recommendation, isNotNull);
  });

  test('controller espone un errore senza corrompere la sessione', () async {
    final repository = InMemoryAuctionSessionRepository();
    final container = ProviderContainer(
      overrides: [
        auctionSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auctionControllerProvider.notifier);
    controller.startSession(
      sessionName: 'Asta test',
      myTeamId: 'me',
      config: const AuctionConfig(
        initialCredits: 10,
        rosterSize: 3,
        minimumBid: 1,
      ),
      players: [player('p1')],
      teams: const [
        FantasyTeamEntity(
          id: 'me',
          name: 'Matrix FC',
          creditsRemaining: 10,
        ),
      ],
    );
    await readyForCommands(controller);

    controller.nominatePlayer('p1');
    controller.setCurrentBid(9);
    controller.assignActivePlayer('me');

    final state = container.read(auctionControllerProvider);
    expect(state.errorMessage, contains('massimo 8 crediti'));
    expect(state.snapshot!.activePlayerId, 'p1');
    expect(state.snapshot!.teamsById['me']!.creditsRemaining, 10);
  });

  test('mantiene i nomi delle squadre e separa gli svincolati', () async {
    final repository = InMemoryAuctionSessionRepository();
    final container = ProviderContainer(
      overrides: [
        auctionSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auctionControllerProvider.notifier);
    controller.startSession(
      sessionName: 'Asta nominata',
      myTeamId: 'me',
      config: const AuctionConfig(
        initialCredits: 100,
        rosterSize: 3,
        minimumBid: 1,
      ),
      players: [player('p1'), player('p2')],
      teams: const [
        FantasyTeamEntity(
          id: 'me',
          name: 'Mantra Matrix',
          creditsRemaining: 100,
        ),
        FantasyTeamEntity(
          id: 'rival',
          name: 'Gli Svincolati',
          creditsRemaining: 100,
        ),
      ],
    );
    await readyForCommands(controller);

    var state = container.read(auctionControllerProvider);
    expect(
      state.snapshot!.teamsById.values.map((team) => team.name),
      ['Mantra Matrix', 'Gli Svincolati'],
    );

    controller.nominatePlayer('p1');
    controller.skipActivePlayer();
    state = container.read(auctionControllerProvider);

    expect(state.snapshot!.unsoldPlayers.single.id, 'p1');
    expect(state.snapshot!.uncalledPlayers.single.id, 'p2');
  });

  test('blocca i comandi ottimistici quando il dispositivo è viewer', () async {
    final repository = InMemoryAuctionSessionRepository(
      instanceId: 'viewer-instance',
      liveControllerInstanceId: 'other-controller',
    );
    final container = ProviderContainer(
      overrides: [
        auctionSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auctionControllerProvider.notifier);
    controller.startSession(
      sessionName: 'Asta viewer',
      myTeamId: 'me',
      config: const AuctionConfig(
        initialCredits: 100,
        rosterSize: 3,
        minimumBid: 1,
      ),
      players: [player('p1')],
      teams: const [
        FantasyTeamEntity(
          id: 'me',
          name: 'Matrix FC',
          creditsRemaining: 100,
        ),
      ],
    );
    await readyForCommands(controller);

    controller.nominatePlayer('p1');

    final state = container.read(auctionControllerProvider);
    expect(state.snapshot!.activePlayerId, isNull);
    expect(state.session!.events, isEmpty);
    expect(repository.appendedEvents, isEmpty);
    expect(state.errorMessage, contains('modalità viewer'));
  });

  test('apre una specifica asta selezionata dalla home', () async {
    final repository = InMemoryAuctionSessionRepository();
    final container = ProviderContainer(
      overrides: [
        auctionSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auctionControllerProvider.notifier);
    controller.startSession(
      sessionName: 'Asta da riprendere',
      myTeamId: 'me',
      config: const AuctionConfig(
        initialCredits: 500,
        rosterSize: 25,
        minimumBid: 1,
      ),
      players: [player('p1')],
      teams: const [
        FantasyTeamEntity(
          id: 'me',
          name: 'Matrix FC',
          creditsRemaining: 500,
        ),
      ],
    );

    await controller.waitForPendingPersistence();
    final sessionId = container.read(auctionControllerProvider).session!.id;

    controller.closeSession();
    expect(container.read(auctionControllerProvider).isStarted, isFalse);

    final opened = await controller.openSession(
      sessionId: sessionId,
      players: [player('p1')],
    );

    expect(opened, isTrue);
    final state = container.read(auctionControllerProvider);
    expect(state.isStarted, isTrue);
    expect(state.session!.name, 'Asta da riprendere');
  });
}

Future<void> readyForCommands(AuctionController controller) async {
  await controller.waitForPendingPersistence();
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
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
