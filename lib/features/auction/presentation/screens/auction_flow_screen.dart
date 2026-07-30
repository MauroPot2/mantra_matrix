import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/presentation/controllers/auction_controller.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/auction_setup_screen.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/live_auction_screen.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

/// Route dedicata a una singola asta.
///
/// La selezione della sessione avviene nella AuctionHomeScreen: questa route
/// mostra il setup per una nuova asta oppure la dashboard live per una sessione
/// già caricata nel controller.
class AuctionFlowScreen extends ConsumerWidget {
  final List<PlayerEntity> players;

  const AuctionFlowScreen({required this.players, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auctionControllerProvider);

    if (state.isRestoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Apertura dell’asta…'),
            ],
          ),
        ),
      );
    }

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && state.isStarted) {
          ref.read(auctionControllerProvider.notifier).closeSession();
        }
      },
      child: state.isStarted
          ? const LiveAuctionScreen()
          : AuctionSetupScreen(players: players),
    );
  }
}
