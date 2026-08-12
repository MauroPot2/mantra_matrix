import 'package:flutter/material.dart';
import 'package:mantra_matrix/features/auction/presentation/screens/auction_home_screen.dart';

class AuctionBootstrapScreen extends StatelessWidget {
  const AuctionBootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Le nuove sessioni scelgono esplicitamente il proprio dataset e le aste
    // persistite da schema 7 in poi contengono uno snapshot per-sessione.
    // Nessun catalogo globale viene più letto all'avvio dell'app.
    return const AuctionHomeScreen(players: []);
  }
}
