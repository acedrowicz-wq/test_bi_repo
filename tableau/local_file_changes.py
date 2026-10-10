#!/usr/bin/env python3
"""
CZĘŚĆ 2 - zmiany w lokalnych plikach Tableau (.twb / .twbx, a także .tds / .tdsx).

Pliki .twb/.tds to zwykły XML. Skrypt podmienia szczegóły połączeń do bazy danych
(serwer, port, nazwa bazy, użytkownik) według mapowania CONNECTION_MAPPING, np.
serwer testowy -> produkcyjny, i zapisuje wynik.

Pliki .twbx/.tdsx to archiwa ZIP zawierające .twb/.tds + dane (ekstrakty .hyper,
pliki CSV/Excel, obrazki). Skrypt: rozpakowuje archiwum w pamięci -> modyfikuje XML
-> pakuje ponownie wszystkie pozostałe pliki bez zmian.

Używamy wyłącznie biblioteki standardowej Pythona (xml.etree.ElementTree, zipfile) -
nie trzeba nic instalować. Biblioteka `tableaudocumentapi` nie jest rozwijana od 2022 r.,
nie buduje się na nowszych Pythonach (np. 3.13) i nie widzi wszystkich połączeń
w nowym formacie "federated" - patrz README.md.

Uruchomienie:
    python local_file_changes.py                    # plik z FILE_PATH
    python local_file_changes.py raport.twbx        # albo ścieżka z linii poleceń
"""

import io
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

# =============================================================================
# KONFIGURACJA - uzupełnij przed uruchomieniem
# =============================================================================

# Plik do zmiany: .twb, .twbx, .tds lub .tdsx.
FILE_PATH = "raporty/Raport sprzedazy.twbx"

# Gdzie zapisać wynik. "" = nadpisz plik źródłowy (kopia zapasowa trafi obok jako *.bak).
OUTPUT_PATH = ""

# Mapowanie: aktualny serwer -> nowe wartości atrybutów połączenia.
# Klucz to dokładna wartość atrybutu server= w pliku (porównanie bez względu na wielkość liter).
# W słowniku wartości podaj tylko to, co chcesz zmienić. Dostępne atrybuty:
#   "server", "port", "dbname", "username", "schema", "warehouse" (Snowflake), "service" (Oracle)
CONNECTION_MAPPING = {
    "test-db.firma.local": {
        "server": "prod-db.firma.local",
        "dbname": "sprzedaz_prod",
        "username": "tableau_reader",
    },
    # "test-dwh.firma.local": {"server": "prod-dwh.firma.local", "port": "5433"},
}

# True = tylko wypisz znalezione połączenia i planowane zmiany, nic nie zapisuj.
DRY_RUN = False

# Kopia zapasowa oryginału przed nadpisaniem (tylko gdy OUTPUT_PATH = "").
MAKE_BACKUP = True

# =============================================================================

SUPPORTED = {".twb", ".tds", ".twbx", ".tdsx"}
PACKAGED = {".twbx": ".twb", ".tdsx": ".tds"}


class TableauFileError(Exception):
    """Błąd pliku wejściowego lub konfiguracji - przerywa skrypt z czytelnym komunikatem."""


# -----------------------------------------------------------------------------
# XML
# -----------------------------------------------------------------------------

def register_namespaces(xml_bytes: bytes) -> None:
    """Rejestruje prefiksy przestrzeni nazw z pliku (np. xmlns:user=...).

    Bez tego ElementTree zapisze je jako ns0:, ns1:..., a Tableau może takiego pliku nie otworzyć.
    """
    for _, (prefix, uri) in ET.iterparse(io.BytesIO(xml_bytes), events=("start-ns",)):
        ET.register_namespace(prefix, uri)


def update_connections(xml_bytes: bytes, source_name: str) -> tuple[bytes, int]:
    """Zwraca (nowy XML, liczba zmienionych połączeń)."""
    try:
        register_namespaces(xml_bytes)
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as e:
        raise TableauFileError(f"{source_name}: niepoprawny XML ({e}). Czy to na pewno plik Tableau?")

    mapping = {k.lower(): v for k, v in CONNECTION_MAPPING.items()}
    changed = 0
    seen = 0

    # Mapa rodziców, żeby móc poprawić też caption elementu <named-connection>.
    parents = {child: parent for parent in root.iter() for child in parent}

    # W nowszych plikach połączenia do bazy są zagnieżdżone:
    #   <datasource><connection class='federated'><named-connections>
    #     <named-connection caption='test-db...'><connection class='postgres' server='test-db...' .../>
    # Przechodzimy po WSZYSTKICH <connection> w pliku i bierzemy te z atrybutem server=.
    for conn in root.iter("connection"):
        server = conn.get("server")
        if not server:
            continue  # np. połączenie 'federated', 'hyper' (ekstrakt) lub plikowe
        seen += 1
        new_values = mapping.get(server.lower())
        label = f"{conn.get('class')} @ {server} / db={conn.get('dbname', '-')}"
        if new_values is None:
            print(f"   bez zmian:  {label}")
            continue

        diffs = {a: (conn.get(a), v) for a, v in new_values.items() if conn.get(a) != v}
        print(f"   ZMIANA:     {label}")
        for attr, (old, new) in diffs.items():
            print(f"               {attr}: {old!r} -> {new!r}")
            conn.set(attr, new)

        parent = parents.get(conn)
        new_server = new_values.get("server")
        if (new_server and parent is not None and parent.tag == "named-connection"
                and parent.get("caption", "").lower() == server.lower()):
            parent.set("caption", new_server)  # nazwa połączenia widoczna w Tableau Desktop

        changed += 1 if diffs else 0

    if seen == 0:
        print("   Nie znaleziono żadnych połączeń z atrybutem server= (np. tylko ekstrakty lub pliki).")

    # Tableau zapisuje nagłówek z apostrofami; ElementTree z cudzysłowami - oba są poprawne.
    out = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return out, changed


# -----------------------------------------------------------------------------
# Pliki
# -----------------------------------------------------------------------------

def process_plain(src: Path) -> tuple[bytes, int]:
    print(f"Plik XML: {src.name}")
    return update_connections(src.read_bytes(), src.name)


def process_packaged(src: Path) -> tuple[bytes, int]:
    """.twbx/.tdsx: rozpakuj -> zmień .twb/.tds -> spakuj ponownie (reszta plików 1:1)."""
    inner_ext = PACKAGED[src.suffix.lower()]
    try:
        zin = zipfile.ZipFile(src)
    except zipfile.BadZipFile:
        raise TableauFileError(f"{src.name} nie jest poprawnym archiwum ZIP - plik uszkodzony?")

    with zin:
        # Główny dokument leży w katalogu głównym archiwum (nie w Data/ czy Image/).
        docs = [i for i in zin.infolist()
                if "/" not in i.filename and i.filename.lower().endswith(inner_ext)]
        if len(docs) != 1:
            raise TableauFileError(
                f"{src.name}: oczekiwano jednego pliku {inner_ext} w archiwum, znaleziono {len(docs)}.")
        doc = docs[0]
        print(f"Archiwum: {src.name} -> dokument w środku: {doc.filename}")

        new_xml, changed = update_connections(zin.read(doc), doc.filename)

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zout:
            for item in zin.infolist():
                data = new_xml if item.filename == doc.filename else zin.read(item)
                # Zachowujemy oryginalne metadane wpisu (data, kompresja, atrybuty).
                zout.writestr(item, data, compress_type=item.compress_type)
    return buf.getvalue(), changed


def write_atomically(target: Path, data: bytes) -> None:
    """Zapis do pliku tymczasowego i podmiana - przerwany zapis nie zniszczy oryginału."""
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=f".{target.name}.", delete=False) as tmp:
        tmp.write(data)
        tmp_path = Path(tmp.name)
    tmp_path.replace(target)


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else FILE_PATH).expanduser()
    try:
        if not src.is_file():
            raise TableauFileError(f"Plik nie istnieje: {src.resolve()}")
        ext = src.suffix.lower()
        if ext not in SUPPORTED:
            raise TableauFileError(f"Nieobsługiwane rozszerzenie '{ext}'. Obsługiwane: {sorted(SUPPORTED)}")
        if not CONNECTION_MAPPING:
            raise TableauFileError("CONNECTION_MAPPING jest puste - nie ma czego zmieniać.")

        data, changed = process_packaged(src) if ext in PACKAGED else process_plain(src)

        if DRY_RUN:
            print(f"\nDRY RUN: zmieniłbym {changed} połączeń. Nic nie zapisano.")
            return 0
        if changed == 0:
            print("\nBrak połączeń do zmiany - plik pozostaje bez zmian.")
            return 0

        target = Path(OUTPUT_PATH).expanduser() if OUTPUT_PATH else src
        if target.suffix.lower() != ext:
            raise TableauFileError(f"OUTPUT_PATH musi mieć to samo rozszerzenie co plik źródłowy ({ext}).")
        if target == src and MAKE_BACKUP:
            backup = src.with_name(src.name + ".bak")
            shutil.copy2(src, backup)
            print(f"\nKopia zapasowa: {backup}")

        target.parent.mkdir(parents=True, exist_ok=True)
        write_atomically(target, data)
        print(f"Zapisano {changed} zmienionych połączeń do: {target}")
        print("Otwórz plik w Tableau Desktop i sprawdź połączenie (hasło trzeba będzie podać przy logowaniu).")
        return 0

    except TableauFileError as e:
        print(f"\nBŁĄD: {e}", file=sys.stderr)
        return 2
    except PermissionError as e:
        print(f"\nBRAK UPRAWNIEŃ DO PLIKU: {e}\n"
              "Zamknij plik w Tableau Desktop (blokuje go na Windows) i sprawdź uprawnienia.",
              file=sys.stderr)
        return 3
    except OSError as e:
        print(f"\nBŁĄD ODCZYTU/ZAPISU: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
