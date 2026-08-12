import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/auction_sharing_providers.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/owned_auction_sessions_provider.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/auction_flow_screen.dart';
import 'package:mantra_matrix/features/auction/presentation/widgets/join_auction_code_dialog.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionHomeScreen extends ConsumerStatefulWidget {
  final List<PlayerEntity> players;

  const AuctionHomeScreen({required this.players, super.key});

  @override
  ConsumerState<AuctionHomeScreen> createState() => _AuctionHomeScreenState();
}

class _AuctionHomeScreenState extends ConsumerState<AuctionHomeScreen> {
  String? _openingSessionId;

  Future<void> _createAuction() async {
    ref.read(auctionControllerProvider.notifier).prepareNewSession();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AuctionFlowScreen(players: widget.players),
      ),
    );
  }

  Future<void> _joinAuction() async {
    final requested = await showDialog<bool>(
      context: context,
      builder: (_) => const JoinAuctionCodeDialog(),
    );
    if (!mounted || requested != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Richiesta inviata. L’asta comparirà qui appena il proprietario ti approva e assegna la squadra.',
        ),
      ),
    );
  }

  Future<void> _resumeAuction(AuctionSessionSummary session) async {
    if (_openingSessionId != null) return;

    setState(() => _openingSessionId = session.id);
    final opened = await ref
        .read(auctionControllerProvider.notifier)
        .openSession(sessionId: session.id, players: widget.players);

    if (!mounted) return;
    setState(() => _openingSessionId = null);

    if (!opened) {
      final message = ref.read(auctionControllerProvider).errorMessage ??
          'Impossibile aprire l’asta.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AuctionFlowScreen(players: widget.players),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(ownedAuctionSessionsProvider);
    final shared = ref.watch(sharedAuctionSessionsProvider);
    final user = ref.watch(currentUserProvider);
    final firstName = _firstName(user?.displayName, user?.email);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Asta Matrix',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Entra con codice',
            onPressed: _joinAuction,
            icon: const Icon(Icons.key_rounded),
          ),
          const AuthUserMenu(),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openingSessionId == null ? _createAuction : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuova asta'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ownedAuctionSessionsProvider);
          ref.invalidate(sharedAuctionSessionsProvider);
          await Future.wait([
            ref.read(ownedAuctionSessionsProvider.future),
            ref.read(sharedAuctionSessionsProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeHero(
                      firstName: firstName,
                      onCreate: _createAuction,
                      onJoin: _joinAuction,
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      icon: Icons.gavel_rounded,
                      title: 'Le mie aste',
                    ),
                    const SizedBox(height: 10),
                    _SessionAsyncSection(
                      value: owned,
                      openingSessionId: _openingSessionId,
                      owner: true,
                      onOpen: _resumeAuction,
                    ),
                    const SizedBox(height: 26),
                    const _SectionTitle(
                      icon: Icons.visibility_outlined,
                      title: 'Aste condivise con me',
                    ),
                    const SizedBox(height: 10),
                    _SessionAsyncSection(
                      value: shared,
                      openingSessionId: _openingSessionId,
                      owner: false,
                      onOpen: _resumeAuction,
                      emptyMessage:
                          'Nessuna asta condivisa. Usa “Entra con codice” per chiedere accesso.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _firstName(String? displayName, String? email) {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    return email?.split('@').first ?? 'manager';
  }
}

class _HomeHero extends StatelessWidget {
  final String firstName;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  const _HomeHero({
    required this.firstName,
    required this.onCreate,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crea asta'),
              ),
              OutlinedButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.key_rounded),
                label: const Text('Entra con codice'),
              ),
            ],
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bentornato, $firstName',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Crea una sessione oppure entra nell’asta di un altro manager con il codice condiviso.',
              ),
            ],
          );

          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 18), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 24),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SessionAsyncSection extends StatelessWidget {
  final AsyncValue<List<AuctionSessionSummary>> value;
  final String? openingSessionId;
  final bool owner;
  final Future<void> Function(AuctionSessionSummary session) onOpen;
  final String emptyMessage;

  const _SessionAsyncSection({
    required this.value,
    required this.openingSessionId,
    required this.owner,
    required this.onOpen,
    this.emptyMessage = 'Nessuna asta in questa sezione.',
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stackTrace) => _InlineMessage(
        icon: Icons.cloud_off_outlined,
        message: error.toString(),
      ),
      data: (sessions) {
        final live = sessions
            .where((session) => session.status == AuctionSessionStatus.live)
            .toList(growable: false);
        final completed = sessions
            .where((session) => session.status == AuctionSessionStatus.completed)
            .toList(growable: false);

        if (live.isEmpty && completed.isEmpty) {
          return _InlineMessage(
            icon: owner ? Icons.inbox_outlined : Icons.group_outlined,
            message: emptyMessage,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final session in live) ...[
              _AuctionCard(
                session: session,
                owner: owner,
                opening: openingSessionId == session.id,
                disabled: openingSessionId != null,
                onOpen: () => onOpen(session),
              ),
              const SizedBox(height: 10),
            ],
            if (completed.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Concluse',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final session in completed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CompletedCard(session: session, owner: owner),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final AuctionSessionSummary session;
  final bool owner;
  final bool opening;
  final bool disabled;
  final VoidCallback onOpen;

  const _AuctionCard({
    required this.session,
    required this.owner,
    required this.opening,
    required this.disabled,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: owner
                    ? colors.primaryContainer
                    : colors.secondaryContainer,
                child: Icon(owner ? Icons.gavel_rounded : Icons.visibility_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(owner ? 'OWNER' : 'VIEWER'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${session.teamCount} squadre · ${session.initialCredits} cr · ${session.rosterSize} slot',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              opening
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final AuctionSessionSummary session;
  final bool owner;

  const _CompletedCard({required this.session, required this.owner});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline_rounded),
        title: Text(session.name),
        subtitle: Text(owner ? 'Asta conclusa · proprietario' : 'Asta conclusa · viewer'),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InlineMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
