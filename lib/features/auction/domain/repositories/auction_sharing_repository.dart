import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';

abstract class AuctionSharingRepository {
  Future<AuctionShareInvite> createInvite({
    required String sessionId,
    bool regenerate = false,
  });

  Future<void> disableSharing({required String sessionId});

  Future<String> requestAccess({required AuctionShareInvite invite});

  Future<String> requestAccessByCode({required String entryCode});

  Stream<List<AuctionJoinRequest>> watchPendingRequests();

  Stream<AuctionJoinRequest?> watchRequest({required String requestId});

  Future<void> approveRequest({
    required String requestId,
    required String assignedTeamId,
  });

  Future<void> rejectRequest({required String requestId});

  Stream<List<AuctionSessionSummary>> watchSharedSessions();
}

class AuctionSharingException implements Exception {
  final String message;

  const AuctionSharingException(this.message);

  @override
  String toString() => message;
}
