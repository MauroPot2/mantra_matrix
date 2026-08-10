import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_recommendation.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
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
  String _query = '';
  int _sectionIndex = 0;

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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            _PersistenceLabel(state: state),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Annulla ultima azione',
            onPressed: snapshot.lastReversibleEvent == null
                ? null
                : () => ref
                    .read(auctionControllerProvider.notifier)
                    .undoLast(),
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Concludi asta',
            onPressed: () => _completeAuction(context),
            icon: const Icon(Icons.flag_outlined),
          ),
          const AuthUserMenu(),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 430,
                    child: _marketPanel(session, snapshot),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _auctionPanel(session, snapshot, state)),
                ],
              );
            }

            return Column(
              children: [
                NavigationBar(
                  selectedIndex: _sectionIndex,
                  onDestinationSelected: (value) {
                    setState(() => _sectionIndex = value);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      label: 'Mercato',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.gavel_rounded),
                      label: 'Asta live',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.groups_2_outlined),
                      label: 'Rose',
                    ),
                  ],
                ),
                Expanded(
                  child: switch (_sectionIndex) {
                    0 => _marketPanel(session, snapshot),
                    1 => _auctionPanel(session, snapshot, state),
                    _ => _teamsPanel(session, snapshot),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _marketPanel(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
  ) {
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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Cerca giocatore, squadra o ruolo',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Pulisci ricerca',
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              _CountChip(
                label: 'Disponibili',
                value: snapshot.availablePlayers.length,
              ),
              const SizedBox(width: 8),
              _CountChip(
                label: 'Invenduti',
                value: snapshot.unsoldPlayers.length,
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
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final player = candidates[index];
                    return _PlayerTile(
                      player: player,
                      unsold: snapshot.isUnsold(player.id),
                      onNominate: snapshot.activePlayerId == null
                          ? () => ref
                              .read(auctionControllerProvider.notifier)
                              .nominatePlayer(player.id)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _auctionPanel(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
    AuctionUiState state,
  ) {
    final active = snapshot.activePlayer;
    if (active == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign_outlined, size: 58),
                const SizedBox(height: 16),
                Text(
                  'Pronto per la prossima chiamata',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seleziona un giocatore dal mercato. Il countdown partirà dal timestamp condiviso del server.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _sectionIndex = 0),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Apri mercato'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        _ActivePlayerCard(player: active),
        const SizedBox(height: 14),
        _BidControlCard(
          currentBid: snapshot.currentBid,
          minimumBid: session.config.minimumBid,
          onIncrement: (amount) => ref
              .read(auctionControllerProvider.notifier)
              .incrementBid(amount),
          onManualBid: () => _manualBid(
            context,
            currentBid: snapshot.currentBid,
            minimumBid: session.config.minimumBid,
          ),
        ),
        const SizedBox(height: 14),
        if (state.recommendation != null)
          _RecommendationCard(recommendation: state.recommendation!),
        if (state.recommendation != null) const SizedBox(height: 14),
        _ActionCard(
          teams: snapshot.teamsById.values.toList(growable: false),
          onAssign: (team) => ref
              .read(auctionControllerProvider.notifier)
              .assignActivePlayer(team.id),
          onSkip: () => ref
              .read(auctionControllerProvider.notifier)
              .skipActivePlayer(),
          onUnavailable: () => ref
              .read(auctionControllerProvider.notifier)
              .markActivePlayerUnavailable(),
        ),
        const SizedBox(height: 14),
        _MyTeamSummary(
          team: snapshot.teamsById[state.myTeamId],
          session: session,
        ),
      ],
    );
  }

  Widget _teamsPanel(
    AuctionSession session,
    AuctionSessionSnapshot snapshot,
  ) {
    final teams = snapshot.teamsById.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      itemCount: teams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _TeamCard(
        team: teams[index],
        session: session,
      ),
    );
  }

  bool _matchesQuery(PlayerEntity player) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return true;
    return player.name.toLowerCase().contains(query) ||
        player.team.toLowerCase().contains(query) ||
        player.roles.any((role) => role.name.toLowerCase().contains(query));
  }

  Future<void> _manualBid(
    BuildContext context, {
    required int currentBid,
    required int minimumBid,
  }) async {
    final controller = TextEditingController(text: currentBid.toString());
    final bid = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Imposta offerta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Crediti',
            helperText:
                'Se aumenti il prezzo, il rilancio aggiunge 5 secondi al timer.',
          ),
          onSubmitted: (_) {
            final value = int.tryParse(controller.text);
            if (value != null && value >= minimumBid) {
              Navigator.of(context).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null || value < minimumBid) return;
              Navigator.of(context).pop(value);
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
      builder: (context) => AlertDialog(
        title: const Text('Concludere l’asta?'),
        content: const Text(
          'La sessione verrà marcata come conclusa e non sarà più riaperta come asta live.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Concludi'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(auctionControllerProvider.notifier).completeSession();
      Navigator.of(context).pop();
    }
  }
}

class _PersistenceLabel extends StatelessWidget {
  final AuctionUiState state;

  const _PersistenceLabel({required this.state});

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

class _PlayerTile extends StatelessWidget {
  final PlayerEntity player;
  final bool unsold;
  final VoidCallback? onNominate;

  const _PlayerTile({
    required this.player,
    required this.unsold,
    required this.onNominate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onNominate,
        leading: CircleAvatar(
          child: Text(player.roles.first.name.toUpperCase()),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (unsold)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(label: Text('Invenduto')),
              ),
          ],
        ),
        subtitle: Text(
          '${player.team} · ${player.roles.map((role) => role.name.toUpperCase()).join(' / ')}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${player.basePrice}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const Text('Base'),
          ],
        ),
      ),
    );
  }
}

class _ActivePlayerCard extends StatelessWidget {
  final PlayerEntity player;

  const _ActivePlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(22),
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
                const SizedBox(height: 4),
                Text(
                  '${player.team} · ${player.roles.map((role) => role.name.toUpperCase()).join(' / ')}',
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${player.basePrice}',
                style: theme.textTheme.titleLarge?.copyWith(
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

class _BidControlCard extends StatelessWidget {
  final int currentBid;
  final int minimumBid;
  final ValueChanged<int> onIncrement;
  final VoidCallback onManualBid;

  const _BidControlCard({
    required this.currentBid,
    required this.minimumBid,
    required this.onIncrement,
    required this.onManualBid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text('OFFERTA CORRENTE', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              '$currentBid cr',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => onIncrement(1),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('+1 · +5s'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => onIncrement(5),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('+5 · +5s'),
                ),
                OutlinedButton.icon(
                  onPressed: onManualBid,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Manuale'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Offerta minima: $minimumBid · Ogni aumento è un singolo rilancio e aggiunge 5 secondi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(
                  label: Text(recommendation.decision.name.toUpperCase()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Valore Matrix',
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
              const SizedBox(height: 14),
              ...recommendation.reasons.take(3).map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('• $reason'),
                    ),
                  ),
            ],
            if (recommendation.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...recommendation.warnings.take(2).map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '⚠ $warning',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
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
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final List<FantasyTeamEntity> teams;
  final ValueChanged<FantasyTeamEntity> onAssign;
  final VoidCallback onSkip;
  final VoidCallback onUnavailable;

  const _ActionCard({
    required this.teams,
    required this.onAssign,
    required this.onSkip,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...teams]..sort((a, b) => a.name.compareTo(b.name));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chiudi la chiamata',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Assegna a una squadra',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              items: sorted
                  .map(
                    (team) => DropdownMenuItem<String>(
                      value: team.id,
                      child: Text(
                        '${team.name} · ${team.creditsRemaining} cr',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (teamId) {
                if (teamId == null) return;
                final team = sorted.firstWhere((item) => item.id == teamId);
                onAssign(team);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSkip,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Invenduto'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onUnavailable,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Non disponibile'),
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

class _MyTeamSummary extends StatelessWidget {
  final FantasyTeamEntity? team;
  final AuctionSession session;

  const _MyTeamSummary({required this.team, required this.session});

  @override
  Widget build(BuildContext context) {
    final value = team;
    if (value == null) return const SizedBox.shrink();

    return _TeamCard(team: value, session: session, titlePrefix: 'La tua rosa · ');
  }
}

class _TeamCard extends StatelessWidget {
  final FantasyTeamEntity team;
  final AuctionSession session;
  final String titlePrefix;

  const _TeamCard({
    required this.team,
    required this.session,
    this.titlePrefix = '',
  });

  @override
  Widget build(BuildContext context) {
    final slots = team.slotsRemaining(session.config);
    return Card(
      child: ExpansionTile(
        title: Text(
          '$titlePrefix${team.name}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${team.creditsRemaining} cr · ${team.roster.length}/${session.config.rosterSize} giocatori · $slots slot liberi',
        ),
        children: [
          if (team.roster.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun acquisto.'),
            )
          else
            ...team.roster.map(
              (player) => ListTile(
                dense: true,
                title: Text(player.name),
                subtitle: Text(
                  player.roles.map((role) => role.name.toUpperCase()).join(' / '),
                ),
                trailing: Text('${player.purchasePrice ?? 0} cr'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;

  const _CountChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}
