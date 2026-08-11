# Asta Matrix — MVP release checklist

## Runtime core

- [x] Nuove aste senza catalogo globale implicito
- [x] Import CSV / TSV / TXT con mapping colonne
- [x] Snapshot giocatori isolato per sessione
- [x] Schema 7 come formato minimo indipendente supportato
- [x] Event log immutabile
- [x] Ripristino aste schema 7 dal solo snapshot per-sessione
- [x] Countdown basato su timestamp Firestore server
- [x] +5 secondi per ogni vero rilancio, indipendente dall'importo
- [x] Nessuna estensione sulle correzioni prezzo
- [x] Calibrazione del clock locale rispetto al server
- [x] Pending event merge stabile durante ACK Firestore progressivi
- [x] Stress test automatico con 25 rilanci rapidi e 125 secondi totali di estensione
- [x] Undo timer deterministico per rilancio, correzione, nomina e chiusura chiamata
- [x] Controller/viewer lease per evitare multi-writer concorrenti
- [x] Blocco client delle mutazioni Viewer prima dello stato ottimistico
- [x] Handoff esplicito tra dispositivi autenticati come owner
- [x] Rollback/ripristino verso lo stato autorevole se una mutazione viene rifiutata
- [x] Chiusura asta cloud-authoritative: la live locale si chiude solo dopo il commit
- [x] Dashboard live indipendente
- [x] Matrix Advisor senza etichette FVM nel percorso pubblico

## Sharing sotto il cofano

- [x] Token invito casuale 192-bit
- [x] Token memorizzato in subcollection privata owner-only
- [x] Payload `astamatrix://join`
- [x] Richiesta accesso separata dalla membership
- [x] Richieste leggibili solo da requester e owner indicato
- [x] Approvazione/rifiuto owner-only
- [x] Approvazione vincolata al token privato corrente
- [x] Associazione obbligatoria del membro a una squadra dell'asta
- [x] Prevenzione associazione della stessa squadra a più membri
- [x] Sessioni condivise individuabili tramite `member_uids`
- [x] Viewer cross-account in sola lettura a livello client + Security Rules
- [x] Viewer approvato può ripristinare snapshot giocatori, eventi e stato live della stessa asta
- [ ] UX per creare/condividere invito, richiedere accesso e approvare la squadra
- [ ] Deep-linking nativo del protocollo `astamatrix://join`

## Data & security

- [x] Nessuna lettura runtime del catalogo globale `/players`
- [x] Accesso client a `/players` globale negato dalle Security Rules
- [x] Rimossi provider/repository legacy del catalogo globale
- [x] Sessioni pre-schema-7 respinte esplicitamente invece di riaprire il bridge legacy
- [x] Firestore rules versionate nel repository
- [x] Dataset per sessione in subcollection
- [x] Stato realtime minimale in `live/current`
- [x] Nessuna scrittura cloud ogni secondo per il timer
- [x] Eventi nuovi con revisione server monotona
- [x] Informazioni in-app su indipendenza e provenienza dati

## Quality gate

- [x] GitHub Actions per `flutter analyze`
- [x] GitHub Actions per `flutter test`
- [x] Smoke build Android configurato
- [x] Android release build CI configurato
- [x] Apple build CI configurato
- [x] Firestore Security Rules emulator CI configurata
- [x] Analyzer diagnostics conservati come artifact
- [x] Test automatici di race/pending event ordering
- [x] Test automatici Viewer mutation guard
- [x] Test automatici Undo clock semantics
- [x] Test automatici cloud-authoritative completion
- [x] Test automatici Security Rules sharing/membership/private token
- [ ] Ultima pipeline branch completamente verde
- [ ] Test manuale su almeno due dispositivi fisici
- [ ] Misura pratica della latenza countdown/rilancio su rete reale
- [ ] Test fisico Wi-Fi + rete cellulare
- [ ] Test manuale cross-account dopo integrazione UX sharing

## Prima dello store

- [ ] Deploy delle Firestore rules aggiornate nel progetto Firebase
- [ ] Cancellazione account direttamente nell'app
- [ ] Privacy Policy pubblica con URL stabile
- [ ] Termini/contatti di supporto pubblici
- [ ] Verifica finale marchio/nome da professionista IP/IT
- [ ] App icon e asset store definitivi
- [ ] Bundle identifier definitivo e relativo riallineamento Firebase/signing
- [ ] Build iOS/macOS release definitiva con signing reale
- [ ] Test import file su Android, iOS e macOS release
- [ ] Store metadata e screenshot

## Fuori dal motore MVP congelato

- Database Matrix proprietario/licenziato
- XLSX nativo (il flusso MVP accetta CSV/TSV/TXT)
- Ruoli completamente dinamici al posto dell'enum tattico interno legacy
- Monetizzazione / subscription
- Restyling UX/UI completo
