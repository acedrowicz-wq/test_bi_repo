#!/usr/bin/env python3
"""
CZĘŚĆ 1 - zmiany na Tableau Server / Tableau Cloud przez tableauserverclient (TSC).

Skrypt loguje się Personal Access Tokenem (PAT) i wykonuje do trzech operacji:
  1. aktualizacja poświadczeń (username/password) w połączeniach opublikowanego źródła danych,
  2. zmiana właściciela skoroszytu,
  3. dodanie tagów do skoroszytu.

Każdą operację włączasz/wyłączasz flagą w sekcji KONFIGURACJA. Domyślnie DRY_RUN = True:
skrypt tylko pokazuje, co by zrobił - nic nie zmienia na serwerze.

Instalacja:
    pip install "tableauserverclient>=0.34"

Uruchomienie (sekret tokenu i hasło bazy podajemy przez zmienne środowiskowe, NIE w kodzie):
    export TABLEAU_PAT_SECRET='...sekret tokenu...'
    export DB_PASSWORD='...nowe hasło do bazy...'      # tylko gdy UPDATE_DATASOURCE_CREDENTIALS
    python server_changes.py
"""

import os
import sys

import requests
import tableauserverclient as TSC

# =============================================================================
# KONFIGURACJA - uzupełnij przed uruchomieniem
# =============================================================================

# Adres serwera, BEZ ścieżki /#/site/...
#   Tableau Server: "https://tableau.firma.pl"
#   Tableau Cloud:  "https://10ax.online.tableau.com" (prefiks pod-a z adresu w przeglądarce)
SERVER_URL = "https://tableau.firma.pl"

# Content URL site'u - fragment adresu po "/#/site/", np. dla
# https://10ax.online.tableau.com/#/site/mojafirma/home  ->  "mojafirma".
# Site domyślny ("Default") na Tableau Server to pusty string "".
SITE_CONTENT_URL = ""

# Personal Access Token: My Account Settings -> Personal Access Tokens -> Create new token.
# Nazwa tokenu może być w kodzie; SEKRET czytamy ze zmiennej środowiskowej.
TOKEN_NAME = "automatyzacja-python"
TOKEN_SECRET_ENV = "TABLEAU_PAT_SECRET"

# Weryfikacja certyfikatu TLS. True = domyślne CA systemu/certifi.
# Dla firmowego CA podaj ścieżkę do pliku .pem, np. "/etc/ssl/certs/firma-ca.pem".
# Nie ustawiaj False na produkcji.
SSL_VERIFY = True

# Tryb próbny: True = tylko wypisz planowane zmiany, nic nie zapisuj na serwerze.
DRY_RUN = True

# --- Operacja 1: poświadczenia opublikowanego źródła danych -------------------
UPDATE_DATASOURCE_CREDENTIALS = True
# Wskaż źródło po LUID (najpewniejsze) ALBO po nazwie + projekcie (gdy LUID = "").
DATASOURCE_LUID = ""
DATASOURCE_NAME = "Sprzedaz - PROD"
DATASOURCE_PROJECT = "Finanse"
NEW_DB_USERNAME = "tableau_reader"
NEW_DB_PASSWORD_ENV = "DB_PASSWORD"
# Zmieniaj tylko połączenia do tego serwera bazy (np. gdy źródło ma kilka połączeń).
# Pusty string = wszystkie połączenia źródła.
ONLY_CONNECTIONS_TO_SERVER = ""

# --- Operacja 2: zmiana właściciela skoroszytu --------------------------------
CHANGE_WORKBOOK_OWNER = True
WORKBOOK_LUID = ""
WORKBOOK_NAME = "Raport sprzedazy"
WORKBOOK_PROJECT = "Finanse"
# Nazwa użytkownika (login) nowego właściciela - na Tableau Cloud zwykle e-mail.
NEW_OWNER_USERNAME = "jan.kowalski@firma.pl"

# --- Operacja 3: tagi skoroszytu (ten sam skoroszyt co w operacji 2) ----------
ADD_WORKBOOK_TAGS = True
TAGS_TO_ADD = ["produkcja", "zweryfikowany"]

# =============================================================================
# JAK ZNALEŹĆ LUID ZASOBU
# =============================================================================
# LUID to globalny identyfikator zasobu w formacie UUID, np.
# "9d6b7e3a-1c2f-4a5b-8e9d-0123456789ab". Nie myl go z numerem z adresu URL!
#
#  * Adres w przeglądarce typu .../#/site/x/workbooks/12345 zawiera "repository id"
#    (liczbę), a NIE LUID - REST API go nie przyjmie.
#  * Najprościej: uruchom ten skrypt z LUID = "" i podaną nazwą + projektem.
#    Funkcje find_* wypiszą LUID znalezionego zasobu - skopiuj go do konfiguracji.
#  * Wylistowanie wszystkiego (np. w konsoli Pythona po zalogowaniu):
#        for wb in TSC.Pager(server.workbooks):
#            print(wb.id, wb.project_name, wb.name)
#        for ds in TSC.Pager(server.datasources):
#            print(ds.id, ds.project_name, ds.name)
#        for u in TSC.Pager(server.users):
#            print(u.id, u.name, u.site_role)
#  * Metadata API (GraphQL, /metadata/graphiql) - pole "luid" na obiektach
#    Workbook / PublishedDatasource.
#  * Tableau Server: repozytorium PostgreSQL (workgroup), kolumna "luid"
#    w tabelach workbooks / datasources / users.
#  * Nazwy NIE są unikalne w obrębie site'u (ta sama nazwa może być w wielu
#    projektach), dlatego wyszukiwanie zawsze zawęża też po projekcie.
# =============================================================================


class ConfigError(Exception):
    """Błąd w konfiguracji lub danych wejściowych - przerywa skrypt z czytelnym komunikatem."""


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ConfigError(f"Brak zmiennej środowiskowej {name}. Ustaw ją: export {name}='...'")
    return value


def _pick_one(items, kind: str, name: str, project: str):
    """Zawęża wyniki do projektu i pilnuje, by był dokładnie jeden."""
    matches = [i for i in items if not project or i.project_name == project]
    if not matches:
        raise ConfigError(f"Nie znaleziono: {kind} '{name}' w projekcie '{project}'.")
    if len(matches) > 1:
        listing = "\n".join(f"   {m.id}  projekt={m.project_name}" for m in matches)
        raise ConfigError(
            f"Znaleziono {len(matches)} zasoby {kind} '{name}' - podaj LUID wprost:\n{listing}"
        )
    item = matches[0]
    print(f"   Znaleziono {kind}: '{item.name}' (projekt '{item.project_name}'), LUID = {item.id}")
    return item


def find_workbook(server: TSC.Server, luid: str, name: str, project: str) -> TSC.WorkbookItem:
    if luid:
        return server.workbooks.get_by_id(luid)
    return _pick_one(server.workbooks.filter(name=name), "skoroszyt", name, project)


def find_datasource(server: TSC.Server, luid: str, name: str, project: str) -> TSC.DatasourceItem:
    if luid:
        return server.datasources.get_by_id(luid)
    return _pick_one(server.datasources.filter(name=name), "źródło danych", name, project)


def find_user(server: TSC.Server, username: str) -> TSC.UserItem:
    users = list(server.users.filter(name=username))
    if not users:
        raise ConfigError(f"Nie znaleziono użytkownika '{username}' na tym site.")
    user = users[0]
    print(f"   Znaleziono użytkownika: '{user.name}', LUID = {user.id}, rola = {user.site_role}")
    return user


# -----------------------------------------------------------------------------
# Operacje
# -----------------------------------------------------------------------------

def update_datasource_credentials(server: TSC.Server) -> None:
    print("\n[1] Aktualizacja poświadczeń źródła danych")
    password = require_env(NEW_DB_PASSWORD_ENV)
    datasource = find_datasource(server, DATASOURCE_LUID, DATASOURCE_NAME, DATASOURCE_PROJECT)

    server.datasources.populate_connections(datasource)
    connections = [
        c for c in datasource.connections
        if not ONLY_CONNECTIONS_TO_SERVER or c.server_address == ONLY_CONNECTIONS_TO_SERVER
    ]
    if not connections:
        raise ConfigError(f"Źródło '{datasource.name}' nie ma pasujących połączeń.")

    for conn in connections:
        print(f"   Połączenie {conn.id}: {conn.connection_type} @ {conn.server_address}:{conn.server_port}"
              f", user '{conn.username}' -> '{NEW_DB_USERNAME}'")
        if DRY_RUN:
            continue
        conn.username = NEW_DB_USERNAME
        conn.password = password
        conn.embed_password = True  # hasło zapisane w źródle - odświeżenia ekstraktów działają bez pytania
        server.datasources.update_connection(datasource, conn)
        print("      zaktualizowano")


def change_workbook_owner(server: TSC.Server, workbook: TSC.WorkbookItem) -> None:
    print("\n[2] Zmiana właściciela skoroszytu")
    new_owner = find_user(server, NEW_OWNER_USERNAME)
    if workbook.owner_id == new_owner.id:
        print("   Użytkownik jest już właścicielem - pomijam.")
        return
    print(f"   Właściciel: {workbook.owner_id} -> {new_owner.id} ({new_owner.name})")
    if DRY_RUN:
        return
    workbook.owner_id = new_owner.id
    server.workbooks.update(workbook)
    print("   zaktualizowano")


def add_workbook_tags(server: TSC.Server, workbook: TSC.WorkbookItem) -> None:
    print("\n[3] Dodawanie tagów do skoroszytu")
    missing = [t for t in TAGS_TO_ADD if t not in workbook.tags]
    print(f"   Obecne tagi: {sorted(workbook.tags) or '-'}; do dodania: {missing or '-'}")
    if DRY_RUN or not missing:
        return
    result = server.workbooks.add_tags(workbook, missing)
    print(f"   Tagi po zmianie: {sorted(result)}")


# -----------------------------------------------------------------------------
# Główna procedura
# -----------------------------------------------------------------------------

def main() -> int:
    try:
        token_secret = require_env(TOKEN_SECRET_ENV)

        server = TSC.Server(SERVER_URL, use_server_version=True,
                            http_options={"verify": SSL_VERIFY, "timeout": 60})
        auth = TSC.PersonalAccessTokenAuth(TOKEN_NAME, token_secret, site_id=SITE_CONTENT_URL)

        print(f"Łączenie z {SERVER_URL} (site: '{SITE_CONTENT_URL or 'Default'}')"
              f"{' [DRY RUN - bez zapisu]' if DRY_RUN else ''}")

        # Context manager gwarantuje wylogowanie (sign_out) także przy wyjątku.
        with server.auth.sign_in(auth):
            print(f"Zalogowano. Wersja REST API: {server.version}")

            if UPDATE_DATASOURCE_CREDENTIALS:
                update_datasource_credentials(server)

            if CHANGE_WORKBOOK_OWNER or ADD_WORKBOOK_TAGS:
                print("\nSzukam skoroszytu")
                workbook = find_workbook(server, WORKBOOK_LUID, WORKBOOK_NAME, WORKBOOK_PROJECT)
                if CHANGE_WORKBOOK_OWNER:
                    change_workbook_owner(server, workbook)
                if ADD_WORKBOOK_TAGS:
                    add_workbook_tags(server, workbook)

        print("\nGotowe." + (" To był DRY RUN - ustaw DRY_RUN = False, aby zapisać zmiany." if DRY_RUN else ""))
        return 0

    except ConfigError as e:
        print(f"\nBŁĄD KONFIGURACJI: {e}", file=sys.stderr)
        return 2
    except TSC.FailedSignInError as e:
        # Najczęstsze przyczyny: zła nazwa/sekret tokenu, token wygasł (nieużywany 15 dni
        # lub minął rok), zły SITE_CONTENT_URL, PAT wyłączone przez administratora.
        print(f"\nLOGOWANIE ODRZUCONE: {e}\n"
              "Sprawdź TOKEN_NAME, sekret tokenu, SITE_CONTENT_URL oraz czy token nie wygasł.",
              file=sys.stderr)
        return 3
    except TSC.ServerResponseError as e:
        # e.code to kod błędu Tableau, np. 403xxx = brak uprawnień, 404xxx = nie znaleziono zasobu
        # (np. błędny LUID), 409xxx = konflikt.
        print(f"\nSERWER ODRZUCIŁ ŻĄDANIE: kod {e.code} - {e.summary}: {e.detail}", file=sys.stderr)
        if str(e.code).startswith("403"):
            print("Brak uprawnień - właściciel tokenu musi być właścicielem zasobu, "
                  "liderem projektu lub administratorem site'u.", file=sys.stderr)
        elif str(e.code).startswith("404"):
            print("Zasób nie istnieje - sprawdź LUID (to UUID, nie numer z adresu URL).", file=sys.stderr)
        return 4
    except requests.exceptions.SSLError as e:
        print(f"\nBŁĄD CERTYFIKATU TLS: {e}\n"
              "Jeśli serwer używa firmowego CA, ustaw SSL_VERIFY na ścieżkę do pliku .pem.",
              file=sys.stderr)
        return 5
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
        print(f"\nBRAK POŁĄCZENIA Z SERWEREM: {e}\n"
              "Sprawdź SERVER_URL, VPN/proxy i czy serwer działa.", file=sys.stderr)
        return 5


if __name__ == "__main__":
    sys.exit(main())
