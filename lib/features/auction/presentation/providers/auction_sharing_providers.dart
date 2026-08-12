import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/auction/data/repositories/firestore_auction_sharing_repository.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';
import 'package:mantra_matrix/features/auction/domain/repositories/auction_sharing_repository.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';

final auctionSharingRepositoryProvider = Provider<AuctionSharingRepository>((ref) {
  final uid = ref.watch(currentUserUidProvider);
  if (uid == null) {
    throw StateError('È necessario accedere prima di condividere un’asta.');
  }

  return FirestoreAuctionSharingRepository(
    ref.watch(firebaseFirestoreProvider),
    currentUid: uid,
  );
});

final pendingAuctionJoinRequestsProvider =
    StreamProvider.autoDispose<List<AuctionJoinRequest>>((ref) {
  return ref.watch(auctionSharingRepositoryProvider).watchPendingRequests();
});

final sharedAuctionSessionsProvider =
    StreamProvider.autoDispose<List<AuctionSessionSummary>>((ref) {
  return ref.watch(auctionSharingRepositoryProvider).watchSharedSessions();
});

final auctionJoinRequestProvider = StreamProvider.autoDispose
    .family<AuctionJoinRequest?, String>((ref, requestId) {
  return ref
      .watch(auctionSharingRepositoryProvider)
      .watchRequest(requestId: requestId);
});

final auctionSessionOwnershipProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, sessionId) async {
  final uid = ref.watch(currentUserUidProvider);
  if (uid == null) return false;
  final document = await ref
      .watch(firebaseFirestoreProvider)
      .collection('auction_sessions')
      .doc(sessionId)
      .get();
  return document.data()?['owner_uid']?.toString() == uid;
});
