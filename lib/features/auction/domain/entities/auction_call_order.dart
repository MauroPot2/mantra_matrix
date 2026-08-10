enum AuctionCallOrderMode { randomAll, randomByRole, alphabeticalByRole }

extension AuctionCallOrderModeX on AuctionCallOrderMode {
  String get label => switch (this) {
    AuctionCallOrderMode.randomAll => 'Random totale',
    AuctionCallOrderMode.randomByRole => 'Random per ruolo',
    AuctionCallOrderMode.alphabeticalByRole => 'Alfabetico per ruolo',
  };

  String get description => switch (this) {
    AuctionCallOrderMode.randomAll =>
      'Tutti i giocatori vengono mescolati in un unico ordine.',
    AuctionCallOrderMode.randomByRole =>
      'Ruoli in ordine Mantra, giocatori casuali dentro ogni ruolo.',
    AuctionCallOrderMode.alphabeticalByRole =>
      'Ruoli in ordine Mantra e nomi in ordine alfabetico.',
  };
}
