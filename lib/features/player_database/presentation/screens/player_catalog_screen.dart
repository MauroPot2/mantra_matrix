import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';
import 'package:mantra_matrix/features/player_database/data/models/player_model.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_catalog.dart';
import 'package:mantra_matrix/features/player_database/presentation/providers/player_providers.dart';

class PlayerCatalogScreen extends ConsumerStatefulWidget {
  const PlayerCatalogScreen({super.key});

  @override
  ConsumerState<PlayerCatalogScreen> createState() =>
      _PlayerCatalogScreenState();
}

class _PlayerCatalogScreenState extends ConsumerState<PlayerCatalogScreen> {
  final _sourceController = TextEditingController();
  final _sourceNameController = TextEditingController(text: 'Listone Mantra');
  List<PlayerModel>? _preview;
  String? _error;
  bool _replaceMissing = true;
  bool _isImporting = false;

  @override
  void dispose() {
    _sourceController.dispose();
    _sourceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = ref.watch(playerCatalogMetadataProvider);
    final players = ref.watch(allPlayersProvider);
    final isAdmin = ref.watch(playerCatalogAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Listone giocatori',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _CatalogStatusCard(
              metadata: metadata.value,
              playerCount: players.value?.length,
              isLoading: metadata.isLoading || players.isLoading,
            ),
            const SizedBox(height: 16),
            isAdmin.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _AdminUnavailable(error: error),
              data: (allowed) => allowed
                  ? _buildImporter(context)
                  : const _AdminOnlyNotice(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImporter(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Aggiorna catalogo',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Incolla un array JSON oppure un CSV/TSV. Campi minimi: '
              'nome, squadra e ruolo. Se manca l’ID ne viene creato uno stabile.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sourceNameController,
              decoration: const InputDecoration(
                labelText: 'Nome o fonte del listone',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceController,
              minLines: 10,
              maxLines: 18,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'JSON / CSV',
                alignLabelWithHint: true,
                hintText:
                    '[{"id":"7006","name":"Lautaro Martinez",'
                    '"team":"Inter","roles":"PC","fvm":120}]',
                suffixIcon: IconButton(
                  tooltip: 'Incolla dagli appunti',
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_go_outlined),
                ),
              ),
              onChanged: (_) {
                if (_preview != null || _error != null) {
                  setState(() {
                    _preview = null;
                    _error = null;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _replaceMissing,
              onChanged: _isImporting
                  ? null
                  : (value) => setState(() => _replaceMissing = value),
              title: const Text('Sostituisci il listone attivo'),
              subtitle: const Text(
                'I giocatori assenti dal nuovo file vengono disattivati, non '
                'eliminati. Le aste già create conservano il proprio snapshot.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 10),
              _PreviewSummary(players: _preview!),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _isImporting ? null : _previewSource,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Controlla anteprima'),
                ),
                FilledButton.icon(
                  onPressed:
                      _isImporting || _preview == null ? null : _importCatalog,
                  icon: _isImporting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_isImporting ? 'Aggiornamento…' : 'Aggiorna'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _sourceController.text = data!.text!;
    _previewSource();
  }

  void _previewSource() {
    try {
      final parsed = ref
          .read(playerCatalogImportServiceProvider)
          .parse(_sourceController.text);
      setState(() {
        _preview = parsed;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _preview = null;
        _error = error.toString();
      });
    }
  }

  Future<void> _importCatalog() async {
    final players = _preview;
    final uid = ref.read(currentUserUidProvider);
    if (players == null || uid == null || _isImporting) return;

    setState(() => _isImporting = true);
    try {
      final result = await ref.read(playerRepositoryProvider).updateCatalog(
            players: players,
            sourceName: _sourceNameController.text,
            updatedByUid: uid,
            deactivateMissing: _replaceMissing,
          );
      ref
        ..invalidate(allPlayersProvider)
        ..invalidate(playerCatalogMetadataProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.importedCount} giocatori aggiornati'
            '${result.deactivatedCount == 0 ? '' : ', ${result.deactivatedCount} disattivati'}.',
          ),
        ),
      );
      setState(() {
        _preview = null;
        _sourceController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Aggiornamento non riuscito: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

class _CatalogStatusCard extends StatelessWidget {
  final PlayerCatalogMetadata? metadata;
  final int? playerCount;
  final bool isLoading;

  const _CatalogStatusCard({
    required this.metadata,
    required this.playerCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = metadata?.updatedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.groups_2_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isLoading ? 'Caricamento listone…' : '${playerCount ?? 0} giocatori attivi',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (!isLoading) ...[
              const SizedBox(height: 12),
              Text('Fonte: ${metadata?.sourceName ?? 'Catalogo legacy'}'),
              if (metadata != null)
                Text('Versione: ${metadata!.version}'),
              if (updatedAt != null)
                Text(
                  'Aggiornato: ${_twoDigits(updatedAt.day)}/${_twoDigits(updatedAt.month)}/${updatedAt.year} '
                  '${_twoDigits(updatedAt.hour)}:${_twoDigits(updatedAt.minute)}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _PreviewSummary extends StatelessWidget {
  final List<PlayerModel> players;

  const _PreviewSummary({required this.players});

  @override
  Widget build(BuildContext context) {
    final teams = players.map((player) => player.team).toSet().length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Anteprima valida: ${players.length} giocatori, $teams squadre. '
        'Primi nomi: ${players.take(3).map((player) => player.name).join(', ')}.',
      ),
    );
  }
}

class _AdminOnlyNotice extends StatelessWidget {
  const _AdminOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.admin_panel_settings_outlined),
        title: Text('Aggiornamento riservato all’amministratore'),
        subtitle: Text(
          'Per proteggere il catalogo globale serve il custom claim `admin: true` '
          'oppure `is_admin: true` nel proprio profilo Firestore. Tutti gli '
          'utenti possono usare il listone pubblicato.',
        ),
      ),
    );
  }
}

class _AdminUnavailable extends StatelessWidget {
  final Object error;

  const _AdminUnavailable({required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('Impossibile verificare i permessi'),
        subtitle: Text(error.toString()),
      ),
    );
  }
}
