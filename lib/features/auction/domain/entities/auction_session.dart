import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/bid_snapshot.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/entities/roster_assignment.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

enum AuctionSessionStatus { setup, live, completed }

class AuctionSession {
  final String id;
  final String name;
  final AuctionConfig config;
  final DateTime createdAt;
  final AuctionSessionStatus status;
  final List<PlayerEntity> initialPlayers;
  final List<FantasyTeamEntity> initialTeams;
  final List<AuctionEvent> events;

  const AuctionSession({
    required this.id,
    required this.name,
    required this.config,
    required this.createdAt,
    required this.initialPlayers,
    required this.initialTeams,
    this.status = AuctionSessionStatus.live,
    this.events = const [],
  }) : assert(id != ''),
       assert(name != '');

  AuctionSession copyWith({
    String? id,
    String? name,
    AuctionConfig? config,
    DateTime? createdAt,
    AuctionSessionStatus? status,
    List<PlayerEntity>? initialPlayers,
    List<FantasyTeamEntity>? initialTeams,
    List<AuctionEvent>? events,
  }) {
    return AuctionSession(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      initialPlayers: initialPlayers ?? this.initialPlayers,
      initialTeams: initialTeams ?? this.initialTeams,
      events: events ?? this.events,
    );
  }
}

class AuctionSessionSnapshot {
  final Map<String, PlayerEntity> playersById;
  final Map<String, FantasyTeamEntity> teamsById;
  final Map<String, RosterAssignment> assignmentsByPlayerId;
  final Set<String> revertedEventIds;

  /// Giocatori che hanno concluso almeno una chiamata come invenduti e non
  /// sono stati successivamente richiamati, assegnati o esclusi.
  /// L'ordine segue l'ultima uscita dalla chiamata, dal meno al più recente.
  final List<String> unsoldPlayerIds;

  final String? activePlayerId;
  final BidSnapshot? activeBid;
  final AuctionEvent? lastReversibleEvent;

  AuctionSessionSnapshot({
    required Map<String, PlayerEntity> playersById,
    required Map<String, FantasyTeamEntity> teamsById,
    required Map<String, RosterAssignment> assignmentsByPlayerId,
    required Set<String> revertedEventIds,
    required List<String> unsoldPlayerIds,
    required this.activePlayerId,
    required this.activeBid,
    required this.lastReversibleEvent,
  }) : playersById = Map<String, PlayerEntity>.unmodifiable(playersById),
       teamsById = Map<String, FantasyTeamEntity>.unmodifiable(teamsById),
       assignmentsByPlayerId =
           Map<String, RosterAssignment>.unmodifiable(assignmentsByPlayerId),
       revertedEventIds = Set<String>.unmodifiable(revertedEventIds),
       unsoldPlayerIds = List<String>.unmodifiable(unsoldPlayerIds);

  PlayerEntity? get activePlayer => activePlayerId == null
      ? null
      : playersById[activePlayerId];

  int get currentBid => activeBid?.currentBid ?? 0;

  /// Tutti i giocatori ancora acquistabili, inclusi quelli già passati come
  /// invenduti e l'eventuale giocatore attualmente chiamato.
  List<PlayerEntity> get availablePlayers => playersById.values
      .where((player) => player.status == DraftStatus.available)
      .toList(growable: false);

  /// Giocatori mai chiusi come invenduti e non attualmente chiamati.
  /// È la lista principale da cui proseguire la consecutio dell'asta.
  List<PlayerEntity> get uncalledPlayers {
    final unsoldIds = unsoldPlayerIds.toSet();
    return playersById.values
        .where(
          (player) =>
              player.status == DraftStatus.available &&
              player.id != activePlayerId &&
              !unsoldIds.contains(player.id),
        )
        .toList(growable: false);
  }

  /// Giocatori ancora acquistabili che hanno già concluso una chiamata senza
  /// assegnazione. Sono richiamabili dalla lista dedicata.
  List<PlayerEntity> get unsoldPlayers => unsoldPlayerIds
      .map((id) => playersById[id])
      .whereType<PlayerEntity>()
      .where((player) => player.status == DraftStatus.available)
      .toList(growable: false);

  List<PlayerEntity> get draftedPlayers => playersById.values
      .where((player) => player.status == DraftStatus.drafted)
      .toList(growable: false);

  bool isUnsold(String playerId) => unsoldPlayerIds.contains(playerId);
}
