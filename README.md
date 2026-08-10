# Asta Matrix

Asta Matrix è un assistente indipendente per aste fantasy football costruito in Flutter e Firebase.

L'MVP è progettato per tenere separati **motore d'asta**, **dati importati** e **sincronizzazione realtime**. Le nuove sessioni non dipendono da un catalogo globale proprietario: ogni asta riceve esplicitamente il proprio dataset e ne conserva uno snapshot isolato.

## MVP

- autenticazione Firebase;
- home con aste live e concluse;
- import CSV / TSV / TXT con mapping delle colonne;
- origine del dato esplicita (`matrix`, `userImport`, `legacyCatalog`);
- configurazione crediti, squadre, rosa, moduli e budget reparto;
- event log immutabile per nomine, rilanci, assegnazioni, invenduti e undo;
- countdown realtime basato su timestamp Firestore server;
- **+5 secondi esatti per ogni vero rilancio**;
- calibrazione del clock locale rispetto al server;
- controller lease: una sola istanza app modifica l'asta, gli altri device sono viewer realtime;
- passaggio esplicito del controllo tra dispositivi;
- Matrix Advisor con valore e tetto consigliato;
- persistenza per-sessione del dataset in Firestore;
- compatibilità temporanea in sola lettura con sessioni legacy.

## Flusso dati

```text
File utente / futuro Matrix Database
              |
              v
        Player Importer
              |
              v
       Auction Session
       /      |       \
      /       |        \
 players    events     live/current
 snapshot   immutable  clock + controller lease
```

### Dataset

I nuovi dataset vengono scelti esplicitamente dall'utente. Il parser non è legato a un provider specifico e supporta intestazioni configurabili.

Campi minimi:

```csv
Nome;Squadra;Ruoli
Mario Rossi;TEST;DC/B
```

Campo opzionale:

```csv
Nome;Squadra;Ruoli;Prezzo
Mario Rossi;TEST;DC/B;7
```

Il prezzo importato è trattato come **valore base**, non come quotazione ufficiale di un servizio terzo.

## Firestore

Schema principale:

```text
users/{uid}

auction_sessions/{sessionId}
  metadata + config + initial_player_ids + initial_teams

auction_sessions/{sessionId}/players/{playerId}
  snapshot neutrale del dataset della sessione

auction_sessions/{sessionId}/events/{eventId}
  log immutabile dell'asta

auction_sessions/{sessionId}/live/current
  active_player_id
  current_bid
  started_at
  extension_seconds
  revision
  controller_instance_id
```

Il countdown **non viene scritto ogni secondo**. Firestore conserva solo il timestamp server di partenza e le estensioni; ogni device anima il timer localmente.

## Concorrenza multi-device

Una singola istanza possiede il lease `controller_instance_id`.

- il controller può produrre eventi;
- i viewer ricevono eventi, prezzo, timer e rose in realtime;
- un viewer può scegliere **Prendi controllo**;
- ogni mutazione è verificata in una transazione Firestore;
- gli eventi nuovi ricevono una `server_revision` monotona;
- un vecchio controller viene rifiutato se tenta di scrivere dopo un handoff.

Questo evita doppie verità durante rilanci simultanei o cambi di dispositivo.

## Compatibilità legacy

La collezione globale `/players` è mantenuta esclusivamente come ponte **read-only** per sessioni precedenti allo schema per-sessione. Quando una sessione legacy viene aperta, il repository può migrarla al nuovo snapshot isolato.

Nessuna nuova asta scrive nel catalogo globale.

## Qualità

La GitHub Action esegue:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug --no-pub
```

`pubspec.lock` risolto dalla CI viene pubblicato temporaneamente come artifact durante la transizione.

## Indipendenza del prodotto

Asta Matrix è progettato come software indipendente. Non effettua scraping automatico di piattaforme fantasy football di terze parti e il nuovo flusso non richiede dataset proprietari precaricati.

Prima della distribuzione commerciale restano necessari i normali adempimenti di pubblicazione, inclusi privacy policy pubblica, asset store definitivi, configurazione degli identificativi applicazione e verifica legale/marchi.
