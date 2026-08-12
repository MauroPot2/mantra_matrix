import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/random_player_draw_service.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/auction_sharing_providers.dart';
import 'package:mantra_matrix/features/auction/presentation/widgets/auction_sharing_sheet.dart';
import 'package:mantra_matrix/features/auction/presentation/widgets/shared_auction_clock.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class IndependentLiveAuctionScreen extends ConsumerStatefulWidget {
  const IndependentLiveAuctionScreen({super.key});

  @override
  ConsumerState<IndependentLiveAuctionScreen> createState() =>
      _IndependentLiveAuctionScreenState();
}

class _IndependentLiveAuctionScreenState
    extends ConsumerState<IndependentLiveAuctionScreen> {
  final _search = TextEditingController();
  final _randomDraw = RandomPlayerDrawService();
  String _query = '';
  int _mobileSection = 0;
  String? _selectedTeamId;
  String? _selectionPlayerId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auctionControllerProvider);
    final session = state.session;
    final snapshot = state.snapshot;

    if (session == null || snapshot == null) {
      return const Scaffold(
        body: Center(child: Text('Nessuna asta attiva.')),
      );
    }

    ref.listen(auctionControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null && message != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        ref.read(auctionControllerProvider.notifier).clearError();
      }
    });

    final live = ref.watch(auctionLiveStateProvider(session.id)).asData?.value;
    final instanceId = ref.watch(auctionInstanceIdProvider);
    final canControl = live?.isControlledBy(instanceId) ?? false;
    final isOwner =
        ref.watch(auctionSessionOwnershipProvider(session.id)).asData?.value ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            _PersistenceLine(state: state),
          ],
        ),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Condividi asta',
              onPressed: () => _showSharing(session, snapshot, state.myTeamId!),
              icon: const Icon(Icons.group_add_outlined),
            ),
          IconButton(
            tooltip: 'Annulla ultima azione',
            onPressed: canControl && snapshot.lastReversibleEvent != null
                ? () => ref.read(auctionControllerProvider.notifier).undoLast()
                : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          if (isOwner)
            IconButton(
              tooltip: 'Concludi asta',
              onPressed: canControl ? () => _completeAuction(context) : null,
              icon: const Icon(Icons.flag_outlined),
            ),
          const AuthUserMenu(),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 1000
          ? NavigationBar(
              selectedIndex: _mobileSection,
              onDestinationSelected: (value) {
                setState(() => _mobileSection = value);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.gavel_rounded),
                  label: 'Asta',
                ),
                NavigationDestination(
                  icon: Icon(
                    session.config.usesRandomDraw
                        ? Icons.casino_outlined
                        : Icons.search_rounded,
                  ),
                  label: session.config.usesRandomDraw ? 'Estrai' : 'Chiamata',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.groups_2_outlined),
                  label: 'Rose',
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _ControlStrip(
              isOwner: isOwner,
              canControl: canControl,
              onClaim: isOwner
                  ? () => ref.read(auctionControllerProvider.notifier).claimControl()
                  : null,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 330,
                          child: _sourcePanel(
                            session,
                            snapshot,
                            canControl: canControl,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _cockpit(
                            session,
                            snapshot,
                            state,
                            canControl: canControl,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 320,
                          child: _teamsPanel(session, snapshot, state),
                        ),
                      ],
                    );
                  }

                  return switch (_mobileSection) {
                    0 => _cockpit(
                        session,
                        snapshot,
                        state,
                        canControl: canControl,
                      ),
                    1 => _sourcePanel(
                        session,
                        snapshot,
                        canControl: canControl,
                      ),
                    _ => _teamsPanel(session, snapshot, state),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePanel(
    AuctionSession session,
    AuctionSessionSnapshot snapshot, {
    required bool canControl,
  }) {
    if (session.config.callMode == AuctionCallMode.random) {
      return _RandomDrawPanel(
        remaining: snapshot.uncalledPlayers.length,
        unsold: snapshot.unsoldPlayers,
        hasActivePlayer: snapshot.activePlayerId != null,
        canControl: canControl,
        onDraw: () => _drawNext(snapshot),
        onRecallUnsold: (playerId) =>
            ref.read(auctionControllerProvider.notifier).nominatePlayer(playerId),
      );
    }

    final candidates = snapshot.availablePlayers
        .where((player) => player.id != snapshot.activePlayerId)
        .where(_matchesQuery)
        .toList(growable: false)
      ..sort((a, b) {
        final aUnsold = snapshot.isUnsold(a.id);
        final bUnsold = snapshot.isUnsold(b.id);
        if (aUnsold != bUnsold) return aUnsold ? 1 : -1;
        return a.name.compareTo(b.name);
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Cerca giocatore',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                '${snapshot.uncalledPlayers.length} mai chiamati',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text('${candidates.length} risultati'),
            ],
          ),
        ),
        Expanded(
          child: candidates.isEmpty
              ? const Center(child: Text('Nessun giocatore trovato.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final player = candidates[index];
                    return _PlayerTile(
                      player: player,
                      unsold: snapshot.isUnsold(player.id),
                      enabled: canControl && snapshot.activePlayerId == null,
                      onTap: () => ref
                          .read(auctionControllerProvider.notifier)
                          .nominatePlayer(player.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cockpit(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
    AuctionUiState state, {
    required bool canControl,
  }) {
    final active = snapshot.activePlayer;
    if (active == null) {
      return _WaitingCockpit(
        random: session.config.usesRandomDraw,
        remaining: snapshot.uncalledPlayers.length,
        canControl: canControl,
        onPrimary: session.config.usesRandomDraw
            ? () => _drawNext(snapshot)
            : () => setState(() => _mobileSection = 1),
      );
    }

    if (_selectionPlayerId != active.id) {
      _selectionPlayerId = active.id;
      _selectedTeamId = null;
    }

    final teams = snapshot.teamsById.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final playerCard = _ActivePlayerCard(player: active);
            final clock = SharedAuctionClock(session: session);
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  playerCard,
                  const SizedBox(height: 10),
                  clock,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: playerCard),
                const SizedBox(width: 12),
                clock,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _BidCockpit(
          currentBid: snapshot.currentBid,
          extensionSeconds: session.config.bidExtensionSeconds,
          enabled: canControl,
          onMinus: () => ref
              .read(auctionControllerProvider.notifier)
              .decrementBid(),
          onPlusOne: () => ref
              .read(auctionControllerProvider.notifier)
              .incrementBid(),
          onPlusFive: () => ref
              .read(auctionControllerProvider.notifier)
              .incrementBid(5),
          onPlusTen: () => ref
              .read(auctionControllerProvider.notifier)
              .incrementBid(10),
          onManual: () => _manualBid(
            context,
            currentBid: snapshot.currentBid,
            minimumBid: session.config.minimumBid,
          ),
        ),
        const SizedBox(height: 12),
        _AssignmentCard(
          teams: teams,
          currentValue: _selectedTeamId,
          currentBid: snapshot.currentBid,
          enabled: canControl,
          onChanged: (value) => setState(() => _selectedTeamId = value),
          onAssign: _selectedTeamId == null
              ? null
              : () => ref
                  .read(auctionControllerProvider.notifier)
                  .assignActivePlayer(_selectedTeamId!),
          onUnsold: () => ref
              .read(auctionControllerProvider.notifier)
              .skipActivePlayer(),
          onUnavailable: () => ref
              .read(auctionControllerProvider.notifier)
              .markActivePlayerUnavailable(),
        ),
        if (state.recommendation != null) ...[
          const SizedBox(height: 12),
          _RecommendationCard(recommendation: state.recommendation!),
        ],
      ],
    );
  }

  Widget _teamsPanel(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
    AuctionUiState state,
  ) {
    final teams = snapshot.teamsById.values.toList(growable: false)
      ..sort((a, b) {
        if (a.id == state.myTeamId) return -1;
        if (b.id == state.myTeamId) return 1;
        return a.name.compareTo(b.name);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        if (state.myTeamId != null && snapshot.teamsById[state.myTeamId] != null)
          _MyTeamCard(
            team: snapshot.teamsById[state.myTeamId]!,
            session: session,
          ),
        const SizedBox(height: 12),
        Text(
          'Tutte le rose',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        for (final team in teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TeamCard(team: team, session: session),
          ),
      ],
    );
  }

  void _drawNext(AuctionSessionSnapshot snapshot) {
    try {
      final player = _randomDraw.draw(snapshot);
      ref.read(auctionControllerProvider.notifier).nominatePlayer(player.id);
      if (MediaQuery.sizeOf(context).width < 1000 && mounted) {
        setState(() => _mobileSection = 0);
      }
    } on RandomPlayerDrawException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  bool _matchesQuery(PlayerEntity player) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return true;
    return player.name.toLowerCase().contains(query) ||
        player.team.toLowerCase().contains(query) ||
        player.roles.any((role) => role.name.toLowerCase().contains(query));
  }

  Future<void> _showSharing(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
    String myTeamId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AuctionSharingSheet(
          session: session,
          snapshot: snapshot,
          myTeamId: myTeamId,
        ),
      ),
    );
  }

  Future<void> _manualBid(
    BuildContext context, {
    required int currentBid,
    required int minimumBid,
  }) async {
    final controller = TextEditingController(text: currentBid.toString());
    final bid = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Imposta offerta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Crediti',
            helperText:
                'Solo un aumento reale aggiunge i secondi di rilancio.',
          ),
          onSubmitted: (_) {
            final value = int.tryParse(controller.text);
            if (value != null && value >= minimumBid) {
              Navigator.of(dialogContext).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null || value < minimumBid) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (bid != null && mounted) {
      ref.read(auctionControllerProvider.notifier).setCurrentBid(bid);
    }
  }

  Future<void> _completeAuction(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Concludere l’asta?'),
        content: const Text(
          'La sessione sarà chiusa soltanto dopo la conferma cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Concludi'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final controller = ref.read(auctionControllerProvider.notifier);
    controller.completeSession();
    await controller.waitForPendingPersistence();
    if (!mounted) return;
    if (ref.read(auctionControllerProvider).session == null) {
      Navigator.of(context).pop();
    }
  }
}

class _ControlStrip extends StatelessWidget {
  final bool isOwner;
  final bool canControl;
  final VoidCallback? onClaim;

  const _ControlStrip({
    required this.isOwner,
    required this.canControl,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: canControl
          ? colors.primaryContainer.withValues(alpha: 0.45)
          : colors.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(
            canControl ? Icons.sports_esports_rounded : Icons.visibility_rounded,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              canControl
                  ? 'CONTROLLER · questo dispositivo comanda l’asta'
                  : isOwner
                      ? 'VIEWER · segui il realtime oppure prendi il controllo'
                      : 'VIEWER · asta condivisa in sola lettura',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (!canControl && isOwner && onClaim != null)
            TextButton.icon(
              onPressed: onClaim,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Prendi controllo'),
            ),
        ],
      ),
    );
  }
}

class _WaitingCockpit extends StatelessWidget {
  final bool random;
  final int remaining;
  final bool canControl;
  final VoidCallback onPrimary;

  const _WaitingCockpit({
    required this.random,
    required this.remaining,
    required this.canControl,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Icon(
                random ? Icons.casino_outlined : Icons.campaign_outlined,
                size: 72,
              ),
              const SizedBox(height: 18),
              Text(
                random ? 'Pronto al sorteggio' : 'Pronto alla prossima chiamata',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                random
                    ? '$remaining giocatori ancora mai chiamati. Il prossimo nome non viene deciso finché non premi Estrai.'
                    : 'Scegli il giocatore dal pannello Chiamata.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: canControl && (!random || remaining > 0)
                    ? onPrimary
                    : null,
                icon: Icon(random ? Icons.casino_rounded : Icons.search_rounded),
                label: Text(random ? 'ESTRAI PROSSIMO' : 'Apri chiamata'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RandomDrawPanel extends StatelessWidget {
  final int remaining;
  final List<PlayerEntity> unsold;
  final bool hasActivePlayer;
  final bool canControl;
  final VoidCallback onDraw;
  final ValueChanged<String> onRecallUnsold;

  const _RandomDrawPanel({
    required this.remaining,
    required this.unsold,
    required this.hasActivePlayer,
    required this.canControl,
    required this.onDraw,
    required this.onRecallUnsold,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              const Icon(Icons.visibility_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                '$remaining',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Text('ancora da estrarre'),
              const SizedBox(height: 14),
              const Text(
                'Nessuna lista e nessuna sequenza futura. Il nome viene scelto soltanto quando estrai.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: canControl && !hasActivePlayer && remaining > 0
                    ? onDraw
                    : null,
                icon: const Icon(Icons.casino_rounded),
                label: const Text('ESTRAI PROSSIMO'),
              ),
            ],
          ),
        ),
        if (remaining == 0 && unsold.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Invenduti da richiamare',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          for (final player in unsold)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(player.name),
                subtitle: Text(player.team),
                trailing: const Icon(Icons.replay_rounded),
                enabled: canControl && !hasActivePlayer,
                onTap: canControl && !hasActivePlayer
                    ? () => onRecallUnsold(player.id)
                    : null,
              ),
            ),
        ],
      ],
    );
  }
}

class _ActivePlayerCard extends StatelessWidget {
  final PlayerEntity player;

  const _ActivePlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            child: Text(
              player.roles.first.name.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${player.team} · ${player.roles.map((role) => role.name.toUpperCase()).join(' / ')}',
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${player.basePrice}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Text('Valore base'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BidCockpit extends StatelessWidget {
  final int currentBid;
  final int extensionSeconds;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlusOne;
  final VoidCallback onPlusFive;
  final VoidCallback onPlusTen;
  final VoidCallback onManual;

  const _BidCockpit({
    required this.currentBid,
    required this.extensionSeconds,
    required this.enabled,
    required this.onMinus,
    required this.onPlusOne,
    required this.onPlusFive,
    required this.onPlusTen,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('OFFERTA CORRENTE'),
            const SizedBox(height: 2),
            Text(
              '$currentBid',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text('Ogni aumento reale: +${extensionSeconds}s al timer'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: enabled ? onMinus : null,
                  child: const Text('−1'),
                ),
                FilledButton(
                  onPressed: enabled ? onPlusOne : null,
                  child: const Text('+1'),
                ),
                FilledButton(
                  onPressed: enabled ? onPlusFive : null,
                  child: const Text('+5'),
                ),
                FilledButton(
                  onPressed: enabled ? onPlusTen : null,
                  child: const Text('+10'),
                ),
                OutlinedButton.icon(
                  onPressed: enabled ? onManual : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Imposta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final List<FantasyTeamEntity> teams;
  final String? currentValue;
  final int currentBid;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onAssign;
  final VoidCallback onUnsold;
  final VoidCallback onUnavailable;

  const _AssignmentCard({
    required this.teams,
    required this.currentValue,
    required this.currentBid,
    required this.enabled,
    required this.onChanged,
    required this.onAssign,
    required this.onUnsold,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chi se lo aggiudica?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: currentValue,
              decoration: const InputDecoration(
                labelText: 'Squadra vincente',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              items: teams
                  .map(
                    (team) => DropdownMenuItem(
                      value: team.id,
                      child: Text('${team.name} · ${team.creditsRemaining} cr'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled ? onChanged : null,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled ? onAssign : null,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text('ASSEGNA A $currentBid CR'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onUnsold : null,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Invenduto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: enabled ? onUnavailable : null,
                    icon: const Icon(Icons.block_outlined),
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

class _RecommendationCard extends StatelessWidget {
  final AuctionRecommendation recommendation;

  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matrix Advisor',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(label: Text(_decisionLabel(recommendation.decision))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Valore equo',
                    value: '${recommendation.fairValue}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Tetto consigliato',
                    value: '${recommendation.maxBid}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Confidenza',
                    value: '${(recommendation.confidence * 100).round()}%',
                  ),
                ),
              ],
            ),
            if (recommendation.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                recommendation.reasons.take(2).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _decisionLabel(AuctionDecision decision) => switch (decision) {
        AuctionDecision.strongBuy => 'FORTE BUY',
        AuctionDecision.buy => 'BUY',
        AuctionDecision.wait => 'ASPETTA',
        AuctionDecision.pass => 'PASSA',
        AuctionDecision.unavailable => 'N/D',
      };
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

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
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class _MyTeamCard extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;

  const _MyTeamCard({required this.team, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text('${team.creditsRemaining} crediti rimasti'),
          Text('${team.roster.length}/${session.config.rosterSize} giocatori'),
          Text('Max spendibile ora: ${team.maxAffordableBid(session.config)}'),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;

  const _TeamCard({required this.team, required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(
          team.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${team.creditsRemaining} cr · ${team.roster.length}/${session.config.rosterSize}',
        ),
        children: [
          if (team.roster.isEmpty)
            const ListTile(title: Text('Rosa vuota'))
          else
            for (final player in team.roster)
              ListTile(
                dense: true,
                title: Text(player.name),
                trailing: Text('${player.purchasePrice ?? '-'} cr'),
              ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final PlayerEntity player;
  final bool unsold;
  final bool enabled;
  final VoidCallback onTap;

  const _PlayerTile({
    required this.player,
    required this.unsold,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: CircleAvatar(
          child: Text(player.roles.first.name.toUpperCase()),
        ),
        title: Text(
          player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${player.team} · ${player.roles.map((role) => role.name.toUpperCase()).join(' / ')}',
        ),
        trailing: unsold
            ? const Chip(label: Text('Invenduto'))
            : Text('${player.basePrice}'),
      ),
    );
  }
}

class _PersistenceLine extends StatelessWidget {
  final AuctionUiState state;

  const _PersistenceLine({required this.state});

  @override
  Widget build(BuildContext context) {
    final (text, icon) = switch (state.persistenceStatus) {
      AuctionPersistenceStatus.pending => ('Sincronizzazione…', Icons.sync),
      AuctionPersistenceStatus.synced => ('Sincronizzata', Icons.cloud_done),
      AuctionPersistenceStatus.failed => ('Errore sync', Icons.cloud_off),
      AuctionPersistenceStatus.idle => ('Locale', Icons.cloud_outlined),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
