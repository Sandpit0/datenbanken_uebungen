#!/usr/bin/env bash
# sqlpractice.sh – lokaler PostgreSQL-Übungscontainer
#
# Lädt beim ersten Start zwei Beispiel-Datenbanken:
#   pagila       – Pagila-Beispieldatenbank (DVD-Verleih)
#   sportverein  – Übungsdatenbank zu "Datenbanken I" (DHBW Mannheim),
#                  aus sportverein_setup.sql im selben Ordner
#
# Nutzung:
#   ./sqlpractice.sh             starten (beim 1. Mal: anlegen + Daten laden)
#   ./sqlpractice.sh psql [DB]   psql im Container öffnen (Standard: sportverein)
#   ./sqlpractice.sh reset       sportverein auf den Ausgangszustand zurücksetzen
#   ./sqlpractice.sh password    Passwort anzeigen
#   ./sqlpractice.sh set-password  eigenes Passwort setzen
#   ./sqlpractice.sh stop        Container stoppen
#   ./sqlpractice.sh recreate    Image aktualisieren, Container neu anlegen
#                                (Daten im Volume bleiben erhalten)
#
# Optionale Einstellungen per Umgebungsvariable:
#   SQLPRACTICE_PORT    Port auf dem eigenen Rechner     (Standard: 5432)
#   SQLPRACTICE_ENGINE  podman oder docker               (Standard: automatisch)
#   SQLPRACTICE_NAME    Containername                    (Standard: sqlpractice)
#   SQLPRACTICE_IMAGE   PostgreSQL-Image                 (Standard: postgres:17)
#   SQLPRACTICE_PGPASS  0 = ~/.pgpass nicht anfassen     (Standard: 1)
set -euo pipefail

NAME="${SQLPRACTICE_NAME:-sqlpractice}"
IMAGE="${SQLPRACTICE_IMAGE:-docker.io/library/postgres:17}"
PORT="${SQLPRACTICE_PORT:-5432}"
VOLUME="${SQLPRACTICE_VOLUME:-${NAME}-pgdata}"
WRITE_PGPASS="${SQLPRACTICE_PGPASS:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sqlpractice"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sqlpractice"
PASSWORD_FILE="$CONFIG_DIR/password-$NAME"

# Pagila auf einen festen Commit pinnen: Das SQL läuft als Superuser,
# deshalb soll nicht ungeprüft der jeweils neueste Stand ausgeführt werden.
# v3.1.0 ist die letzte Version, die mit dem offiziellen postgres-Image läuft;
# ab v4.0.0 braucht Pagila PostgreSQL 18 + die Erweiterung pgvector.
PAGILA_REPO="https://github.com/devrimgunduz/pagila.git"
PAGILA_COMMIT="fef9675714cfba1756df4719b5e36075a7ddf90e"   # Tag pagila-v3.1.0
PAGILA_DIR="$CACHE_DIR/pagila"

SPORTVEREIN_SQL="$SCRIPT_DIR/sportverein_setup.sql"

die()  { echo "Fehler: $*" >&2; exit 1; }
info() { echo "$*"; }

# --- Container-Engine ------------------------------------------------------
if [ -n "${SQLPRACTICE_ENGINE:-}" ]; then
    ENGINE="$SQLPRACTICE_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
else
    die "Weder podman noch docker gefunden."
fi
command -v "$ENGINE" >/dev/null 2>&1 || die "'$ENGINE' nicht gefunden."

container_exists()  { "$ENGINE" container inspect "$NAME" >/dev/null 2>&1; }
container_running() { [ "$("$ENGINE" container inspect -f '{{.State.Running}}' "$NAME")" = "true" ]; }

# psql als Superuser über den Unix-Socket im Container (dort: trust)
psql_admin() {
    "$ENGINE" exec -i -e PGOPTIONS="-c client_min_messages=warning" "$NAME" \
        psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"
}
require_running() {
    if ! container_exists || ! container_running; then
        die "Container läuft nicht – erst '$0' ausführen."
    fi
}

db_exists() {
    [ "$("$ENGINE" exec "$NAME" psql -X -U postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '$1'")" = "1" ]
}

# --- Passwort: zufällig, pro Rechner, nie im Skript/Repo --------------------
ensure_password() {
    if [ ! -s "$PASSWORD_FILE" ]; then
        (
            umask 077
            mkdir -p "$CONFIG_DIR"
            head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$PASSWORD_FILE"
        )
        info "Neues Passwort erzeugt: $PASSWORD_FILE"
    fi
    chmod 600 "$PASSWORD_FILE"
    PASSWORD=""
    IFS= read -r PASSWORD < "$PASSWORD_FILE" || true   # nur die erste Zeile
    [ -n "$PASSWORD" ] || die "$PASSWORD_FILE ist leer."
}

# Eigenes Passwort setzen: interaktiv (verdeckt, zweimal) oder über stdin,
# z. B.  ./sqlpractice.sh set-password < datei
set_password() {
    local pw="" pw2=""
    if [ -t 0 ]; then
        read -rsp "Neues Passwort: " pw; echo
        read -rsp "Wiederholen:    " pw2; echo
        [ "$pw" = "$pw2" ] || die "Die Passwörter stimmen nicht überein."
    else
        IFS= read -r pw || true
    fi
    [ "${#pw}" -ge 8 ] || die "Das Passwort muss mindestens 8 Zeichen haben."

    ( umask 077; mkdir -p "$CONFIG_DIR"; printf '%s\n' "$pw" > "$PASSWORD_FILE" )
    chmod 600 "$PASSWORD_FILE"
    PASSWORD="$pw"

    if container_exists && container_running; then
        sync_password
        update_pgpass
        info "Passwort gesetzt."
    else
        info "Passwort gespeichert – wird beim nächsten Start übernommen."
    fi
}

# Passwort der Datenbank an die Datei angleichen (über stdin, nicht über argv).
# Macht auch alte Container mit Standardpasswort sicher.
sync_password() {
    local q="'" pw_sql
    pw_sql="${PASSWORD//$q/$q$q}"          # ' -> '' (SQL-String-Literal)
    printf "ALTER ROLE postgres PASSWORD '%s';\n" "$pw_sql" | psql_admin -d postgres
}

update_pgpass() {
    [ "$WRITE_PGPASS" = "1" ] || return 0
    local pgpass="$HOME/.pgpass" tmp pw_esc
    pw_esc="${PASSWORD//\\/\\\\}"          # \ -> \\   (Format von .pgpass)
    pw_esc="${pw_esc//:/\\:}"              # : -> \:
    ( umask 077; touch "$pgpass" )
    tmp="$(mktemp "$pgpass.XXXXXX")"
    grep -v "^localhost:$PORT:\*:postgres:" "$pgpass" > "$tmp" || true
    printf '%s\n' "localhost:$PORT:*:postgres:$pw_esc" >> "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$pgpass"
}

# --- Container -------------------------------------------------------------
create_container() {
    info "Lege Container '$NAME' an ($ENGINE, $IMAGE)..."
    # Port nur auf 127.0.0.1: Ohne das wäre die DB im ganzen Netz erreichbar
    # (z. B. im Uni-WLAN), bei Docker sogar an der Firewall vorbei.
    # Passwort über die Umgebung statt über die Kommandozeile übergeben.
    POSTGRES_PASSWORD="$PASSWORD" "$ENGINE" run -d --name "$NAME" \
        -e POSTGRES_PASSWORD \
        -p "127.0.0.1:$PORT:5432" \
        -v "$VOLUME:/var/lib/postgresql/data" \
        "$IMAGE" >/dev/null
}

check_port_binding() {
    local ips
    # shellcheck disable=SC2016  # Go-Template, kein Shell-Ausdruck
    ips="$("$ENGINE" container inspect -f \
        '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}[{{.HostIp}}] {{end}}{{end}}' \
        "$NAME")"
    for ip in $ips; do
        case "$ip" in
            "[127.0.0.1]"|"[::1]") ;;
            *) die "Container '$NAME' ist im ganzen Netzwerk erreichbar (Port-Bindung $ip).
Neu anlegen mit:  $0 recreate   (Daten im Volume bleiben erhalten)" ;;
        esac
    done
}

wait_ready() {
    printf "Warte auf PostgreSQL"
    for _ in $(seq 1 60); do
        # -h 127.0.0.1: Während der Erstinitialisierung läuft ein temporärer
        # Server nur auf dem Socket; erst TCP heißt "wirklich fertig".
        if "$ENGINE" exec "$NAME" pg_isready -h 127.0.0.1 -U postgres -q 2>/dev/null; then
            echo " bereit."
            return 0
        fi
        printf "."
        sleep 1
    done
    echo
    "$ENGINE" logs --tail 20 "$NAME" >&2 || true
    die "PostgreSQL ist nach 60 s nicht bereit."
}

# --- Beispieldaten ---------------------------------------------------------
fetch_pagila() {
    if [ "$(git -C "$PAGILA_DIR" rev-parse HEAD 2>/dev/null || true)" != "$PAGILA_COMMIT" ]; then
        command -v git >/dev/null 2>&1 || die "git wird zum Herunterladen von Pagila benötigt."
        info "Lade Pagila (Commit ${PAGILA_COMMIT:0:12})..."
        rm -rf "$PAGILA_DIR"
        mkdir -p "$PAGILA_DIR"
        git -C "$PAGILA_DIR" init -q
        git -C "$PAGILA_DIR" fetch -q --depth 1 "$PAGILA_REPO" "$PAGILA_COMMIT"
        git -C "$PAGILA_DIR" checkout -q --detach FETCH_HEAD
    fi
}

# load_db <datenbank> <sql-datei>...  – bei Fehlern wird die DB wieder gelöscht,
# damit der nächste Start sauber neu lädt statt eine halbe DB zu behalten.
load_db() {
    local db="$1"; shift
    "$ENGINE" exec "$NAME" createdb -U postgres "$db"
    for f in "$@"; do
        if ! psql_admin -d "$db" < "$f" >/dev/null; then
            "$ENGINE" exec "$NAME" dropdb -U postgres --if-exists "$db" || true
            die "Laden von $(basename "$f") in '$db' fehlgeschlagen."
        fi
    done
}

load_sample_data() {
    if ! db_exists pagila; then
        fetch_pagila
        info "Lade Datenbank 'pagila'..."
        load_db pagila "$PAGILA_DIR/pagila-schema.sql" "$PAGILA_DIR/pagila-data.sql"
    fi
    if ! db_exists sportverein; then
        [ -f "$SPORTVEREIN_SQL" ] || die "$SPORTVEREIN_SQL fehlt (muss neben dem Skript liegen)."
        info "Lade Datenbank 'sportverein'..."
        load_db sportverein "$SPORTVEREIN_SQL"
    fi
}

start() {
    ensure_password
    if ! container_exists; then
        create_container
    else
        check_port_binding
        if ! container_running; then
            info "Starte Container '$NAME'..."
            "$ENGINE" start "$NAME" >/dev/null
        else
            info "Container '$NAME' läuft bereits."
        fi
    fi
    wait_ready
    sync_password
    update_pgpass
    load_sample_data

    cat <<EOF

Verbindung:  Host localhost, Port $PORT, Benutzer postgres
Datenbanken: sportverein, pagila
Passwort:    $PASSWORD_FILE$( [ "$WRITE_PGPASS" = "1" ] && echo " (auch in ~/.pgpass eingetragen)" )

  $0 psql                      # psql direkt im Container
  pgcli -h localhost -p $PORT -U postgres sportverein
EOF
}

# --- Befehle ---------------------------------------------------------------
case "${1:-start}" in
    start)
        start ;;
    stop)
        if container_exists; then
            "$ENGINE" stop "$NAME" >/dev/null && info "Gestoppt."
        else
            info "Container '$NAME' existiert nicht."
        fi ;;
    psql)
        require_running
        exec "$ENGINE" exec -it "$NAME" psql -U postgres -d "${2:-sportverein}" ;;
    reset)
        require_running
        [ -f "$SPORTVEREIN_SQL" ] || die "$SPORTVEREIN_SQL fehlt."
        "$ENGINE" exec "$NAME" dropdb -U postgres --if-exists --force sportverein
        load_db sportverein "$SPORTVEREIN_SQL"
        info "Datenbank 'sportverein' zurückgesetzt." ;;
    password)
        ensure_password; echo "$PASSWORD" ;;
    set-password)
        set_password ;;
    recreate)
        ensure_password
        "$ENGINE" pull "$IMAGE" >/dev/null
        if container_exists; then "$ENGINE" rm -f "$NAME" >/dev/null; fi
        start ;;
    -h|--help|help)
        awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" ;;
    *)
        die "Unbekannter Befehl '$1' – siehe '$0 --help'." ;;
esac
