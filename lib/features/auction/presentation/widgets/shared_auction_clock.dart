import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_live_state.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';

class SharedAuctionClock extends ConsumerStatefulWidget {
  final AuctionSession session;

  const SharedAuctionClock({
    required this.session,
    super.key,
  });

  @override
  ConsumerState<SharedAuctionClock> createState() => _SharedAuctionClockState();
}

class _SharedAuctionClockState extends ConsumerState<SharedAuctionClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncLive = ref.watch(auctionLiveStateProvider(widget.session.id));
    final localSnapshot = ref.watch(
      auctionControllerProvider.select((state) => state.snapshot),
    );

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
        child: asyncLive.when(
          loading: () => const _ClockShell(
            child: _ClockStatus(
              icon: Icons.sync_rounded,
              label: 'Sincronizzazione timer…',
            ),
          ),
          error: (error, stackTrace) => _ClockShell(
            child: _ClockStatus(
              icon: Icons.cloud_off_outlined,
              label: 'Timer offline',
              detail: error.toString(),
            ),
          ),
          data: (live) {
            final activePlayerId = localSnapshot?.activePlayerId;
            if (activePlayerId == null) {
              return const _ClockShell(
                child: _ClockStatus(
                  icon: Icons.timer_outlined,
                  label: 'Timer pronto',
                ),
              );
            }

            if (live == null ||
                live.activePlayerId != activePlayerId ||
                live.startedAt == null) {
              return const _ClockShell(
                child: _ClockStatus(
                  icon: Icons.sync_rounded,
                  label: 'Allineamento countdown…',
                ),
              );
            }

            return _RunningClock(
              live: live,
              session: widget.session,
              now: _now,
            );
          },
        ),
      ),
    );
  }
}

class _RunningClock extends StatelessWidget {
  final AuctionLiveState live;
  final AuctionSession session;
  final DateTime now;

  const _RunningClock({
    required this.live,
    required this.session,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final remaining = live.remaining(session.config, now: now);
    final totalSeconds =
        session.config.countdownSeconds + live.extensionSeconds;
    final remainingMs = remaining.inMilliseconds;
    final progress = totalSeconds <= 0
        ? 0.0
        : (remainingMs / (totalSeconds * 1000)).clamp(0.0, 1.0);
    final expired = remaining == Duration.zero;
    final urgent = remaining <= const Duration(seconds: 5);
    final foreground = expired || urgent ? colors.error : colors.primary;

    return _ClockShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded, color: foreground, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  expired ? 'TEMPO SCADUTO' : 'COUNTDOWN LIVE',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: foreground,
                  ),
                ),
              ),
              if (live.extensionSeconds > 0)
                Text(
                  '+${live.extensionSeconds}s',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatRemaining(remaining),
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: foreground,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Offerta ${live.currentBid} cr',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Rilancio +${session.config.bidExtensionSeconds}s',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatRemaining(Duration duration) {
    final milliseconds = duration.inMilliseconds;
    if (milliseconds <= 0) return '0.0';
    final seconds = milliseconds / 1000;
    if (seconds < 10) return seconds.toStringAsFixed(1);
    return seconds.ceil().toString();
  }
}

class _ClockShell extends StatelessWidget {
  final Widget child;

  const _ClockShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _ClockStatus extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;

  const _ClockStatus({
    required this.icon,
    required this.label,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (detail != null)
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
