import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_strategy.dart';
import 'package:mantra_matrix/features/auction/domain/entities/fantasy_team_entity.dart';
import 'package:mantra_matrix/features/auction/domain/services/formation_engine.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auth/presentation/widgets/auth_user_menu.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class IndependentAuctionSetupScreen extends ConsumerStatefulWidget {
  final List<PlayerEntity> players;

  const IndependentAuctionSetupScreen({
    required this.players,
    super.key,
  });

  @override
  ConsumerState<IndependentAuctionSetupScreen> createState() =>
      _IndependentAuctionSetupScreenState();
}

class _IndependentAuctionSetupScreenState
    extends ConsumerState<IndependentAuctionSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auctionName = TextEditingController(text: 'Asta Matrix');
  final _credits = TextEditingController(text: '500');
  final _rosterSize = TextEditingController(text: '25');
  final _minimumBid = TextEditingController(text: '1');
  final _teamCount = TextEditingController(text: '10');
  final _countdown = TextEditingController(text: '15');
  final List<TextEditingController> _teamNames = [];
  final Map<PlayerDepartment, TextEditingController> _budgets = {};

  String _primaryFormation = '4-2-3-1';
  final Set<String> _secondaryFormations = {'4-3-3', '4-4-2'};

  @override
  void initState() {
    super.initState();
    _syncTeamNames(10);
    _teamNames.first.text = 'Matrix FC';
    _recalculateBudgets();
  }

  @override
  void dispose() {
    _auctionName.dispose();
    _credits.dispose();
    _rosterSize.dispose();
    _minimumBid.dispose();
    _teamCount.dispose();
    _countdown.dispose();
    for (final controller in _teamNames) {
      controller.dispose();
    }
    for (final controller in _budgets.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credits = int.tryParse(_credits.text) ?? 0;
    final budgetTotal = _budgetTotal;
    final budgetBalanced = credits > 0 && budgetTotal == credits;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configura asta'),
        actions: const [AuthUserMenu(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SetupHero(playerCount: widget.players.length),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Regole della sessione',
                subtitle:
                    'Il countdown è condiviso. Ogni vero rilancio aggiunge sempre 5 secondi.',
                child: LayoutBuilder(
                  builder: (context, constraints) => _ResponsiveFields(
                    maxWidth: constraints.maxWidth,
                    children: [
                      _textField(
                        controller: _auctionName,
                        label: 'Nome asta',
                        icon: Icons.stadium_outlined,
                        validator: _requiredText,
                      ),
                      _numberField(
                        controller: _credits,
                        label: 'Crediti iniziali',
                        icon: Icons.account_balance_wallet_outlined,
                        min: 1,
                        max: 10000,
                        onChanged: (_) {
                          setState(_recalculateBudgets);
                        },
                      ),
                      _numberField(
                        controller: _rosterSize,
                        label: 'Dimensione rosa',
                        icon: Icons.groups_2_outlined,
                        min: 1,
                        max: 100,
                      ),
                      _numberField(
                        controller: _minimumBid,
                        label: 'Offerta minima',
                        icon: Icons.exposure_plus_1,
                        min: 1,
                        max: 1000,
                      ),
                      _numberField(
                        controller: _teamCount,
                        label: 'Numero squadre',
                        icon: Icons.groups_outlined,
                        min: 2,
                        max: 20,
                        onChanged: (value) {
                          final count = int.tryParse(value);
                          if (count == null || count < 2 || count > 20) return;
                          setState(() => _syncTeamNames(count));
                        },
                      ),
                      _numberField(
                        controller: _countdown,
                        label: 'Countdown iniziale (s)',
                        icon: Icons.timer_outlined,
                        min: 5,
                        max: 120,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Squadre partecipanti',
                subtitle:
                    'La prima è la tua squadra. I nomi restano dentro questa sessione.',
                child: LayoutBuilder(
                  builder: (context, constraints) => _ResponsiveFields(
                    maxWidth: constraints.maxWidth,
                    children: [
                      for (var index = 0; index < _teamNames.length; index++)
                        TextFormField(
                          controller: _teamNames[index],
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: index == 0
                                ? 'La tua squadra'
                                : 'Squadra ${index + 1}',
                            prefixIcon: Icon(
                              index == 0
                                  ? Icons.star_rounded
                                  : Icons.shield_outlined,
                            ),
                          ),
                          validator: (value) => _validateTeamName(value),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Strategia tattica',
                subtitle:
                    'Il modulo principale e le alternative alimentano i consigli del motore.',
                child: _formationFields(),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Piano economico',
                subtitle:
                    'La somma dei reparti deve coincidere con i crediti iniziali.',
                trailing: TextButton.icon(
                  onPressed: () => setState(_recalculateBudgets),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Ripartisci'),
                ),
                child: Column(
                  children: [
                    for (final department in PlayerDepartment.values) ...[
                      _BudgetField(
                        department: department,
                        controller: _budgets[department]!,
                        onChanged: () => setState(() {}),
                      ),
                      if (department != PlayerDepartment.values.last)
                        const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: credits <= 0
                                ? 0
                                : (budgetTotal / credits)
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$budgetTotal / $credits cr',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: budgetBalanced
                                ? null
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: budgetBalanced ? _startAuction : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Avvia asta live'),
                ),
              ),
              if (!budgetBalanced) ...[
                const SizedBox(height: 10),
                Text(
                  'Correggi il piano economico: deve totalizzare $credits crediti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _formationFields() {
    final formations = FormationEngine.officialFormations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _primaryFormation,
          decoration: const InputDecoration(
            labelText: 'Modulo principale',
            prefixIcon: Icon(Icons.star_outline_rounded),
          ),
          items: formations
              .map(
                (formation) => DropdownMenuItem<String>(
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
        const SizedBox(height: 14),
        Text(
          'Moduli alternativi',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
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
    required int min,
    required int max,
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
        if (parsed == null || parsed < min || parsed > max) {
          return 'Valore tra $min e $max';
        }
        return null;
      },
    );
  }

  String? _requiredText(String? value) {
    return value == null || value.trim().isEmpty ? 'Campo obbligatorio' : null;
  }

  String? _validateTeamName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return 'Inserisci il nome';
    final count = _teamNames
        .where((item) => item.text.trim().toLowerCase() == normalized)
        .length;
    return count > 1 ? 'Nome già utilizzato' : null;
  }

  void _syncTeamNames(int requested) {
    final count = requested.clamp(2, 20);
    while (_teamNames.length < count) {
      _teamNames.add(TextEditingController());
    }
    while (_teamNames.length > count) {
      _teamNames.removeLast().dispose();
    }
  }

  int get _budgetTotal => PlayerDepartment.values.fold(
        0,
        (sum, department) =>
            sum + (int.tryParse(_budgets[department]?.text ?? '') ?? 0),
      );

  void _recalculateBudgets() {
    final credits = int.tryParse(_credits.text) ?? 500;
    final defaults = AuctionConfig.defaultDepartmentBudgets(credits);
    for (final department in PlayerDepartment.values) {
      final text = (defaults[department] ?? 0).toString();
      final existing = _budgets[department];
      if (existing == null) {
        _budgets[department] = TextEditingController(text: text);
      } else {
        existing.text = text;
      }
    }
  }

  void _startAuction() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final credits = int.parse(_credits.text);
    if (_budgetTotal != credits) return;

    final teamCount = int.parse(_teamCount.text);
    _syncTeamNames(teamCount);
    const myTeamId = 'my-team';

    final teams = <FantasyTeamEntity>[
      for (var index = 0; index < teamCount; index++)
        FantasyTeamEntity(
          id: index == 0 ? myTeamId : 'team-${index + 1}',
          name: _teamNames[index].text.trim(),
          creditsRemaining: credits,
        ),
    ];

    ref.read(auctionControllerProvider.notifier).startSession(
          sessionName: _auctionName.text.trim(),
          myTeamId: myTeamId,
          config: AuctionConfig.standard(
            initialCredits: credits,
            rosterSize: int.parse(_rosterSize.text),
            minimumBid: int.parse(_minimumBid.text),
            countdownSeconds: int.parse(_countdown.text),
            bidExtensionSeconds: 5,
            primaryFormationName: _primaryFormation,
            secondaryFormationNames: _secondaryFormations,
            departmentBudgets: {
              for (final department in PlayerDepartment.values)
                department: int.parse(_budgets[department]!.text),
            },
          ),
          players: widget.players,
          teams: teams,
        );
  }
}

class _SetupHero extends StatelessWidget {
  final int playerCount;

  const _SetupHero({required this.playerCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            avatar: const Icon(Icons.dataset_outlined, size: 18),
            label: Text('$playerCount giocatori nel dataset'),
          ),
          const SizedBox(height: 12),
          Text(
            'Prepara il muretto d’asta',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La sessione conserverà una propria copia del dataset, gli eventi e il timer live.',
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  final double maxWidth;
  final List<Widget> children;

  const _ResponsiveFields({
    required this.maxWidth,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (maxWidth < 640) {
      return Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: children
          .map(
            (child) => SizedBox(
              width: (maxWidth - 12) / 2,
              child: child,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _BudgetField extends StatelessWidget {
  final PlayerDepartment department;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _BudgetField({
    required this.department,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            department.shortLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(child: Text(department.label)),
        SizedBox(
          width: 110,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.end,
            decoration: const InputDecoration(suffixText: 'cr'),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final parsed = int.tryParse(value ?? '');
              return parsed == null || parsed < 0 ? 'Non valido' : null;
            },
          ),
        ),
      ],
    );
  }
}
