import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/auction_sharing_providers.dart';

class AuctionSharingSheet extends ConsumerStatefulWidget {
  final AuctionSession session;
  final AuctionSessionSnapshot snapshot;
  final String myTeamId;

  const AuctionSharingSheet({
    required this.session,
    required this.snapshot,
    required this.myTeamId,
    super.key,
  });

  @override
  ConsumerState<AuctionSharingSheet> createState() => _AuctionSharingSheetState();
}

class _AuctionSharingSheetState extends ConsumerState<AuctionSharingSheet> {
  AuctionShareInvite? _invite;
  final Map<String, String> _selectedTeams = {};
  final Set<String> _busyRequests = {};
  bool _loadingInvite = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInvite);
  }

  Future<void> _loadInvite() async {
    if (mounted) {
      setState(() {
        _loadingInvite = true;
        _error = null;
      });
    }

    try {
      final current = await ref.read(
        currentAuctionShareInviteProvider(widget.session.id).future,
      );
      final invite = current ??
          await ref
              .read(auctionSharingRepositoryProvider)
              .createInvite(sessionId: widget.session.id);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loadingInvite = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInvite = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _copyCode() async {
    final invite = _invite;
    if (invite == null) return;
    await Clipboard.setData(ClipboardData(text: invite.formattedEntryCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Codice di ingresso copiato.')),
    );
  }

  Future<void> _approve(AuctionJoinRequest request) async {
    final teamId = _selectedTeams[request.id];
    if (teamId == null || _busyRequests.contains(request.id)) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await ref.read(auctionSharingRepositoryProvider).approveRequest(
            requestId: request.id,
            assignedTeamId: teamId,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _reject(AuctionJoinRequest request) async {
    if (_busyRequests.contains(request.id)) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await ref
          .read(auctionSharingRepositoryProvider)
          .rejectRequest(requestId: request.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingAuctionJoinRequestsProvider);
    final teams = widget.snapshot.teamsById.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    final assignableTeams = teams
        .where((team) => team.id != widget.myTeamId)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Condividi ${widget.session.name}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gli altri partecipanti entrano con il codice e restano Viewer. '
              'Tu approvi la richiesta e assegni la loro squadra.',
            ),
            const SizedBox(height: 18),
            _InviteCodeCard(
              invite: _invite,
              loading: _loadingInvite,
              error: _error,
              onCopy: _copyCode,
              onRetry: _loadInvite,
            ),
            const SizedBox(height: 20),
            Text(
              'Richieste in attesa',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: pending.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Text(error.toString()),
                data: (requests) {
                  final sessionRequests = requests
                      .where((request) => request.sessionId == widget.session.id)
                      .toList(growable: false);
                  if (sessionRequests.isEmpty) {
                    return const _NoRequests();
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessionRequests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final request = sessionRequests[index];
                      final busy = _busyRequests.contains(request.id);
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Partecipante ${_shortUid(request.requesterUid)}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedTeams[request.id],
                                decoration: const InputDecoration(
                                  labelText: 'Assegna squadra',
                                  isDense: true,
                                ),
                                items: assignableTeams
                                    .map(
                                      (team) => DropdownMenuItem(
                                        value: team.id,
                                        child: Text(team.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: busy
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setState(() => _selectedTeams[request.id] = value);
                                      },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: busy ? null : () => _reject(request),
                                    child: const Text('Rifiuta'),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: busy || _selectedTeams[request.id] == null
                                        ? null
                                        : () => _approve(request),
                                    icon: busy
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.check_rounded),
                                    label: const Text('Approva'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortUid(String uid) {
    if (uid.length <= 10) return uid;
    return '${uid.substring(0, 6)}…${uid.substring(uid.length - 4)}';
  }
}

class _InviteCodeCard extends StatelessWidget {
  final AuctionShareInvite? invite;
  final bool loading;
  final String? error;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  const _InviteCodeCard({
    required this.invite,
    required this.loading,
    required this.error,
    required this.onCopy,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Column(
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Riprova'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const Text('CODICE DI INGRESSO'),
                    const SizedBox(height: 6),
                    SelectableText(
                      invite!.formattedEntryCode,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Il codice resta valido mentre gestisci le richieste di ingresso.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copia codice'),
                    ),
                  ],
                ),
    );
  }
}

class _NoRequests extends StatelessWidget {
  const _NoRequests();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Nessuna richiesta. Condividi il codice; quando qualcuno chiede accesso comparirà qui.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
