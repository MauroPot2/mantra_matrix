# Mantra Matrix

App Flutter per gestire un'asta di fantacalcio Mantra con Firebase
Authentication e Cloud Firestore.

## Funzionalità

- configurazione di rose, crediti, moduli e strategia d'asta;
- sessioni persistenti e ripristinabili;
- asta condivisa tramite codice di sei caratteri;
- offerte sincronizzate in tempo reale con controllo di concorrenza;
- timer a durata selezionabile (15–120 secondi) e chiusura automatica del
  lotto da parte del creatore dell'asta;
- ordine di chiamata casuale totale, casuale per ruolo oppure alfabetico per
  ruolo;
- gestione versionata del listone con import JSON, CSV, TSV o testo separato
  da punto e virgola;
- storico eventi append-only, annullamento dell'ultima azione e snapshot dei
  giocatori usati da ogni asta.

## Avvio locale

Sono richiesti Flutter compatibile con Dart `^3.12.2` e un progetto Firebase.
La configurazione Firebase inclusa punta al progetto di sviluppo già associato
all'app.

```sh
flutter pub get
flutter run
```

Prima di usare il listone e le sessioni condivise, pubblicare le regole
Firestore:

```sh
firebase deploy --only firestore:rules
```

Le regole sono definite in `firestore.rules` e referenziate da `firebase.json`.

## Aggiornare il listone

La schermata **Listone giocatori** mostra versione, data e numero di giocatori
attivi. L'importazione è riservata agli amministratori. Un utente è
amministratore quando ha il custom claim Firebase `admin: true` oppure quando
il documento `users/{uid}` contiene `is_admin: true`; questo valore va impostato
da un ambiente amministrativo attendibile, non dall'app client.

L'import accetta:

- un array JSON, oppure un oggetto con array in `players`, `data` o `items`;
- CSV/TSV con intestazioni; il separatore `;` è supportato;
- alias comuni come `player_id`, `understat_id`, `name`/`nome`,
  `team`/`squadra`, `roles`/`ruoli` e `position`.

In modalità **Sostituisci**, i giocatori assenti dal nuovo file vengono
disattivati senza essere eliminati. In modalità **Unisci**, il catalogo
esistente resta attivo e i record importati vengono aggiunti o aggiornati.
Ogni nuova asta conserva inoltre una copia del listone iniziale, quindi un
aggiornamento non altera le sessioni già create.

## Asta condivisa

Il creatore abilita la condivisione nel setup e comunica il codice mostrato
nella schermata live. Un partecipante inserisce il codice dalla home e sceglie
una squadra ancora libera. Il creatore gestisce chiamate, assegnazioni,
annullamenti e chiusura; ogni partecipante può rilanciare solo per la propria
squadra.

Il timer ha una scadenza assoluta salvata nell'evento di chiamata e non viene
esteso dai rilanci. Alla scadenza, il client del creatore assegna il giocatore
al miglior offerente oppure lo marca invenduto. Per una chiusura garantita anche
quando tutti i client sono offline è necessario aggiungere un backend
schedulato, ad esempio Cloud Functions con Cloud Tasks.

## Verifiche

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

I test di dominio coprono parsing del listone, generazione degli ordini di
chiamata e chiusura dei lotti con e senza offerte.
