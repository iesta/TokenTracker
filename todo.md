# TODO

## Data Sources

- [x] OpenCode local (SQLite)
- [x] Pi Agent (JSONL sessions)
- [x] OpenCode Go
- [x] OpenRouter (API key from env or manual entry)
- [ ] **Remote SSH** — ajouter support pour ouvrir une DB opencode distante via `ssh user@host sqlite3 -json /path/opencode.db`
  - [ ] Nouveau `kind: .remoteSSH` dans `OpenCodeSource`
  - [ ] Formulaire d'ajout dans Settings (host, port, user, remote path)
  - [ ] `queryDB` adaptée pour lancer le process SSH au lieu de sqlite3 local
  - [ ] Cache : signature via `ssh stat` ou TTL court
  - [ ] Bouton "Test connection" dans les prefs

## Features

- [ ] Rafraîchissement manuel par source (bouton refresh individuel dans Data settings)
- [ ] Barre de progression pendant le scan multi-source
- [ ] Icônes personnalisées pour chaque source dans la sidebar

## Polish

- [ ] Captures d'écran du popover + préférences pour le README