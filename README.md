# sqlpractice – PostgreSQL zum Üben

Startet PostgreSQL 17 in einem Container (Podman oder Docker) und lädt zwei Beispiel-Datenbanken:

| Datenbank     | Inhalt |
|---------------|--------|
| `sportverein` | Übungsdatenbank zu „Datenbanken I“ (DHBW Mannheim, Übungsblöcke 1–10). Die Daten sind rekonstruiert, sodass die Ergebnisse auf den Folien herauskommen. |
| `pagila`      | Pagila v3.1.0 (DVD-Verleih), zum freien Üben |

## Voraussetzungen

- Podman (empfohlen) oder Docker (Kann eigene Konfiguration und Änderungen am skript benötigen)
- `git` (zum einmaligen Herunterladen von Pagila, sollte aber bereits installiert sein wenn der code runtergeladen wird ;))
- Linux, macOS (Podman/Docker Desktop) oder WSL

## Start

```bash
git clone https://github.com/Sandpit0/datenbanken_uebungen.git && cd datenbanken_uebungen
./sqlpractice.sh
```

Beim ersten Start wird ein zufälliges Passwort erzeugt und in
`~/.config/sqlpractice/password-sqlpractice` gespeichert. Außerdem wird es in `~/.pgpass`
eingetragen, damit `psql`/`pgcli` ohne Passwortabfrage verbinden.
Das Passwort steht nie im Repo.

Ein eigenes Passwort setzt du mit `./sqlpractice.sh set-password`. Es wird in der Datenbank,
in der Passwortdatei und in `~/.pgpass` geändert. Ändere es nicht direkt mit
`ALTER ROLE` oder `\password`: Das Skript stellt bei jedem Start das Passwort aus der Datei wieder her.

## Befehle

```bash
./sqlpractice.sh             # starten
./sqlpractice.sh psql        # psql im Container (Datenbank sportverein)
./sqlpractice.sh psql pagila # psql auf pagila
./sqlpractice.sh reset       # sportverein auf Ausgangszustand zurücksetzen
./sqlpractice.sh password    # Passwort anzeigen (z. B. für DBeaver/pgAdmin)
./sqlpractice.sh set-password  # eigenes Passwort setzen (mind. 8 Zeichen)
./sqlpractice.sh stop        # stoppen
./sqlpractice.sh recreate    # Image aktualisieren, Container neu anlegen (Daten bleiben)
```

In DBeaver/pgAdmin/DataGrip: Host `localhost`, Port `5432`, Benutzer `postgres`,
Passwort aus `./sqlpractice.sh password`.

Ein anderer Port, z. B. weil lokal schon ein PostgreSQL läuft:

```bash
SQLPRACTICE_PORT=5433 ./sqlpractice.sh
```

Alles komplett entfernen:

```bash
podman rm -f sqlpractice && podman volume rm sqlpractice-pgdata
rm -rf ~/.config/sqlpractice ~/.cache/sqlpractice
```
