import 'package:flutter/material.dart';

class LegalInfoScreen extends StatelessWidget {
  const LegalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informazioni e dati')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: const [
            _LegalHero(),
            SizedBox(height: 18),
            _InfoSection(
              icon: Icons.info_outline_rounded,
              title: 'Prodotto indipendente',
              body:
                  'Asta Matrix è uno strumento indipendente per la gestione di aste fantasy football. Non è un prodotto ufficiale e non è affiliato, sponsorizzato o approvato da piattaforme fantasy football di terze parti.',
            ),
            SizedBox(height: 12),
            _InfoSection(
              icon: Icons.upload_file_outlined,
              title: 'Dati importati',
              body:
                  'Per creare una nuova asta scegli tu il dataset da importare. Importa soltanto contenuti che hai il diritto di utilizzare. Asta Matrix non effettua scraping automatico di piattaforme di terze parti.',
            ),
            SizedBox(height: 12),
            _InfoSection(
              icon: Icons.cloud_outlined,
              title: 'Cosa viene salvato',
              body:
                  'Quando avvii un’asta, il dataset scelto viene copiato nello spazio della singola sessione insieme a configurazione, squadre ed eventi d’asta. Questo permette di riprendere la sessione senza dipendere dalla sorgente originale.',
            ),
            SizedBox(height: 12),
            _InfoSection(
              icon: Icons.person_outline_rounded,
              title: 'Account',
              body:
                  'L’autenticazione è gestita tramite Firebase Authentication. I dati delle aste sono associati all’account e protetti dalle regole di accesso del database.',
            ),
            SizedBox(height: 12),
            _InfoSection(
              icon: Icons.query_stats_outlined,
              title: 'Valori Matrix',
              body:
                  'Consigli, indici e valori calcolati dall’app sono strumenti di supporto e non rappresentano quotazioni ufficiali di servizi terzi.',
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalHero extends StatelessWidget {
  const _LegalHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 42),
          const SizedBox(height: 14),
          Text(
            'Asta Matrix mette il software al centro.',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'I dati della tua asta hanno una provenienza esplicita e restano separati dal motore di calcolo e sincronizzazione dell’app.',
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
