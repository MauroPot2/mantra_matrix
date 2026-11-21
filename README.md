# Mantra Matrix

Progetto Flutter per la gestione di attività legate a un fantacalcio con ruoli Mantra. L'applicazione è organizzata per funzionalità e utilizza Firebase per identità e dati condivisi.

## Funzionalità e struttura

Nel repository sono presenti moduli per:

- autenticazione e accesso degli utenti;
- archivio dei calciatori;
- gestione delle aste.

Il codice è suddiviso in `lib/features/auth/`, `lib/features/player_database/` e `lib/features/auction/`, con separazione fra dati, dominio e presentazione. `lib/core/` contiene componenti trasversali e tema dell'app.

## Stack

Flutter, Dart, Riverpod, Firebase Authentication, Cloud Firestore e accesso Google.

## Configurazione

Serve un progetto Firebase configurato per le piattaforme che si intende eseguire. Verificare i file di configurazione, le regole e le autorizzazioni prima dell'avvio: non utilizzare credenziali personali di altri ambienti.

~~~bash
flutter pub get
flutter run
~~~

## Verifiche

~~~bash
flutter analyze
flutter test
~~~

## Stato

Progetto in sviluppo. La presenza di un modulo o di una schermata non implica che il relativo flusso sia completo o pronto per un utilizzo competitivo reale. Le regole del fantacalcio e i dati dei giocatori vanno verificati prima di utilizzarli per calcoli ufficiali.
