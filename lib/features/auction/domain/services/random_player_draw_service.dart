import 'dart:math';

import 'package:mantra_matrix/features/auction/domain/entities/auction_session.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

class RandomPlayerDrawException implements Exception {
  final String message;

  const RandomPlayerDrawException(this.message);

  @override
  String toString() => message;
}

class RandomPlayerDrawService {
  final Random _random;

  RandomPlayerDrawService({Random? random}) : _random = random ?? Random.secure();

  /// Estrae soltanto al momento della chiamata.
  ///
  /// Non viene mai generata né conservata una sequenza futura: il prossimo
  /// giocatore non è quindi conoscibile in anticipo da UI, Firestore o viewer.
  PlayerEntity draw(AuctionSessionSnapshot snapshot) {
    if (snapshot.activePlayerId != null) {
      throw const RandomPlayerDrawException(
        'Concludi prima la chiamata attiva.',
      );
    }

    final candidates = snapshot.uncalledPlayers;
    if (candidates.isEmpty) {
      throw const RandomPlayerDrawException(
        'Non ci sono più giocatori mai chiamati da estrarre.',
      );
    }

    return candidates[_random.nextInt(candidates.length)];
  }
}
