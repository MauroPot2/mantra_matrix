import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mantra_matrix/features/player_database/data/services/delimited_player_importer.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/domain/import/player_import.dart';

class PlayerImportScreen extends StatefulWidget {
  const PlayerImportScreen({super.key});

  @override
  State<PlayerImportScreen> createState() => _PlayerImportScreenState();
}

class _PlayerImportScreenState extends State<PlayerImportScreen> {
  static const _importer = DelimitedPlayerImporter();

  String? _fileName;
  String? _contents;
  List<String> _headers = const [];
  PlayerImportResult? _result;
  String? _error;
  bool _loading = false;

  String? _nameColumn;
  String? _teamColumn;
  String? _rolesColumn;
  String? _basePriceColumn;

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      const typeGroup = XTypeGroup(
        label: 'File tabellari',
        extensions: ['csv', 'tsv', 'txt'],
        mimeTypes: ['text/csv', 'text/tab-separated-values', 'text/plain'],
        uniformTypeIdentifiers: [
          'public.comma-separated-values-text',
          'public.tab-separated-values-text',
          'public.plain-text',
        ],
        webWildCards: ['text/*'],
      );

      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null) return;

      final contents = await file.readAsString();
      final headers = _importer.readHeaders(contents);
      final auto = _autoMapping(headers);

      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _contents = contents;
        _headers = headers;
        _nameColumn = auto.nameColumn;
        _teamColumn = auto.teamColumn;
        _rolesColumn = auto.rolesColumn;
        _basePriceColumn = auto.basePriceColumn;
      });
    } on PlayerImportException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Impossibile leggere il file: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _analyze() {
    final contents = _contents;
    final nameColumn = _nameColumn;
    final teamColumn = _teamColumn;
    final rolesColumn = _rolesColumn;

    if (contents == null) {
      setState(() => _error = 'Seleziona prima un file.');
      return;
    }
    if (nameColumn == null || teamColumn == null || rolesColumn == null) {
      setState(() {
        _error = 'Associa almeno le colonne Nome, Squadra e Ruoli.';
      });
      return;
    }

    try {
      final result = _importer.import(
        contents,
        mapping: PlayerImportColumnMapping(
          nameColumn: nameColumn,
          teamColumn: teamColumn,
          rolesColumn: rolesColumn,
          basePriceColumn: _basePriceColumn,
        ),
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } on PlayerImportException catch (error) {
      setState(() {
        _result = null;
        _error = error.message;
      });
    }
  }

  void _continue() {
    final result = _result;
    if (result == null || !result.isValid) return;
    Navigator.of(context).pop<List<PlayerEntity>>(context, result.players);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Importa giocatori')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _IntroCard(onPickFile: _loading ? null : _pickFile),
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_fileName != null) ...[
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_fileName!),
                  subtitle: Text('${_headers.length} colonne rilevate'),
                  trailing: IconButton(
                    tooltip: 'Scegli un altro file',
                    onPressed: _loading ? null : _pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                ),
              ),
            ],
            if (_headers.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Associa le colonne',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Matrix legge solo le colonne che scegli tu. Il file può usare '
                'nomi di intestazione diversi.',
              ),
              const SizedBox(height: 14),
              _MappingField(
                label: 'Nome giocatore',
                value: _nameColumn,
                headers: _headers,
                requiredField: true,
                onChanged: (value) => setState(() {
                  _nameColumn = value;
                  _result = null;
                }),
              ),
              const SizedBox(height: 12),
              _MappingField(
                label: 'Squadra reale',
                value: _teamColumn,
                headers: _headers,
                requiredField: true,
                onChanged: (value) => setState(() {
                  _teamColumn = value;
                  _result = null;
                }),
              ),
              const SizedBox(height: 12),
              _MappingField(
                label: 'Ruoli',
                value: _rolesColumn,
                headers: _headers,
                requiredField: true,
                onChanged: (value) => setState(() {
                  _rolesColumn = value;
                  _result = null;
                }),
              ),
              const SizedBox(height: 12),
              _MappingField(
                label: 'Prezzo base',
                value: _basePriceColumn,
                headers: _headers,
                requiredField: false,
                onChanged: (value) => setState(() {
                  _basePriceColumn = value;
                  _result = null;
                }),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _analyze,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Analizza file'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _MessageCard(
                icon: Icons.error_outline,
                message: _error!,
                isError: true,
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 20),
              _ImportPreview(result: _result!),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _result!.isValid ? _continue : null,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _result!.isValid
                      ? 'Continua con ${_result!.players.length} giocatori'
                      : 'Correggi il file prima di continuare',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  PlayerImportColumnMapping _autoMapping(List<String> headers) {
    String? find(Set<String> candidates) {
      for (final header in headers) {
        final normalized = _normalize(header);
        if (candidates.contains(normalized)) return header;
      }
      return null;
    }

    return PlayerImportColumnMapping(
      nameColumn: find({
            'nome',
            'name',
            'player',
            'giocatore',
            'calciatore',
          }) ??
          '',
      teamColumn: find({'squadra', 'team', 'club'}) ?? '',
      rolesColumn: find({'ruolo', 'ruoli', 'role', 'roles'}) ?? '',
      basePriceColumn: find({
        'prezzo',
        'prezzo base',
        'base price',
        'baseprice',
        'quotazione',
        'value',
      }),
    );
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _IntroCard extends StatelessWidget {
  final VoidCallback? onPickFile;

  const _IntroCard({required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.upload_file_rounded, size: 42),
          const SizedBox(height: 12),
          Text(
            'Porta la tua lista',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Importa un CSV, TSV o TXT. Il file deve contenere almeno nome, '
            'squadra e ruoli. Il prezzo base è facoltativo.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Scegli file'),
          ),
        ],
      ),
    );
  }
}

class _MappingField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> headers;
  final bool requiredField;
  final ValueChanged<String?> onChanged;

  const _MappingField({
    required this.label,
    required this.value,
    required this.headers,
    required this.requiredField,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value != null && value!.isNotEmpty ? value : null;

    return DropdownButtonFormField<String>(
      value: normalizedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        prefixIcon: const Icon(Icons.view_column_outlined),
      ),
      items: [
        if (!requiredField)
          const DropdownMenuItem<String>(
            value: '__none__',
            child: Text('Non importare'),
          ),
        ...headers.map(
          (header) => DropdownMenuItem<String>(
            value: header,
            child: Text(header, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (selected) {
        if (selected == '__none__') {
          onChanged(null);
        } else {
          onChanged(selected);
        }
      },
    );
  }
}

class _ImportPreview extends StatelessWidget {
  final PlayerImportResult result;

  const _ImportPreview({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = result.players.take(6).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Anteprima',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Chip(
              avatar: const Icon(Icons.groups_2_outlined, size: 18),
              label: Text('${result.players.length} validi'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (result.issues.isNotEmpty)
          _MessageCard(
            icon: Icons.warning_amber_rounded,
            message:
                '${result.issues.length} righe contengono errori. '
                'Correggile nel file e importalo di nuovo.',
            isError: true,
          )
        else
          const _MessageCard(
            icon: Icons.check_circle_outline_rounded,
            message: 'Tutte le righe sono valide. Il dataset è pronto.',
            isError: false,
          ),
        const SizedBox(height: 12),
        ...preview.map(
          (player) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(player.roles.first.name.toUpperCase()),
              ),
              title: Text(player.name),
              subtitle: Text(
                '${player.team} · '
                '${player.roles.map((role) => role.name.toUpperCase()).join(' / ')}',
              ),
              trailing: Text('${player.basePrice} cr'),
            ),
          ),
        ),
        if (result.players.length > preview.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${result.players.length - preview.length} altri giocatori',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (result.issues.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...result.issues.take(6).map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Riga ${issue.rowNumber}: ${issue.message}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isError;

  const _MessageCard({
    required this.icon,
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isError ? colors.error : colors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
