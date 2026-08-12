import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/independent_auction_setup_screen.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/independent_live_auction_screen.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/presentation/screens/player_import_screen.dart';

/// Route dedicata a una singola asta.
///
/// Le sessioni già aperte vanno direttamente alla dashboard live. Una nuova
/// sessione, invece, deve scegliere esplicitamente il proprio dataset prima di
/// accedere al setup: il catalogo globale non viene più usato implicitamente.
class AuctionFlowScreen extends ConsumerStatefulWidget {
  final List<PlayerEntity> players;

  const AuctionFlowScreen({required this.players, super.key});

  @override
  ConsumerState<AuctionFlowScreen> createState() => _AuctionFlowScreenState();
}

class _AuctionFlowScreenState extends ConsumerState<AuctionFlowScreen> {
  List<PlayerEntity>? _newSessionPlayers;

  Future<void> _importPlayers() async {
    final imported = await Navigator.of(context).push<List<PlayerEntity>>(
      MaterialPageRoute(builder: (_) => const PlayerImportScreen()),
    );
    if (!mounted || imported == null || imported.isEmpty) return;
    setState(() => _newSessionPlayers = imported);
  }

  void _changeDataset() {
    setState(() => _newSessionPlayers = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auctionControllerProvider);

    if (state.isRestoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Apertura dell’asta…'),
            ],
          ),
        ),
      );
    }

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && state.isStarted) {
          ref.read(auctionControllerProvider.notifier).closeSession();
        }
      },
      child: state.isStarted
          ? _startedAuction(state)
          : _newSessionPlayers == null
              ? _PlayerSourceGate(onImport: _importPlayers)
              : _ImportedAuctionSetup(
                  players: _newSessionPlayers!,
                  onChangeDataset: _changeDataset,
                ),
    );
  }

  Widget _startedAuction(AuctionUiState state) {
    final initialSyncComplete = state.lastPersistedAt != null;

    if (!initialSyncComplete) {
      if (state.persistenceStatus == AuctionPersistenceStatus.failed) {
        return _InitialSyncFailureScreen(
          error: state.persistenceError,
          onBack: () {
            ref.read(auctionControllerProvider.notifier).closeSession();
          },
        );
      }

      return const _InitialSyncPreparingScreen();
    }

    // Timer e stato Controller/Viewer ora fanno parte del cockpit live. Non
    // aggiungiamo più overlay assoluti che coprono pulsanti o duplicano il clock.
    return const IndependentLiveAuctionScreen();
  }
}

class _InitialSyncPreparingScreen extends StatelessWidget {
  const _InitialSyncPreparingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preparazione asta')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 22),
                  Text(
                    'Preparazione realtime…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Sto salvando dataset, stato live e controller lease. '
                    'I comandi d’asta si attivano solo quando Firestore ha '
                    'confermato la sessione.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialSyncFailureScreen extends StatelessWidget {
  final String? error;
  final VoidCallback onBack;

  const _InitialSyncFailureScreen({
    required this.error,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rawError = error?.trim() ?? 'Errore Firestore non disponibile.';
    final lower = rawError.toLowerCase();
    final permissionDenied = lower.contains('permission-denied') ||
        lower.contains('permission_denied');

    final title = permissionDenied
        ? 'Configurazione Firestore non aggiornata'
        : 'Sincronizzazione iniziale non riuscita';
    final message = permissionDenied
        ? 'Questa build usa lo stato realtime per-sessione '
            '`auction_sessions/.../live/current`. Firestore sta rifiutando '
            'l’accesso: le Security Rules distribuite sul progetto non sono '
            'ancora allineate alla branch. Aggiorna le rules e crea di nuovo '
            'l’asta.'
        : 'Asta Matrix non avvia un’asta locale quando il backend realtime '
            'non è pronto. In questo modo timer, rilanci e rose non possono '
            'divergire tra dispositivi.';

    return Scaffold(
      appBar: AppBar(title: const Text('Realtime non disponibile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 54,
                      color: colors.error,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      title: const Text('Dettagli tecnici'),
                      children: [
                        SelectableText(
                          rawError,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Torna alla configurazione'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSourceGate extends StatelessWidget {
  final VoidCallback onImport;

  const _PlayerSourceGate({required this.onImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuova asta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.dataset_outlined, size: 52),
                        const SizedBox(height: 16),
                        Text(
                          'Scegli i dati della tua asta',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Ogni nuova asta usa un dataset scelto esplicitamente. '
                          'Matrix non carica automaticamente listoni di terze parti.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onImport,
                      child: const Padding(
                        padding: EdgeInsets.all(18),
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Icon(Icons.upload_file_rounded),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Importa un file',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'CSV, TSV o TXT con colonne configurabili',
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _ComingSoonSourceCard(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Database Matrix',
                    subtitle:
                        'Dataset indipendente con statistiche e valori Matrix',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonSourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonSourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Chip(label: Text('Prossimamente')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportedAuctionSetup extends StatelessWidget {
  final List<PlayerEntity> players;
  final VoidCallback onChangeDataset;

  const _ImportedAuctionSetup({
    required this.players,
    required this.onChangeDataset,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndependentAuctionSetupScreen(players: players),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'change-auction-dataset',
              tooltip: 'Cambia dataset',
              onPressed: onChangeDataset,
              child: const Icon(Icons.dataset_outlined),
            ),
          ),
        ),
      ],
    );
  }
}
