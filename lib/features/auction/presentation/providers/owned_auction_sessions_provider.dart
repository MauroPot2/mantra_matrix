import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_session_summary.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';

final ownedAuctionSessionsProvider =
    StreamProvider.autoDispose<List<AuctionSessionSummary>>((ref) {
      final repository = ref.watch(auctionSessionRepositoryProvider);
      return repository.watchOwnedSessions();
    });
