import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_call_order.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/formation_engine.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class AuctionSetupScreen extends ConsumerStatefulWidget {
  final List<PlayerEntity> players;

  const AuctionSetupScreen({required this.players, super.key});

  @override
  ConsumerState<AuctionSetupScreen> createState() => _AuctionSetupScreenState();
}

class _AuctionSetupScreenState extends ConsumerState<AuctionSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auctionNameController = TextEditingController(text: 'Asta Mantra');
  final List<TextEditingController> _teamNameControllers = [];
  final _creditsController = TextEditingController(text: '500');
  final _rosterSizeController = TextEditingController(text: '25');
  final _minimumBidController = TextEditingController(text: '1');
  final _teamCountController = TextEditingController(text: '10');
  final Map<PlayerDepartment, TextEditingController> _budgetControllers = {};

  String _primaryFormation = '4-2-3-1';
  final Set<String> _secondaryFormations = {'4-3-3', '4-4-2'};
  int _bidDurationSeconds = 30;
  AuctionCallOrderMode _callOrderMode = AuctionCallOrderMode.randomAll;
  bool _isShared = true;

  @override
  void initState() {
    super.initState();
    _syncTeamNameControllers(10);
    _teamNameControllers.first.text = 'Matrix FC';
    _applyAutomaticBudgets();
  }

  @override
  void dispose() {
    _auctionNameController.dispose();
    for (final controller in _teamNameControllers) {
      controller.dispose();
    }
    _creditsController.dispose();
    _rosterSizeController.dispose();
    _minimumBidController.dispose();
    _teamCountController.dispose();
    for (final controller in _budgetControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credits = int.tryParse(_creditsController.text) ?? 0;
    final budgetTotal = _budgetTotal;
    final balanced = credits > 0 && budgetTotal == credits;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuova asta'),
        actions: const [AuthUserMenu(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1040;
            final form = Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroHeader(playerCount: widget.players.length),
                  const SizedBox(height: 20),
                  _SetupSection(
                    number: '01',
                    title: 'Dati della lega',
                    subtitle: 'I parametri che governano budget e rosa.',
                    child: _buildLeagueFields(),
                  ),
                  const SizedBox(height: 16),
                  _SetupSection(
                    number: '02',
                    title: 'Squadre partecipanti',
                    subtitle:
                        'Inserisci i nomi reali: saranno usati in assegnazioni, rose e riepiloghi.',
                    child: _buildTeamNames(),
                  ),
                  const SizedBox(height: 16),
                  _SetupSection(
                    number: '03',
                    title: 'Sessione e chiamate',
                    subtitle:
                        'Condivisione, timer per ogni calciatore e ordine del listone.',
                    child: _buildAuctionMode(),
                  ),
                  const SizedBox(height: 16),
                  _SetupSection(
                    number: '04',
                    title: 'Strategia tattica',
                    subtitle:
                        'Il modulo principale pesa più delle alternative nei consigli.',
                    child: _buildFormationStrategy(),
                  ),
                  const SizedBox(height: 16),
                  _SetupSection(
                    number: '05',
                    title: 'Piano economico',
                    subtitle:
                        'Definisce i guardrail dei tetti, senza impedirti di sforare manualmente.',
                    trailing: TextButton.icon(
                      onPressed: () => setState(_applyAutomaticBudgets),
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Ripartisci'),
                    ),
                    child: _buildBudgets(
                      credits: credits,
                      total: budgetTotal,
                      balanced: balanced,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: balanced ? _startAuction : null,
                    icon: const Icon(Icons.sports_soccer),
                    label: const Text('Entra nel muretto d’asta'),
                  ),
                  if (!balanced) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Il piano reparti deve totalizzare esattamente $credits crediti.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );

            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: form,
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: form),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 3,
                        child: _StrategyPreview(
                          credits: credits,
                          budgetTotal: budgetTotal,
                          primaryFormation: _primaryFormation,
                          secondaryFormations: _secondaryFormations,
                          budgets: {
                            for (final department in PlayerDepartment.values)
                              department:
                                  int.tryParse(
                                    _budgetControllers[department]?.text ?? '',
                                  ) ??
                                  0,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLeagueFields() {
    final fields = <Widget>[
      _textField(
        controller: _auctionNameController,
        label: 'Nome dell’asta',
        icon: Icons.stadium_outlined,
        validator: _requiredText,
      ),
      _numberField(
        controller: _creditsController,
        label: 'Crediti iniziali',
        icon: Icons.account_balance_wallet_outlined,
        minimum: 1,
        onChanged: (_) => setState(() {}),
      ),
      _numberField(
        controller: _rosterSizeController,
        label: 'Dimensione rosa',
        icon: Icons.groups_2_outlined,
        minimum: 1,
      ),
      _numberField(
        controller: _minimumBidController,
        label: 'Offerta minima',
        icon: Icons.exposure_plus_1,
        minimum: 1,
      ),
      _numberField(
        controller: _teamCountController,
        label: 'Numero squadre',
        icon: Icons.groups_outlined,
        minimum: 2,
        maximum: 20,
        onChanged: (value) {
          final count = int.tryParse(value);
          if (count == null || count < 2) return;
          setState(() => _syncTeamNameControllers(count));
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 620;
        if (!twoColumns) {
          return Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index < fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields
              .map(
                (field) => SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: field,
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildTeamNames() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 620;
        final fields = <Widget>[
          for (var index = 0; index < _teamNameControllers.length; index++)
            TextFormField(
              controller: _teamNameControllers[index],
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: index == 0
                    ? 'La tua squadra'
                    : 'Squadra ${index + 1}',
                prefixIcon: Icon(
                  index == 0 ? Icons.star_rounded : Icons.shield_outlined,
                ),
                hintText: index == 0 ? 'Matrix FC' : 'Nome partecipante',
              ),
              validator: (value) => _validateTeamName(value, index),
            ),
        ];

        if (!twoColumns) {
          return Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index < fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields
              .map(
                (field) => SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: field,
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  String? _validateTeamName(String? value, int index) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return 'Inserisci il nome della squadra';

    final duplicates = _teamNameControllers.where((controller) {
      return controller.text.trim().toLowerCase() == normalized;
    }).length;
    if (duplicates > 1) return 'Nome già utilizzato';
    return null;
  }

  void _syncTeamNameControllers(int requestedCount) {
    final count = requestedCount < 0
        ? 0
        : requestedCount > 20
        ? 20
        : requestedCount;
    while (_teamNameControllers.length < count) {
      _teamNameControllers.add(TextEditingController());
    }
    while (_teamNameControllers.length > count) {
      _teamNameControllers.removeLast().dispose();
    }
  }

  Widget _buildFormationStrategy() {
    final formations = FormationEngine.officialFormations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _primaryFormation,
          decoration: const InputDecoration(
            labelText: 'Modulo principale',
            prefixIcon: Icon(Icons.star_outline),
          ),
          items: formations
              .map(
                (formation) => DropdownMenuItem(
                  value: formation.name,
                  child: Text(formation.name),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _primaryFormation = value;
              _secondaryFormations.remove(value);
            });
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Moduli alternativi',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final formation in formations)
              if (formation.name != _primaryFormation)
                FilterChip(
                  label: Text(formation.name),
                  selected: _secondaryFormations.contains(formation.name),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _secondaryFormations.add(formation.name);
                      } else {
                        _secondaryFormations.remove(formation.name);
                      }
                    });
                  },
                ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuctionMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isShared,
          onChanged: (value) => setState(() => _isShared = value),
          title: const Text('Asta condivisa'),
          subtitle: const Text(
            'Genera un codice di 6 caratteri. Ogni partecipante entra con il '
            'proprio account e sceglie la sua squadra.',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _bidDurationSeconds,
          decoration: const InputDecoration(
            labelText: 'Durata timer per giocatore',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
          items: const [15, 30, 45, 60, 90, 120]
              .map(
                (seconds) => DropdownMenuItem(
                  value: seconds,
                  child: Text('$seconds secondi'),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) setState(() => _bidDurationSeconds = value);
          },
        ),
        const SizedBox(height: 8),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.more_time_rounded),
          title: Text('Proroga anti-sniping attiva'),
          subtitle: Text(
            'Ogni offerta valida aggiunge automaticamente 5 secondi al timer.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Modello di chiamata',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        RadioGroup<AuctionCallOrderMode>(
          groupValue: _callOrderMode,
          onChanged: (value) {
            if (value != null) setState(() => _callOrderMode = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final mode in AuctionCallOrderMode.values)
                RadioListTile<AuctionCallOrderMode>(
                  contentPadding: EdgeInsets.zero,
                  value: mode,
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBudgets({
    required int credits,
    required int total,
    required bool balanced,
  }) {
    final theme = Theme.of(context);
    final progress = credits <= 0
        ? 0.0
        : (total / credits).clamp(0.0, 1.2).toDouble();

    return Column(
      children: [
        for (final department in PlayerDepartment.values) ...[
          _DepartmentBudgetField(
            department: department,
            controller: _budgetControllers[department]!,
            onChanged: () => setState(() {}),
          ),
          if (department != PlayerDepartment.values.last)
            const SizedBox(height: 10),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0).toDouble(),
                  minHeight: 9,
                  color: balanced
                      ? Colors.green.shade500
                      : total > credits
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '$total / $credits',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: balanced
                    ? Colors.green.shade500
                    : total > credits
                    ? theme.colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required int minimum,
    int? maximum,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      onChanged: onChanged,
      validator: (value) {
        final parsed = int.tryParse(value?.trim() ?? '');
        if (parsed == null || parsed < minimum) {
          return 'Inserisci un valore ≥ $minimum';
        }
        if (maximum != null && parsed > maximum) {
          return 'Inserisci un valore ≤ $maximum';
        }
        return null;
      },
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Campo obbligatorio';
    return null;
  }

  int get _budgetTotal => PlayerDepartment.values.fold(
    0,
    (total, department) =>
        total + (int.tryParse(_budgetControllers[department]?.text ?? '') ?? 0),
  );

  void _applyAutomaticBudgets() {
    final credits = int.tryParse(_creditsController.text) ?? 500;
    final defaults = AuctionConfig.defaultDepartmentBudgets(credits);
    for (final department in PlayerDepartment.values) {
      final value = defaults[department] ?? 0;
      final existing = _budgetControllers[department];
      if (existing == null) {
        _budgetControllers[department] = TextEditingController(
          text: value.toString(),
        );
      } else {
        existing.text = value.toString();
      }
    }
  }

  void _startAuction() {
    if (!_formKey.currentState!.validate()) return;

    final credits = int.parse(_creditsController.text);
    if (_budgetTotal != credits) return;

    final rosterSize = int.parse(_rosterSizeController.text);
    final minimumBid = int.parse(_minimumBidController.text);
    final teamCount = int.parse(_teamCountController.text);
    _syncTeamNameControllers(teamCount);
    const myTeamId = 'my-team';

    final teams = <FantasyTeamEntity>[
      for (var index = 0; index < teamCount; index++)
        FantasyTeamEntity(
          id: index == 0 ? myTeamId : 'team-${index + 1}',
          name: _teamNameControllers[index].text.trim(),
          creditsRemaining: credits,
        ),
    ];

    ref
        .read(auctionControllerProvider.notifier)
        .startSession(
          sessionName: _auctionNameController.text.trim(),
          myTeamId: myTeamId,
          config: AuctionConfig.standardMantra(
            initialCredits: credits,
            rosterSize: rosterSize,
            minimumBid: minimumBid,
            bidDurationSeconds: _bidDurationSeconds,
            callOrderMode: _callOrderMode,
            primaryFormationName: _primaryFormation,
            secondaryFormationNames: _secondaryFormations,
            departmentBudgets: {
              for (final department in PlayerDepartment.values)
                department: int.parse(_budgetControllers[department]!.text),
            },
          ),
          players: widget.players,
          teams: teams,
          isShared: _isShared,
        );
  }
}

class _HeroHeader extends StatelessWidget {
  final int playerCount;

  const _HeroHeader({required this.playerCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text('$playerCount giocatori pronti'),
          ),
          const SizedBox(height: 18),
          Text(
            'Configura il tuo piano.\nL’asta reagirà in tempo reale.',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Moduli, budget e coperture diventano parte del consiglio, non semplici note.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _SetupSection extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SetupSection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    number,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _DepartmentBudgetField extends StatelessWidget {
  final PlayerDepartment department;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _DepartmentBudgetField({
    required this.department,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            department.shortLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            department.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          width: 116,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.end,
            decoration: const InputDecoration(suffixText: 'cr'),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final parsed = int.tryParse(value ?? '');
              if (parsed == null || parsed < 0) return 'Non valido';
              return null;
            },
          ),
        ),
      ],
    );
  }
}

class _StrategyPreview extends StatelessWidget {
  final int credits;
  final int budgetTotal;
  final String primaryFormation;
  final Set<String> secondaryFormations;
  final Map<PlayerDepartment, int> budgets;

  const _StrategyPreview({
    required this.credits,
    required this.budgetTotal,
    required this.primaryFormation,
    required this.secondaryFormations,
    required this.budgets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Anteprima strategia', style: theme.textTheme.titleLarge),
            const SizedBox(height: 18),
            _PreviewLine(
              icon: Icons.star_rounded,
              label: 'Modulo principale',
              value: primaryFormation,
            ),
            const SizedBox(height: 12),
            _PreviewLine(
              icon: Icons.alt_route,
              label: 'Alternative',
              value: secondaryFormations.isEmpty
                  ? 'Nessuna'
                  : secondaryFormations.join(' · '),
            ),
            const Divider(height: 30),
            for (final department in PlayerDepartment.values) ...[
              Row(
                children: [
                  Text(department.shortLabel),
                  const Spacer(),
                  Text(
                    '${budgets[department] ?? 0} cr',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (department != PlayerDepartment.values.last)
                const SizedBox(height: 10),
            ],
            const Divider(height: 30),
            Row(
              children: [
                const Text('Totale'),
                const Spacer(),
                Text(
                  '$budgetTotal / $credits',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: budgetTotal == credits
                        ? Colors.green.shade500
                        : theme.colorScheme.error,
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

class _PreviewLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PreviewLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}
