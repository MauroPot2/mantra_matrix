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

/// Invito privato attualmente attivo dell'owner.
///
/// Serve alla UI per riaprire il pannello Condividi senza rigenerare token e
/// codice, così le richieste già inviate restano approvabili.
final currentAuctionShareInviteProvider = FutureProvider.autoDispose
    .family<AuctionShareInvite?, String>((ref, sessionId) async {
  final uid = ref.watch(currentUserUidProvider);
  if (uid == null) return null;

  final document = await ref
      .watch(firebaseFirestoreProvider)
      .collection('auction_sessions')
      .doc(sessionId)
      .collection('private')
      .doc('sharing')
      .get();
  final data = document.data();
  if (!document.exists ||
      data == null ||
      data['enabled'] != true ||
      data['owner_uid']?.toString() != uid) {
    return null;
  }

  final ownerUid = data['owner_uid']?.toString();
  final token = data['token']?.toString();
  final entryCode = AuctionShareInvite.normalizeEntryCode(
    data['entry_code']?.toString() ?? '',
  );
  if (ownerUid == null ||
      ownerUid.isEmpty ||
      token == null ||
      token.length < 32 ||
      entryCode.length != 8) {
    return null;
  }

  return AuctionShareInvite(
    sessionId: sessionId,
    ownerUid: ownerUid,
    token: token,
    entryCode: entryCode,
  );
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
