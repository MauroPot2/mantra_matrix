# Asta Matrix — MVP release checklist

## Runtime

- [x] Nuove aste senza catalogo globale implicito
- [x] Import CSV / TSV / TXT con mapping colonne
- [x] Snapshot giocatori isolato per sessione
- [x] Event log immutabile
- [x] Ripristino aste schema 7 senza catalogo globale
- [x] Migrazione compatibile delle sessioni legacy
- [x] Countdown basato su timestamp Firestore server
- [x] +5 secondi per ogni vero rilancio
- [x] Calibrazione del clock locale rispetto al server
- [x] Controller/viewer lease per evitare multi-writer concorrenti
- [x] Handoff esplicito “Prendi controllo”
- [x] Viewer con UI di mutazione disabilitata
- [x] Rollback verso lo stato autorevole se una mutazione viene rifiutata
- [x] Dashboard live indipendente
- [x] Matrix Advisor senza etichette FVM nel percorso pubblico

## Data & security

- [x] `/players` globale read-only e solo legacy
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
- [x] Analyzer diagnostics conservati come artifact
- [ ] Ultima pipeline branch completamente verde dopo controller lease
- [ ] Test manuale su almeno due dispositivi fisici
- [ ] Misura pratica della latenza countdown/rilancio su rete reale

## Prima dello store

- [ ] Deploy delle Firestore rules aggiornate nel progetto Firebase
- [ ] Privacy Policy pubblica con URL stabile
- [ ] Termini/contatti di supporto pubblici
- [ ] Verifica finale marchio/nome da professionista IP/IT
- [ ] App icon e asset store definitivi
- [ ] Bundle identifier definitivo e relativo riallineamento Firebase/signing
- [ ] Build iOS/macOS release su runner Apple o macchina di sviluppo
- [ ] Test import file su Android, iOS e macOS release
- [ ] Store metadata e screenshot

## Fuori dall’MVP corrente

- Database Matrix proprietario/licenziato
- XLSX nativo (il flusso MVP accetta CSV/TSV/TXT)
- Inviti e join tra account Firebase distinti
- Ruoli completamente dinamici al posto dell’enum tattico interno legacy
- Monetizzazione / subscription
