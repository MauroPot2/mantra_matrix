import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';

class AuctionControlBanner extends ConsumerWidget {
  final String sessionId;

  const AuctionControlBanner({
    required this.sessionId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(auctionLiveStateProvider(sessionId));
    final instanceId = ref.watch(auctionInstanceIdProvider);

    return live.when(
      loading: () => const _ControlShell(
        icon: Icons.sync_rounded,
        label: 'Allineamento controllo…',
      ),
      error: (error, stackTrace) => _ControlShell(
        icon: Icons.cloud_off_outlined,
        label: 'Controllo non disponibile',
        detail: error.toString(),
      ),
      data: (value) {
        if (value == null) {
          return const _ControlShell(
            icon: Icons.sync_rounded,
            label: 'Stato controller in arrivo…',
          );
        }

        if (value.isControlledBy(instanceId)) {
          return const _ControlShell(
            icon: Icons.sports_esports_rounded,
            label: 'Controller',
            detail: 'Questo dispositivo comanda l’asta',
          );
        }

        return _ControlShell(
          icon: Icons.visibility_outlined,
          label: 'Viewer',
          detail: 'Segui tutto in realtime senza creare conflitti',
          action: FilledButton.tonalIcon(
            onPressed: () => ref
                .read(auctionControllerProvider.notifier)
                .claimControl(),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Prendi controllo'),
          ),
        );
      },
    );
  }
}

class AuctionPreparingControlBanner extends StatelessWidget {
  const AuctionPreparingControlBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ControlShell(
      icon: Icons.cloud_upload_outlined,
      label: 'Preparazione sessione…',
      detail: 'I comandi si attivano dopo il primo salvataggio cloud',
    );
  }
}

class _ControlShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final Widget? action;

  const _ControlShell({
    required this.icon,
    required this.label,
    this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 370),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
