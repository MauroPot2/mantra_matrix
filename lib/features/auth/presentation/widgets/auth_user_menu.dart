import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auth/presentation/controllers/auth_controller.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';

enum _AuthMenuAction { signOut }

class AuthUserMenu extends ConsumerWidget {
  const AuthUserMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final authUi = ref.watch(authControllerProvider);

    if (user == null) return const SizedBox.shrink();

    final name = user.displayName?.trim();
    final initials = _initials(name, user.email);

    return PopupMenuButton<_AuthMenuAction>(
      tooltip: 'Account',
      enabled: !authUi.isLoading,
      onSelected: (action) async {
        if (action != _AuthMenuAction.signOut) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnettersi?'),
            content: const Text(
              'Le aste già sincronizzate resteranno salvate nel tuo account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Esci'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await ref.read(authControllerProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AuthMenuAction>(
          enabled: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _UserAvatar(photoUrl: user.photoURL, initials: initials),
              title: Text(name == null || name.isEmpty ? 'Account' : name),
              subtitle: Text(user.email ?? ''),
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_AuthMenuAction>(
          value: _AuthMenuAction.signOut,
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Esci dall’account'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _UserAvatar(
          photoUrl: user.photoURL,
          initials: initials,
          loading: authUi.isLoading,
        ),
      ),
    );
  }

  static String _initials(String? displayName, String? email) {
    final source = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : email?.split('@').first ?? 'U';
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final bool loading;

  const _UserAvatar({
    required this.photoUrl,
    required this.initials,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 18,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
      child: photoUrl == null ? Text(initials) : null,
    );

    if (!loading) return avatar;

    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.55, child: avatar),
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}
