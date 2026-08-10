import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_join_preview.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/owned_auction_sessions_provider.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/auction_flow_screen.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/presentation/screens/player_catalog_screen.dart';

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

  Future<void> _resumeAuction(AuctionSessionSummary session) async {
    if (_openingSessionId != null) return;

    setState(() => _openingSessionId = session.id);
    final opened = await ref
        .read(auctionControllerProvider.notifier)
        .openSession(sessionId: session.id, players: widget.players);

    if (!mounted) return;
    setState(() => _openingSessionId = null);

    if (!opened) {
      final message =
          ref.read(auctionControllerProvider).errorMessage ??
          'Impossibile aprire l’asta.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AuctionFlowScreen(players: widget.players),
      ),
    );
  }

  Future<void> _joinAuction() async {
    if (_openingSessionId != null) return;
    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unisciti a un’asta'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Codice invito',
            hintText: 'ABC234',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(codeController.text),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    codeController.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;

    setState(() => _openingSessionId = 'join');
    try {
      final preview = await ref
          .read(auctionControllerProvider.notifier)
          .loadJoinPreview(code);
      if (!mounted) return;
      final teamId = await _selectJoinTeam(preview);
      if (teamId == null || !mounted) return;

      final opened = await ref
          .read(auctionControllerProvider.notifier)
          .joinSession(
            joinCode: preview.joinCode,
            teamId: teamId,
            players: widget.players,
          );
      if (!mounted) return;
      if (!opened) {
        throw StateError(
          ref.read(auctionControllerProvider).errorMessage ??
              'Impossibile entrare nell’asta.',
        );
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AuctionFlowScreen(players: widget.players),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _openingSessionId = null);
    }
  }

  Future<String?> _selectJoinTeam(AuctionJoinPreview preview) {
    final availableTeams = preview.availableTeams;
    if (availableTeams.isEmpty) {
      throw StateError('Tutte le squadre sono già state associate.');
    }
    var selectedTeamId = availableTeams.first.id;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(preview.sessionName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Scegli la squadra che controllerai nell’asta.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedTeamId,
                decoration: const InputDecoration(
                  labelText: 'La tua squadra',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                items: availableTeams
                    .map(
                      (team) => DropdownMenuItem(
                        value: team.id,
                        child: Text(team.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedTeamId = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(selectedTeamId),
              icon: const Icon(Icons.login),
              label: const Text('Entra'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(ownedAuctionSessionsProvider);
    final user = ref.watch(currentUserProvider);
    final firstName = _firstName(user?.displayName, user?.email);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Le mie aste',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Gestisci listone',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const PlayerCatalogScreen()),
            ),
            icon: const Icon(Icons.storage_outlined),
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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ownedAuctionSessionsProvider);
            await ref.read(ownedAuctionSessionsProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: _WelcomePanel(
                    firstName: firstName,
                    onCreate: _openingSessionId == null ? _createAuction : null,
                    onJoin: _openingSessionId == null ? _joinAuction : null,
                  ),
                ),
              ),
              sessions.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _SessionsError(
                    error: error,
                    onRetry: () => ref.invalidate(ownedAuctionSessionsProvider),
                  ),
                ),
                data: (items) {
                  final live = items
                      .where((item) => item.status == AuctionSessionStatus.live)
                      .toList(growable: false);
                  final completed = items
                      .where(
                        (item) => item.status == AuctionSessionStatus.completed,
                      )
                      .toList(growable: false);

                  if (items.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyAuctions(onCreate: _createAuction),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                    sliver: SliverList.list(
                      children: [
                        _SectionHeader(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'Aste da riprendere',
                          count: live.length,
                        ),
                        const SizedBox(height: 10),
                        if (live.isEmpty)
                          const _InlineEmpty(
                            message: 'Non hai aste attualmente in corso.',
                          )
                        else
                          ...live.map(
                            (session) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _AuctionCard(
                                session: session,
                                isOpening: _openingSessionId == session.id,
                                disabled: _openingSessionId != null,
                                onResume: () => _resumeAuction(session),
                              ),
                            ),
                          ),
                        if (completed.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _SectionHeader(
                            icon: Icons.inventory_2_outlined,
                            title: 'Aste concluse',
                            count: completed.length,
                          ),
                          const SizedBox(height: 10),
                          ...completed.map(
                            (session) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CompletedAuctionCard(session: session),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
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

class _WelcomePanel extends StatelessWidget {
  final String firstName;
  final VoidCallback? onCreate;
  final VoidCallback? onJoin;

  const _WelcomePanel({
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
          final compact = constraints.maxWidth < 620;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bentornato, $firstName',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Riprendi un’asta salvata oppure prepara una nuova sessione. '
                'Ogni asta resta separata nel tuo account.',
              ),
            ],
          );
          final buttons = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Unisciti'),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crea nuova asta'),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 18), buttons],
            );
          }

          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 24),
              buttons,
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Badge(label: Text('$count')),
      ],
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final AuctionSessionSummary session;
  final bool isOpening;
  final bool disabled;
  final VoidCallback onResume;

  const _AuctionCard({
    required this.session,
    required this.isOpening,
    required this.disabled,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onResume,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.gavel_rounded,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Aggiornata ${_formatDate(session.updatedAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.groups_2_outlined,
                        label: '${session.teamCount} squadre',
                      ),
                      _InfoChip(
                        icon: Icons.toll_outlined,
                        label: '${session.initialCredits} crediti',
                      ),
                      _InfoChip(
                        icon: Icons.person_outline_rounded,
                        label: '${session.rosterSize} giocatori',
                      ),
                      if (session.isShared)
                        _InfoChip(
                          icon: Icons.hub_outlined,
                          label: '${session.memberCount} collegati',
                        ),
                      if (!session.isOwner)
                        const _InfoChip(
                          icon: Icons.group_outlined,
                          label: 'Ospite',
                        ),
                    ],
                  ),
                ],
              );
              final action = FilledButton.icon(
                onPressed: disabled ? null : onResume,
                icon: isOpening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(isOpening ? 'Apertura…' : 'Riprendi'),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [details, const SizedBox(height: 18), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 24),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompletedAuctionCard extends StatelessWidget {
  final AuctionSessionSummary session;

  const _CompletedAuctionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.check_rounded)),
        title: Text(
          session.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${session.teamCount} squadre · conclusa · '
          '${_formatDate(session.updatedAt)}',
        ),
        trailing: const Tooltip(
          message: 'Il riepilogo delle aste concluse sarà il prossimo modulo.',
          child: Icon(Icons.lock_clock_outlined),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _EmptyAuctions extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyAuctions({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_soccer_outlined, size: 64),
            const SizedBox(height: 18),
            Text(
              'Nessuna asta salvata',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea la tua prima asta. Da quel momento comparirà qui e potrai '
              'riprenderla anche dopo aver chiuso o reinstallato l’app.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crea la prima asta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String message;

  const _InlineEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message),
    );
  }
}

class _SessionsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _SessionsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isPermissionDenied = error.toString().contains('permission-denied');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 58),
            const SizedBox(height: 16),
            Text(
              isPermissionDenied
                  ? 'Firestore sta bloccando le aste'
                  : 'Impossibile caricare le aste',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              isPermissionDenied
                  ? 'Pubblica le nuove regole Firestore: quelle attuali '
                        'consentono soltanto la lettura di players.'
                  : error.toString(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
