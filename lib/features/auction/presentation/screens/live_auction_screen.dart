import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_event.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/entities/mantra_formation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/role_market_availability.dart';
import 'package:mantra_matrix/features/auction/domain/entities/statistical_evidence.dart';
import 'package:mantra_matrix/features/auction/domain/services/formation_engine.dart';
import 'package:mantra_matrix/features/auction/domain/services/role_market_engine.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

enum _PlayerPoolFilter { uncalled, unsold, allAvailable }

class LiveAuctionScreen extends ConsumerStatefulWidget {
  const LiveAuctionScreen({super.key});

  @override
  ConsumerState<LiveAuctionScreen> createState() =>
      _LiveAuctionScreenState();
}

class _LiveAuctionScreenState extends ConsumerState<LiveAuctionScreen> {
  String? _selectedTeamId;
  int _mobileIndex = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      auctionControllerProvider.select((value) => value.errorMessage),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        ref.read(auctionControllerProvider.notifier).clearError();
      },
    );

    final state = ref.watch(auctionControllerProvider);
    final session = state.session;
    final snapshot = state.snapshot;

    if (session == null || snapshot == null || state.myTeamId == null) {
      return const Scaffold(
        body: Center(child: Text('Nessuna sessione attiva.')),
      );
    }

    final myTeam = snapshot.teamsById[state.myTeamId]!;
    // Manteniamo l'ordine inserito nel setup, utile durante la rotazione d'asta.
    final teams = snapshot.teamsById.values.toList(growable: false);
    final selectedTeamId = teams.any((team) => team.id == _selectedTeamId)
        ? _selectedTeamId!
        : state.myTeamId!;

    final teamPanel = _TeamCommandPanel(
      team: myTeam,
      session: session,
    );
    final auctionPanel = _AuctionCommandPanel(
      state: state,
      selectedTeamId: selectedTeamId,
      teams: teams,
      onTeamChanged: (value) => setState(() => _selectedTeamId = value),
      onPickPlayer: () => _showPlayerPicker(snapshot),
    );
    final marketPanel = _MarketCommandPanel(
      team: myTeam,
      session: session,
      snapshot: snapshot,
      canNominatePlayer: snapshot.activePlayer == null,
      onNominatePlayer: (playerId) {
        ref.read(auctionControllerProvider.notifier).nominatePlayer(playerId);
        if (MediaQuery.sizeOf(context).width < 820) {
          setState(() => _mobileIndex = 0);
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              '${snapshot.uncalledPlayers.length} da chiamare · '
              '${snapshot.unsoldPlayers.length} svincolati · '
              '${snapshot.draftedPlayers.length} assegnati',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Annulla ultima azione',
            onPressed: snapshot.lastReversibleEvent == null
                ? null
                : () => ref
                    .read(auctionControllerProvider.notifier)
                    .undoLast(),
            icon: const Icon(Icons.undo_rounded),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<_AuctionMenuAction>(
            onSelected: (action) {
              if (action == _AuctionMenuAction.closeSession) {
                _confirmCloseSession(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AuctionMenuAction.closeSession,
                child: Text('Chiudi sessione'),
              ),
            ],
          ),
          const AuthUserMenu(),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1180) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(child: teamPanel),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(child: auctionPanel),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 330,
                      child: SingleChildScrollView(child: marketPanel),
                    ),
                  ],
                ),
              );
            }

            if (constraints.maxWidth >= 820) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [teamPanel, const SizedBox(height: 14), marketPanel],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(child: auctionPanel),
                    ),
                  ],
                ),
              );
            }

            final pages = [auctionPanel, teamPanel, marketPanel];
            return Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _mobileIndex,
                    children: [
                      for (final page in pages)
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                          child: page,
                        ),
                    ],
                  ),
                ),
                NavigationBar(
                  selectedIndex: _mobileIndex,
                  onDestinationSelected: (index) {
                    setState(() => _mobileIndex = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.gavel_outlined),
                      selectedIcon: Icon(Icons.gavel),
                      label: 'Asta',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.shield_outlined),
                      selectedIcon: Icon(Icons.shield),
                      label: 'Rosa',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.radar_outlined),
                      selectedIcon: Icon(Icons.radar),
                      label: 'Mercato',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showPlayerPicker(AuctionSessionSnapshot snapshot) async {
    var query = '';
    MantraRole? roleFilter;
    var poolFilter = _PlayerPoolFilter.uncalled;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sourcePlayers = switch (poolFilter) {
              _PlayerPoolFilter.uncalled => snapshot.uncalledPlayers,
              _PlayerPoolFilter.unsold => snapshot.unsoldPlayers,
              _PlayerPoolFilter.allAvailable => snapshot.availablePlayers
                  .where((player) => player.id != snapshot.activePlayerId)
                  .toList(growable: false),
            };
            final normalized = query.trim().toLowerCase();
            final players = sourcePlayers
                .where((player) {
                  final matchesRole = roleFilter == null ||
                      player.roles.contains(roleFilter);
                  if (!matchesRole) return false;
                  if (normalized.isEmpty) return true;
                  final roles = player.roles.map((role) => role.name).join(' ');
                  return player.name.toLowerCase().contains(normalized) ||
                      player.team.toLowerCase().contains(normalized) ||
                      roles.contains(normalized);
                })
                .toList(growable: false)
              ..sort((a, b) => b.basePrice.compareTo(a.basePrice));

            return FractionallySizedBox(
              heightFactor: 0.92,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Giocatore chiamato',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_PlayerPoolFilter>(
                        segments: [
                          ButtonSegment(
                            value: _PlayerPoolFilter.uncalled,
                            icon: const Icon(Icons.playlist_play_rounded),
                            label: Text(
                              'Da chiamare ${snapshot.uncalledPlayers.length}',
                            ),
                          ),
                          ButtonSegment(
                            value: _PlayerPoolFilter.unsold,
                            icon: const Icon(Icons.replay_rounded),
                            label: Text(
                              'Svincolati ${snapshot.unsoldPlayers.length}',
                            ),
                          ),
                          ButtonSegment(
                            value: _PlayerPoolFilter.allAvailable,
                            icon: const Icon(Icons.all_inclusive_rounded),
                            label: Text(
                              'Tutti ${snapshot.availablePlayers.length}',
                            ),
                          ),
                        ],
                        selected: {poolFilter},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          setModalState(() => poolFilter = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Nome, squadra o ruolo',
                      ),
                      onChanged: (value) =>
                          setModalState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: const Text('Tutti i ruoli'),
                            selected: roleFilter == null,
                            onSelected: (_) =>
                                setModalState(() => roleFilter = null),
                          ),
                          const SizedBox(width: 7),
                          for (final role in MantraRole.values) ...[
                            ChoiceChip(
                              label: Text(role.name.toUpperCase()),
                              selected: roleFilter == role,
                              onSelected: (_) =>
                                  setModalState(() => roleFilter = role),
                            ),
                            const SizedBox(width: 7),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${players.length} risultati'),
                    const SizedBox(height: 6),
                    Expanded(
                      child: players.isEmpty
                          ? Center(
                              child: Text(
                                poolFilter == _PlayerPoolFilter.unsold
                                    ? 'Nessuno svincolato da richiamare.'
                                    : 'Nessun giocatore trovato.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: players.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final player = players[index];
                                final isUnsold = snapshot.isUnsold(player.id);
                                return ListTile(
                                  tileColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  leading: _RoleAvatar(player: player),
                                  title: Text(
                                    player.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${player.team} · ${_roles(player)}'
                                    '${isUnsold ? ' · già invenduto' : ''}',
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${player.basePrice}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const Text('FVM'),
                                    ],
                                  ),
                                  onTap: () {
                                    ref
                                        .read(auctionControllerProvider.notifier)
                                        .nominatePlayer(player.id);
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmCloseSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chiudere la sessione?'),
        content: const Text(
          'Assicurati che lo stato sia sincronizzato prima di uscire definitivamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Resta'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(auctionControllerProvider.notifier).closeSession();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _AuctionCommandPanel extends ConsumerWidget {
  final AuctionUiState state;
  final String selectedTeamId;
  final List<FantasyTeamEntity> teams;
  final ValueChanged<String?> onTeamChanged;
  final VoidCallback onPickPlayer;

  const _AuctionCommandPanel({
    required this.state,
    required this.selectedTeamId,
    required this.teams,
    required this.onTeamChanged,
    required this.onPickPlayer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = state.snapshot!;
    final player = snapshot.activePlayer;
    final recommendation = state.recommendation;

    if (player == null) {
      return _EmptyAuctionCard(
        remainingPlayers: snapshot.availablePlayers.length,
        onPickPlayer: onPickPlayer,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivePlayerHero(player: player, onChangePlayer: onPickPlayer),
        const SizedBox(height: 14),
        _BidControl(currentBid: snapshot.currentBid),
        const SizedBox(height: 14),
        if (recommendation != null) ...[
          _RecommendationCard(recommendation: recommendation),
          const SizedBox(height: 14),
        ],
        _AssignmentCard(
          selectedTeamId: selectedTeamId,
          teams: teams,
          onTeamChanged: onTeamChanged,
        ),
      ],
    );
  }
}

class _EmptyAuctionCard extends StatelessWidget {
  final int remainingPlayers;
  final VoidCallback onPickPlayer;

  const _EmptyAuctionCard({
    required this.remainingPlayers,
    required this.onPickPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
              theme.colorScheme.tertiaryContainer.withValues(alpha: 0.58),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.70),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_rounded, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              'Chi è stato chiamato?',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$remainingPlayers giocatori ancora sul mercato',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPickPlayer,
              icon: const Icon(Icons.search),
              label: const Text('Apri ricerca rapida'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivePlayerHero extends StatelessWidget {
  final PlayerEntity player;
  final VoidCallback onChangePlayer;

  const _ActivePlayerHero({
    required this.player,
    required this.onChangePlayer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _RoleAvatar(player: player, large: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${player.team} · ${_roles(player)}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _InfoPill(label: 'FVM ${player.basePrice}'),
                      if (player.isPenaltyTaker)
                        const _InfoPill(label: 'Rigorista', icon: Icons.adjust),
                      if (player.isInjured)
                        const _InfoPill(
                          label: 'Infortunato',
                          icon: Icons.healing,
                          warning: true,
                        ),
                      if (player.isSuspended)
                        const _InfoPill(
                          label: 'Squalificato',
                          icon: Icons.block,
                          warning: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Cambia giocatore',
              onPressed: onChangePlayer,
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
        ),
      ),
    );
  }
}

class _BidControl extends ConsumerStatefulWidget {
  final int currentBid;

  const _BidControl({required this.currentBid});

  @override
  ConsumerState<_BidControl> createState() => _BidControlState();
}

class _BidControlState extends ConsumerState<_BidControl> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentBid.toString());
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _BidControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentBid != widget.currentBid && !_focusNode.hasFocus) {
      _controller.text = widget.currentBid.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department_outlined),
                const SizedBox(width: 9),
                Text(
                  'Offerta corrente',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text('${widget.currentBid} cr'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _BidButton(
                  label: '−1',
                  onPressed: () => _changeBy(-1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: 'cr',
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Conferma importo',
                  onPressed: _commit,
                  icon: const Icon(Icons.check),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _BidButton(
                    label: '+1',
                    onPressed: () => _changeBy(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BidButton(
                    label: '+5',
                    highlighted: true,
                    onPressed: () => _changeBy(5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BidButton(
                    label: '+10',
                    highlighted: true,
                    onPressed: () => _changeBy(10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null) return;
    ref.read(auctionControllerProvider.notifier).setCurrentBid(parsed);
    _focusNode.unfocus();
  }

  void _changeBy(int amount) {
    final current = int.tryParse(_controller.text) ?? widget.currentBid;
    final session = ref.read(auctionControllerProvider).session;
    final minimum = session?.config.minimumBid ?? 1;
    final next = (current + amount).clamp(minimum, 1 << 30).toInt();
    _controller.text = next.toString();
    ref.read(auctionControllerProvider.notifier).setCurrentBid(next);
  }
}

class _BidButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool highlighted;

  const _BidButton({
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return highlighted
        ? FilledButton.tonal(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

class _RecommendationCard extends StatelessWidget {
  final AuctionRecommendation recommendation;

  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _decisionColor(recommendation.decision, theme.colorScheme);
    final evidence = recommendation.statisticalEvidence;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _decisionLabel(recommendation.decision),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                _RiskBadge(risk: recommendation.risk),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth >= 560
                        ? (constraints.maxWidth - 24) / 3
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricTile(
                          width: itemWidth,
                          label: 'FVM adattato',
                          value: '${recommendation.scaledCatalogValue}',
                          icon: Icons.sell_outlined,
                        ),
                        _MetricTile(
                          width: itemWidth,
                          label: 'Valore strategico',
                          value: '${recommendation.fairValue}',
                          icon: Icons.auto_graph,
                        ),
                        _MetricTile(
                          width: itemWidth,
                          label: 'Tetto consigliato',
                          value: '${recommendation.maxBid}',
                          icon: Icons.vertical_align_top,
                          emphasized: true,
                        ),
                        _MetricTile(
                          width: itemWidth,
                          label: 'Affidabilità',
                          value: '${(recommendation.confidence * 100).round()}%',
                          icon: Icons.verified_outlined,
                        ),
                        if (evidence != null)
                          _MetricTile(
                            width: itemWidth,
                            label: 'Percentile',
                            value: '${evidence.percentileRounded}°',
                            icon: Icons.leaderboard_outlined,
                          ),
                        if (recommendation.department != null)
                          _MetricTile(
                            width: itemWidth,
                            label: 'Piano ${recommendation.department!.shortLabel}',
                            value:
                                '${recommendation.departmentSpent}/${recommendation.departmentBudget}',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (recommendation.reasons.isNotEmpty)
                  _MessageBlock(
                    title: 'Perché',
                    icon: Icons.lightbulb_outline,
                    messages: recommendation.reasons,
                  ),
                if (recommendation.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _MessageBlock(
                    title: 'Attenzione',
                    icon: Icons.warning_amber_rounded,
                    messages: recommendation.warnings,
                    warning: true,
                  ),
                ],
                if (evidence != null) ...[
                  const SizedBox(height: 12),
                  _EvidenceExpansion(evidence: evidence),
                ],
                if (recommendation.roleMarkets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _CandidateMarketStrip(markets: recommendation.roleMarkets),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends ConsumerWidget {
  final String selectedTeamId;
  final List<FantasyTeamEntity> teams;
  final ValueChanged<String?> onTeamChanged;

  const _AssignmentCard({
    required this.selectedTeamId,
    required this.teams,
    required this.onTeamChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = teams.firstWhere((team) => team.id == selectedTeamId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Esito chiamata',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedTeamId),
              initialValue: selectedTeamId,
              decoration: const InputDecoration(
                labelText: 'Squadra acquirente',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              items: teams
                  .map(
                    (team) => DropdownMenuItem(
                      value: team.id,
                      child: Text(
                        '${team.name} · ${team.creditsRemaining} cr',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onTeamChanged,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref
                  .read(auctionControllerProvider.notifier)
                  .assignActivePlayer(selectedTeamId),
              icon: const Icon(Icons.gavel),
              label: Text('Assegna a ${selected.name}'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(auctionControllerProvider.notifier)
                        .skipActivePlayer(),
                    icon: const Icon(Icons.redo),
                    label: const Text('Svincolato'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(auctionControllerProvider.notifier)
                        .markActivePlayerUnavailable(),
                    icon: const Icon(Icons.block),
                    label: const Text('Escludi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCommandPanel extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;
  const _TeamCommandPanel({
    required this.team,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slotsRemaining = team.slotsRemaining(session.config);
    final spent = session.config.initialCredits - team.creditsRemaining;
    final formations = const FormationEngine().analyzeRoster(team.roster);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text('${team.roster.length}/${session.config.rosterSize} giocatori'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MiniKpi(
                        label: 'Residui',
                        value: '${team.creditsRemaining}',
                      ),
                    ),
                    Expanded(
                      child: _MiniKpi(label: 'Spesi', value: '$spent'),
                    ),
                    Expanded(
                      child: _MiniKpi(
                        label: 'Slot',
                        value: '$slotsRemaining',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _DepartmentPlanCard(team: team, session: session),
        const SizedBox(height: 14),
        _RoleCoverageCard(team: team, session: session),
        const SizedBox(height: 14),
        _FormationCard(
          analyses: formations,
          primary: session.config.primaryFormationName,
          secondary: session.config.secondaryFormationNames,
        ),
        const SizedBox(height: 14),
        _RecentRosterCard(team: team),
      ],
    );
  }
}

class _DepartmentPlanCard extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;

  const _DepartmentPlanCard({required this.team, required this.session});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Piano reparti',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        children: [
          for (final department in PlayerDepartment.values) ...[
            Builder(
              builder: (context) {
                final budget = session.config.departmentBudgetFor(department);
                final spent = team.roster
                    .where(
                      (player) =>
                          PlayerDepartmentX.forPlayer(player) == department,
                    )
                    .fold(0, (sum, player) => sum + (player.purchasePrice ?? 0));
                final progress = budget == 0
                    ? 0.0
                    : (spent / budget).clamp(0.0, 1.0).toDouble();
                final exceeded = spent > budget;
                return Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            department.shortLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              color: exceeded
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('$spent/$budget'),
                      ],
                    ),
                    if (department != PlayerDepartment.values.last)
                      const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleCoverageCard extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;

  const _RoleCoverageCard({required this.team, required this.session});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Copertura ruoli',
      icon: Icons.grid_view_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final role in MantraRole.values)
            Builder(
              builder: (context) {
                final current = team.coverageFor(role);
                final target = session.config.targetCoverage[role] ?? 0;
                final complete = target > 0 && current >= target;
                return Container(
                  width: 74,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: complete
                        ? Colors.green.withValues(alpha: 0.13)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      Text(
                        role.name.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('$current/$target'),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _FormationCard extends StatelessWidget {
  final List<MantraFormationAnalysis> analyses;
  final String primary;
  final Set<String> secondary;

  const _FormationCard({
    required this.analyses,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...analyses]
      ..sort((a, b) {
        final aPriority = a.formation.name == primary
            ? 0
            : secondary.contains(a.formation.name)
                ? 1
                : 2;
        final bPriority = b.formation.name == primary
            ? 0
            : secondary.contains(b.formation.name)
                ? 1
                : 2;
        final priority = aPriority.compareTo(bPriority);
        if (priority != 0) return priority;
        return a.missingSlots.compareTo(b.missingSlots);
      });

    final visible = sorted.take(6).toList(growable: false);
    return _SectionCard(
      title: 'Moduli',
      icon: Icons.schema_outlined,
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            Builder(
              builder: (context) {
                final analysis = visible[index];
                return Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        analysis.formation.name == primary
                            ? '★'
                            : secondary.contains(analysis.formation.name)
                                ? '◇'
                                : '',
                      ),
                    ),
                    Expanded(child: Text(analysis.formation.name)),
                    Text(
                      analysis.isPlayable
                          ? 'PRONTO'
                          : '−${analysis.missingSlots}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color:
                            analysis.isPlayable ? Colors.green.shade500 : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (index < visible.length - 1) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class _RecentRosterCard extends StatelessWidget {
  final FantasyTeamEntity team;

  const _RecentRosterCard({required this.team});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Ultimi acquisti',
      icon: Icons.history,
      child: team.roster.isEmpty
          ? const Text('Nessun acquisto effettuato.')
          : Column(
              children: [
                for (final player in team.roster.reversed.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _RoleAvatar(player: player),
                    title: Text(player.name),
                    subtitle: Text(_roles(player)),
                    trailing: Text(
                      '${player.purchasePrice ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MarketCommandPanel extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;
  final AuctionSessionSnapshot snapshot;
  final bool canNominatePlayer;
  final ValueChanged<String> onNominatePlayer;

  const _MarketCommandPanel({
    required this.team,
    required this.session,
    required this.snapshot,
    required this.canNominatePlayer,
    required this.onNominatePlayer,
  });

  @override
  Widget build(BuildContext context) {
    final markets = const RoleMarketEngine().analyzeAllRoles(
      availablePlayers: snapshot.availablePlayers,
      catalogPlayers: session.initialPlayers,
    );

    final teams = snapshot.teamsById.values.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuctionProgressCard(snapshot: snapshot),
        const SizedBox(height: 14),
        _AuctionTimelineCard(session: session, snapshot: snapshot),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Radar mercato',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ruoli in ordine Mantra. Apri una scheda per vedere i top ancora disponibili.',
                ),
                const SizedBox(height: 16),
                for (final market in markets) ...[
                  _RoleMarketRow(
                    market: market,
                    missing: team.missingCoverageFor(
                      market.role,
                      session.config,
                    ),
                    initialCredits: session.config.initialCredits,
                    valuationReferenceCredits:
                        session.config.valuationReferenceCredits,
                    canNominatePlayer: canNominatePlayer,
                    onNominatePlayer: onNominatePlayer,
                  ),
                  if (market != markets.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _UnsoldPlayersCard(
          players: snapshot.unsoldPlayers,
          canNominatePlayer: canNominatePlayer,
          onNominatePlayer: onNominatePlayer,
        ),
        const SizedBox(height: 14),
        _TeamsOverviewCard(
          teams: teams,
          rosterSize: session.config.rosterSize,
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Strategia attiva',
          icon: Icons.route_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StrategyLine(
                symbol: '★',
                label: 'Principale',
                value: session.config.primaryFormationName,
              ),
              const SizedBox(height: 12),
              _StrategyLine(
                symbol: '◇',
                label: 'Alternative',
                value: session.config.secondaryFormationNames.isEmpty
                    ? 'Nessuna'
                    : session.config.secondaryFormationNames.join(' · '),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuctionTimelineCard extends StatelessWidget {
  final AuctionSession session;
  final AuctionSessionSnapshot snapshot;

  const _AuctionTimelineCard({
    required this.session,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final outcomes = session.events
        .where(
          (event) =>
              !event.isReversion &&
              !snapshot.revertedEventIds.contains(event.id) &&
              (event.type == AuctionEventType.playerAssigned ||
                  event.type == AuctionEventType.playerSkipped ||
                  event.type == AuctionEventType.playerMarkedUnavailable),
        )
        .toList(growable: false)
        .reversed
        .take(10)
        .toList(growable: false);

    return _SectionCard(
      title: 'Cronologia esiti',
      icon: Icons.receipt_long_outlined,
      child: outcomes.isEmpty
          ? const Text('Nessuna chiamata ancora conclusa.')
          : Column(
              children: [
                for (var index = 0; index < outcomes.length; index++) ...[
                  _AuctionOutcomeTile(
                    event: outcomes[index],
                    snapshot: snapshot,
                  ),
                  if (index < outcomes.length - 1) const Divider(height: 10),
                ],
              ],
            ),
    );
  }
}

class _AuctionOutcomeTile extends StatelessWidget {
  final AuctionEvent event;
  final AuctionSessionSnapshot snapshot;

  const _AuctionOutcomeTile({
    required this.event,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final player = snapshot.playersById[event.playerId];
    final team = snapshot.teamsById[event.teamId];

    final (icon, label, detail) = switch (event.type) {
      AuctionEventType.playerAssigned => (
          Icons.gavel_rounded,
          'Assegnato',
          '${team?.name ?? 'Squadra sconosciuta'} · ${event.amount ?? 0} cr',
        ),
      AuctionEventType.playerSkipped => (
          Icons.replay_rounded,
          'Svincolato',
          'Richiamabile dalla lista dedicata',
        ),
      AuctionEventType.playerMarkedUnavailable => (
          Icons.block_rounded,
          'Escluso',
          event.note?.trim().isNotEmpty == true
              ? event.note!.trim()
              : 'Rimosso dal mercato',
        ),
      _ => (Icons.circle_outlined, 'Evento', ''),
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(
        player?.name ?? 'Giocatore sconosciuto',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(detail),
      trailing: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _AuctionProgressCard extends StatelessWidget {
  final AuctionSessionSnapshot snapshot;

  const _AuctionProgressCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Avanzamento asta',
      icon: Icons.timeline_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth >= 380
              ? (constraints.maxWidth - 16) / 3
              : constraints.maxWidth;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProgressMetric(
                width: itemWidth,
                icon: Icons.playlist_play_rounded,
                value: snapshot.uncalledPlayers.length,
                label: 'Da chiamare',
              ),
              _ProgressMetric(
                width: itemWidth,
                icon: Icons.replay_rounded,
                value: snapshot.unsoldPlayers.length,
                label: 'Svincolati',
              ),
              _ProgressMetric(
                width: itemWidth,
                icon: Icons.how_to_reg_rounded,
                value: snapshot.draftedPlayers.length,
                label: 'Assegnati',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final double width;
  final IconData icon;
  final int value;
  final String label;

  const _ProgressMetric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 5),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _UnsoldPlayersCard extends StatelessWidget {
  final List<PlayerEntity> players;
  final bool canNominatePlayer;
  final ValueChanged<String> onNominatePlayer;

  const _UnsoldPlayersCard({
    required this.players,
    required this.canNominatePlayer,
    required this.onNominatePlayer,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Svincolati dopo la chiamata',
      icon: Icons.replay_circle_filled_outlined,
      child: players.isEmpty
          ? const Text(
              'Nessun invenduto. Quando una chiamata termina senza acquisto, '
              'il giocatore comparirà qui e uscirà dalla lista principale.',
            )
          : Column(
              children: [
                for (final player in players.reversed) ...[
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _RoleAvatar(player: player),
                    title: Text(
                      player.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${player.team} · ${_roles(player)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FVM ${player.basePrice}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Richiama ${player.name}',
                          onPressed: canNominatePlayer
                              ? () => onNominatePlayer(player.id)
                              : null,
                          icon: const Icon(Icons.gavel_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                  if (player != players.first) const Divider(height: 8),
                ],
              ],
            ),
    );
  }
}

class _TeamsOverviewCard extends StatelessWidget {
  final List<FantasyTeamEntity> teams;
  final int rosterSize;

  const _TeamsOverviewCard({
    required this.teams,
    required this.rosterSize,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Squadre e rose',
      icon: Icons.groups_2_outlined,
      child: Column(
        children: [
          for (final team in teams)
            ExpansionTile(
              key: PageStorageKey('team-roster-${team.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 10),
              leading: CircleAvatar(
                child: Text(
                  team.name.trim().isEmpty
                      ? '?'
                      : team.name.trim().characters.first.toUpperCase(),
                ),
              ),
              title: Text(
                team.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${team.creditsRemaining} cr · '
                '${team.roster.length}/$rosterSize giocatori',
              ),
              children: [
                if (team.roster.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Nessun giocatore assegnato.'),
                  )
                else
                  for (final player in team.roster)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 8),
                      leading: _RoleAvatar(player: player),
                      title: Text(player.name),
                      subtitle: Text('${player.team} · ${_roles(player)}'),
                      trailing: Text(
                        '${player.purchasePrice ?? 0} cr',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RoleMarketRow extends StatelessWidget {
  final RoleMarketAvailability market;
  final int missing;
  final int initialCredits;
  final int valuationReferenceCredits;
  final bool canNominatePlayer;
  final ValueChanged<String> onNominatePlayer;

  const _RoleMarketRow({
    required this.market,
    required this.missing,
    required this.initialCredits,
    required this.valuationReferenceCredits,
    required this.canNominatePlayer,
    required this.onNominatePlayer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = missing > 0 && market.remainingTopPlayers <= 2;
    final topPlayers = market.remainingTopPlayerEntries;

    return Material(
      color: urgent
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.42)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('market-${market.role.name}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(11, 0, 11, 12),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            market.role.name.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${market.remainingPlayers} rimasti',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (urgent)
              Icon(
                Icons.priority_high_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
          ],
        ),
        subtitle: Text(
          '${market.remainingTopPlayers} top · ti mancano $missing',
        ),
        children: [
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top ancora disponibili',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                market.topCutoffCatalogValue > 0
                    ? 'Soglia FVM ${market.topCutoffCatalogValue}'
                    : 'Nessuna soglia',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (topPlayers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Nessun top rimasto per questo ruolo.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (var index = 0; index < topPlayers.length; index++) ...[
              _TopMarketPlayerTile(
                rank: index + 1,
                player: topPlayers[index],
                scaledValue: _scaledValue(topPlayers[index].basePrice),
                canNominate: canNominatePlayer,
                onNominate: () => onNominatePlayer(topPlayers[index].id),
              ),
              if (index < topPlayers.length - 1) const Divider(height: 8),
            ],
        ],
      ),
    );
  }

  int _scaledValue(int catalogValue) {
    if (valuationReferenceCredits <= 0) return catalogValue;
    return (catalogValue * initialCredits / valuationReferenceCredits).round();
  }
}

class _TopMarketPlayerTile extends StatelessWidget {
  final int rank;
  final PlayerEntity player;
  final int scaledValue;
  final bool canNominate;
  final VoidCallback onNominate;

  const _TopMarketPlayerTile({
    required this.rank,
    required this.player,
    required this.scaledValue,
    required this.canNominate,
    required this.onNominate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = player.roles
        .map((role) => role.name.toUpperCase())
        .join('/');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(
        player.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${player.team} · $roles\n'
        'FVM ${player.basePrice} · ≈ $scaledValue cr',
      ),
      isThreeLine: true,
      trailing: IconButton.filledTonal(
        tooltip: canNominate
            ? 'Chiama ${player.name}'
            : 'Concludi prima la chiamata attiva',
        onPressed: canNominate ? onNominate : null,
        icon: const Icon(Icons.gavel_rounded, size: 19),
      ),
    );
  }
}

class _EvidenceExpansion extends StatelessWidget {
  final StatisticalEvidence evidence;

  const _EvidenceExpansion({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(Icons.query_stats),
      title: const Text('Affidabilità statistica'),
      subtitle: Text(
        '${evidence.qualityLabel} · affidabilità ${evidence.reliabilityLabel.toLowerCase()}',
      ),
      children: [
        const SizedBox(height: 8),
        _DetailRow(label: 'Metrica', value: evidence.metricSourceLabel),
        _DetailRow(
          label: 'Confronto',
          value:
              '${evidence.peerCount} ${evidence.comparisonRole.name.toUpperCase()}',
        ),
        _DetailRow(
          label: 'Campione',
          value: '${evidence.historicalMinutes} minuti',
        ),
        if (evidence.strengths.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final strength in evidence.strengths)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('✓ $strength'),
            ),
        ],
      ],
    );
  }
}

class _CandidateMarketStrip extends StatelessWidget {
  final List<RoleMarketAvailability> markets;

  const _CandidateMarketStrip({required this.markets});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mercato nei suoi ruoli',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final market in markets)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '${market.role.name.toUpperCase()} · '
                  '${market.remainingPlayers} rim · '
                  '${market.remainingTopPlayers} top',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final bool emphasized;

  const _MetricTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: emphasized
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> messages;
  final bool warning;

  const _MessageBlock({
    required this.title,
    required this.icon,
    required this.messages,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: warning
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.34)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $message'),
            ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final AuctionRisk risk;

  const _RiskBadge({required this.risk});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: _riskColor(risk)),
        const SizedBox(width: 5),
        Text(
          _riskLabel(risk),
          style: TextStyle(
            color: _riskColor(risk),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _RoleAvatar extends StatelessWidget {
  final PlayerEntity player;
  final bool large;

  const _RoleAvatar({required this.player, this.large = false});

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 44.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.tertiary,
          ],
        ),
        borderRadius: BorderRadius.circular(large ? 20 : 14),
      ),
      child: Text(
        player.roles.first.name.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: large ? 17 : 12,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool warning;

  const _InfoPill({
    required this.label,
    this.icon,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: warning
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14),
            const SizedBox(width: 4),
          ],
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;

  const _MiniKpi({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _StrategyLine extends StatelessWidget {
  final String symbol;
  final String label;
  final String value;

  const _StrategyLine({
    required this.symbol,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 24, child: Text(symbol)),
        SizedBox(width: 82, child: Text(label)),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

enum _AuctionMenuAction { closeSession }

String _roles(PlayerEntity player) =>
    player.roles.map((role) => role.name.toUpperCase()).join('/');

String _decisionLabel(AuctionDecision decision) => switch (decision) {
      AuctionDecision.strongBuy => 'COMPRA FORTE',
      AuctionDecision.buy => 'COMPRA',
      AuctionDecision.wait => 'ATTENDI',
      AuctionDecision.pass => 'LASCIA',
      AuctionDecision.unavailable => 'NON DISPONIBILE',
    };

String _riskLabel(AuctionRisk risk) => switch (risk) {
      AuctionRisk.low => 'Rischio basso',
      AuctionRisk.medium => 'Rischio medio',
      AuctionRisk.high => 'Rischio alto',
      AuctionRisk.critical => 'Rischio critico',
    };

Color _decisionColor(AuctionDecision decision, ColorScheme colors) =>
    switch (decision) {
      AuctionDecision.strongBuy => Colors.green.shade700,
      AuctionDecision.buy => colors.primary,
      AuctionDecision.wait => Colors.orange.shade800,
      AuctionDecision.pass => colors.error,
      AuctionDecision.unavailable => colors.outline,
    };

Color _riskColor(AuctionRisk risk) => switch (risk) {
      AuctionRisk.low => Colors.green.shade500,
      AuctionRisk.medium => Colors.orange.shade500,
      AuctionRisk.high => Colors.deepOrange.shade500,
      AuctionRisk.critical => Colors.red.shade600,
    };
