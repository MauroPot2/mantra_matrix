import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/auction_home_screen.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';
import 'package:mantra_matrix/features/player_database/presentation/providers/player_providers.dart';

class AuctionBootstrapScreen extends ConsumerWidget {
  const AuctionBootstrapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Il vecchio catalogo viene caricato soltanto come ponte di compatibilità
    // per le sessioni create con schema <= 5. Non blocca più l'avvio dell'app
    // e non viene usato per creare nuove aste.
    final legacyPlayers = ref.watch(allPlayersProvider);

    return AuctionHomeScreen(
      players: legacyPlayers.valueOrNull ?? const <PlayerEntity>[],
    );
  }
}
