import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auth/presentation/controllers/auth_controller.dart';

enum _AuthMode { signIn, register }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _changeMode(_AuthMode mode) {
    if (_mode == mode) return;

    setState(() {
      _mode = mode;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _formKey.currentState?.reset();
    });

    ref.read(authControllerProvider.notifier).clearFeedback();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final controller = ref.read(authControllerProvider.notifier);

    if (_mode == _AuthMode.signIn) {
      await controller.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      return;
    }

    await controller.registerWithEmailAndPassword(
      displayName: _displayNameController.text,
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _openPasswordReset() async {
    FocusScope.of(context).unfocus();
    ref.read(authControllerProvider.notifier).clearFeedback();

    await showDialog<void>(
      context: context,
      builder: (context) => PasswordResetDialog(
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    ref.listen(authControllerProvider, (previous, next) {
      final error = next.errorMessage;
      final success = next.successMessage;

      if (error != null && error != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }

      if (success != null && success != previous?.successMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(success),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 840;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 24 : 40),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _LoginHero(compact: true),
                                const SizedBox(height: 32),
                                _buildAuthPanel(authState),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(
                                  flex: 5,
                                  child: _LoginHero(compact: false),
                                ),
                                const SizedBox(width: 48),
                                Expanded(
                                  flex: 5,
                                  child: _buildAuthPanel(authState),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthPanel(AuthUiState authState) {
    final theme = Theme.of(context);
    final signingInWithEmail = authState.isRunning(
      AuthOperation.emailSignIn,
    );
    final registering = authState.isRunning(AuthOperation.registration);
    final signingInWithGoogle = authState.isRunning(
      AuthOperation.googleSignIn,
    );
    final emailActionLoading = signingInWithEmail || registering;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _mode == _AuthMode.signIn ? 'Bentornato' : 'Crea il tuo account',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _mode == _AuthMode.signIn
              ? 'Accedi per ritrovare tutte le aste associate al tuo profilo.'
              : 'Registrati per salvare le tue aste e recuperarle su altri dispositivi.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        SegmentedButton<_AuthMode>(
          segments: const [
            ButtonSegment(
              value: _AuthMode.signIn,
              icon: Icon(Icons.login),
              label: Text('Accedi'),
            ),
            ButtonSegment(
              value: _AuthMode.register,
              icon: Icon(Icons.person_add_alt_1),
              label: Text('Registrati'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: authState.isLoading
              ? null
              : (selection) => _changeMode(selection.first),
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mode == _AuthMode.register) ...[
                TextFormField(
                  controller: _displayNameController,
                  enabled: !authState.isLoading,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.length < 2) {
                      return 'Inserisci il tuo nome.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _emailController,
                enabled: !authState.isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                enabled: !authState.isLoading,
                obscureText: _obscurePassword,
                textInputAction: _mode == _AuthMode.register
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: [
                  _mode == _AuthMode.register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onFieldSubmitted: (_) {
                  if (_mode == _AuthMode.signIn && !authState.isLoading) {
                    _submit();
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Mostra password'
                        : 'Nascondi password',
                    onPressed: authState.isLoading
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (password.isEmpty) return 'Inserisci la password.';
                  if (_mode == _AuthMode.register && password.length < 8) {
                    return 'Usa almeno 8 caratteri.';
                  }
                  return null;
                },
              ),
              if (_mode == _AuthMode.register) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  enabled: !authState.isLoading,
                  obscureText: _obscureConfirmation,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) {
                    if (!authState.isLoading) _submit();
                  },
                  decoration: InputDecoration(
                    labelText: 'Conferma password',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirmation
                          ? 'Mostra password'
                          : 'Nascondi password',
                      onPressed: authState.isLoading
                          ? null
                          : () => setState(
                              () => _obscureConfirmation =
                                  !_obscureConfirmation,
                            ),
                      icon: Icon(
                        _obscureConfirmation
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Le password non coincidono.';
                    }
                    return null;
                  },
                ),
              ],
              if (_mode == _AuthMode.signIn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: authState.isLoading
                        ? null
                        : _openPasswordReset,
                    child: const Text('Password dimenticata?'),
                  ),
                )
              else
                const SizedBox(height: 18),
              FilledButton(
                onPressed: authState.isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                ),
                child: emailActionLoading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(
                        _mode == _AuthMode.signIn
                            ? 'Accedi con email'
                            : 'Crea account',
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('oppure'),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 22),
        FilledButton.tonal(
          onPressed: authState.isLoading
              ? null
              : () => ref
                  .read(authControllerProvider.notifier)
                  .signInWithGoogle(),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (signingInWithGoogle)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    'G',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Text(
                signingInWithGoogle
                    ? 'Accesso in corso…'
                    : 'Continua con Google',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Proseguendo accetti che i dati delle aste vengano salvati sul tuo account Firebase.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Inserisci l’email.';

    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!valid) return 'Inserisci un indirizzo email valido.';
    return null;
  }
}

class PasswordResetDialog extends ConsumerStatefulWidget {
  final String initialEmail;

  const PasswordResetDialog({
    super.key,
    required this.initialEmail,
  });

  @override
  ConsumerState<PasswordResetDialog> createState() =>
      _PasswordResetDialogState();
}

class _PasswordResetDialogState
    extends ConsumerState<PasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sent = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordResetEmail(email: _emailController.text);

    if (sent && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isRunning(AuthOperation.passwordReset);

    return AlertDialog(
      icon: const Icon(Icons.mark_email_read_outlined),
      title: const Text('Recupera password'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Inserisci l’email del tuo account. Riceverai un collegamento per scegliere una nuova password.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _emailController,
                enabled: !loading,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: _LoginScreenState._validateEmail,
                onFieldSubmitted: (_) {
                  if (!loading) _send();
                },
              ),
              if (authState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  authState.errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: loading ? null : _send,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(loading ? 'Invio…' : 'Invia email'),
        ),
      ],
    );
  }
}

class _LoginHero extends StatelessWidget {
  final bool compact;

  const _LoginHero({required this.compact});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.grid_view_rounded,
            size: 38,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Mantra Matrix',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Il tuo muretto d’asta: consigli, scarsità, moduli, budget e cronologia sempre sincronizzati.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        const _FeatureRow(
          icon: Icons.cloud_done_outlined,
          text: 'Ritrova le tue aste dopo la reinstallazione.',
        ),
        const SizedBox(height: 12),
        const _FeatureRow(
          icon: Icons.lock_person_outlined,
          text: 'Ogni account accede soltanto ai propri dati.',
        ),
        const SizedBox(height: 12),
        const _FeatureRow(
          icon: Icons.devices_outlined,
          text: 'Accedi con Google oppure email e password.',
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
