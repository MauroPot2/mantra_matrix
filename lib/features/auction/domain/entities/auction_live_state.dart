import 'package:mantra_matrix/features/auction/domain/entities/auction_config.dart';

enum AuctionClockPhase { idle, running }

class AuctionLiveState {
  final AuctionClockPhase phase;
  final String? activePlayerId;
  final int currentBid;
  final DateTime? startedAt;
  final int extensionSeconds;
  final int revision;
  final DateTime? updatedAt;
  final String? controllerInstanceId;

  const AuctionLiveState({
    required this.phase,
    required this.activePlayerId,
    required this.currentBid,
    required this.startedAt,
    required this.extensionSeconds,
    required this.revision,
    required this.updatedAt,
    required this.controllerInstanceId,
  });

  const AuctionLiveState.idle()
      : phase = AuctionClockPhase.idle,
        activePlayerId = null,
        currentBid = 0,
        startedAt = null,
        extensionSeconds = 0,
        revision = 0,
        updatedAt = null,
        controllerInstanceId = null;

  bool get isRunning =>
      phase == AuctionClockPhase.running &&
      activePlayerId != null &&
      startedAt != null;

  bool isControlledBy(String instanceId) =>
      controllerInstanceId != null && controllerInstanceId == instanceId;

  DateTime? deadline(AuctionConfig config) {
    final start = startedAt;
    if (start == null) return null;
    return start.add(
      Duration(seconds: config.countdownSeconds + extensionSeconds),
    );
  }

  Duration remaining(
    AuctionConfig config, {
    DateTime? now,
  }) {
    final end = deadline(config);
    if (end == null) return Duration.zero;
    final remaining = end.difference((now ?? DateTime.now()).toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool isExpired(
    AuctionConfig config, {
    DateTime? now,
  }) => remaining(config, now: now) == Duration.zero;
}
