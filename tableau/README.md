# Automatyzacja Tableau w Pythonie

| Skrypt | Gdzie działa | Biblioteka |
|---|---|---|
| `server_changes.py` | Tableau Server / Tableau Cloud (REST API) | `tableauserverclient` (TSC) |
| `local_file_changes.py` | lokalne pliki `.twb` / `.twbx` / `.tds` / `.tdsx` | tylko biblioteka standardowa (`xml.etree`, `zipfile`) |

## Instalacja

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install "tableauserverclient>=0.34"     # albo: pip install -r requirements.txt
```

`local_file_changes.py` nie wymaga żadnych pakietów.

## Część 1 — zmiany na serwerze (`server_changes.py`)

1. Utwórz Personal Access Token: *My Account Settings → Personal Access Tokens*.
2. Uzupełnij sekcję **KONFIGURACJA** na górze pliku (`SERVER_URL`, `SITE_CONTENT_URL`,
   `TOKEN_NAME`, nazwy/LUID zasobów, flagi operacji).
3. Sekrety podaj przez zmienne środowiskowe — nie wpisuj ich do kodu ani do repozytorium:
   ```bash
   export TABLEAU_PAT_SECRET='sekret-tokenu'
   export DB_PASSWORD='nowe-haslo-do-bazy'     # tylko dla aktualizacji poświadczeń
   ```
   Windows PowerShell: `$env:TABLEAU_PAT_SECRET = 'sekret-tokenu'`.
4. Uruchom `python server_changes.py`. Domyślnie `DRY_RUN = True` — skrypt wypisze, co znalazł
   (łącznie z LUID-ami), i co by zmienił. Gdy wynik się zgadza, ustaw `DRY_RUN = False`.

Operacje: aktualizacja poświadczeń połączeń opublikowanego źródła danych, zmiana właściciela
skoroszytu, dodanie tagów. Jak znaleźć LUID — opisane w komentarzu w skrypcie
(w skrócie: to UUID, a nie numer z adresu URL; skrypt wypisuje go po wyszukaniu po nazwie).

Kody wyjścia: `2` konfiguracja, `3` logowanie odrzucone, `4` serwer odrzucił żądanie
(uprawnienia, nieistniejący zasób), `5` brak połączenia / błąd TLS.

## Część 2 — zmiany w plikach lokalnych (`local_file_changes.py`)

1. Ustaw `FILE_PATH` i `CONNECTION_MAPPING` (stary serwer → nowe `server`, `port`, `dbname`, `username`...).
2. `python local_file_changes.py` (albo `python local_file_changes.py sciezka/do/pliku.twbx`).
3. Oryginał zostaje zachowany jako `*.bak`; zapis jest atomowy (plik tymczasowy + podmiana).

Zamknij plik w Tableau Desktop przed uruchomieniem. Hasła nie są przechowywane w `.twb`,
więc po zmianie serwera Tableau poprosi o nie przy pierwszym połączeniu.

### Jak to działa dla `.twbx`

`.twbx` to archiwum ZIP: w katalogu głównym leży `.twb` (XML), a obok `Data/` (ekstrakty `.hyper`,
pliki CSV/Excel) i `Image/`. Postępowanie:

1. **Rozpakuj** — `zipfile.ZipFile(...)`, znajdź jedyny plik `.twb` w katalogu głównym archiwum.
2. **Zmodyfikuj XML** — ten sam kod co dla zwykłego `.twb`.
3. **Spakuj ponownie** — nowe archiwum ZIP z podmienionym `.twb` i wszystkimi pozostałymi
   plikami skopiowanymi bez zmian (te same nazwy ścieżek i metody kompresji).

Ręcznie: zmień rozszerzenie na `.zip`, rozpakuj, edytuj `.twb`, spakuj zawartość
(nie folder nadrzędny!) i zmień rozszerzenie z powrotem na `.twbx`.

Uwaga: jeśli źródło w `.twbx` korzysta z **ekstraktu**, dane w `Data/*.hyper` pochodzą nadal
ze starego serwera — po zmianie połączenia odśwież ekstrakt w Tableau Desktop.

### Dlaczego nie `tableaudocumentapi`?

Biblioteka nie jest rozwijana od 2022 r., `pip install tableaudocumentapi` nie buduje się na
Pythonie 3.13, a jej API nie obejmuje wszystkich połączeń w formacie *federated* (Tableau 10+).
Na starszym Pythonie można jej użyć tak:

```python
from tableaudocumentapi import Workbook

wb = Workbook("raport.twbx")
for ds in wb.datasources:
    for conn in ds.connections:
        if conn.server == "test-db.firma.local":
            conn.server = "prod-db.firma.local"
            conn.dbname = "sprzedaz_prod"
wb.save_as("raport_prod.twbx")
```
