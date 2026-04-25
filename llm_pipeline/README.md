# ==============================================================================
# LLM Book Rewriting Pipeline - README
# 
# System przetwarzania książek przy użyciu Qwen-Coder i Qwen3.6-35B-A3B
# Przeznaczony dla Raspberry Pi 4 (optymalizacja CPU/RAM)
# ==============================================================================

## 📁 STRUKTURA PROJEKTU

```
llm_pipeline/
├── pipeline.sh      # Główny skrypt przetwarzania
├── tui.sh           # Interfejs tekstowy (Terminal UI)
├── start.sh         # Uruchamianie w tle
├── stop.sh          # Bezpieczne zatrzymywanie
├── status.sh        # Status systemu
├── webui.sh         # Interfejs webowy (port 8080)
├── install.sh       # Instalacja zależności
├── README.md        # Ten plik
├── input/           # Tu wrzucaj książki do przetworzenia
├── finish/          # Tu pojawią się gotowe wyniki
├── chunk/           # Tymczasowe fragmenty (chunki)
├── temp/            # Pliki tymczasowe konwersji
└── logs/            # Logi systemu
```

## 🚀 SZYBKI START

### 1. Instalacja zależności

```bash
cd /workspace/llm_pipeline
./install.sh
```

### 2. Uruchomienie serwerów LLM (w osobnych terminalach)

```bash
# Terminal 1: Qwen3.6-35B-A3B (główny model piszący)
vllm serve Qwen/Qwen3.6-35B-A3B --port 8000 --host 0.0.0.0

# Terminal 2: Qwen-Coder (analiza i składanie)
vllm serve Qwen/Qwen-Coder --port 8001 --host 0.0.0.0
```

### 3. Uruchomienie pipeline

```bash
# Opcja A: Interfejs tekstowy (TUI)
./tui.sh

# Opcja B: Tryb automatyczny (w tle)
./start.sh

# Opcja C: Pojedynczy plik
./pipeline.sh process /ścieżka/do/ksiazki.pdf
```

### 4. Web UI (opcjonalnie)

```bash
./webui.sh
# Dostępne pod: http://localhost:8080
```

## 📥 OBSŁUGIWANE FORMATY

System automatycznie konwertuje następujące formaty do TXT:
- **Tekstowe**: `.txt`, `.md`
- **Dokumenty**: `.doc`, `.docx`, `.odt`
- **Arkusze**: `.xls`, `.xlsx`, `.ods`
- **Prezentacje**: `.ppt`, `.pptx`
- **PDF**: `.pdf`

## 🔄 ARCHITEKTURA PIPELINE

```
📥 input/ksiazka.pdf
    ↓
[1] KONWERSJA → temp/ksiazka.txt
    ↓
[2] CHUNKING → chunk/ksiazka/part_0001.txt, part_0002.txt, ...
    ↓
[3] QWEN-CODER (port 8001): Analiza stylu i struktury
    ↓
[4] QWEN3.6-35B (port 8000): Pisanie nowej treści ← GŁÓWNY MODEL
    ↓
[5] QWEN-CODER (port 8001): Scalanie i wygładzanie
    ↓
📤 finish/ksiazka_rewritten.txt
```

## ⚙️ KONFIGURACJA

### Zmienne środowiskowe

Możesz nadpisać domyślne ustawienia:

```bash
export LLM_35B_URL="http://localhost:8000/v1"
export LLM_CODER_URL="http://localhost:8001/v1"
export CHUNK_SIZE=1500          # Znaków na fragment
export COOLDOWN_TIME=120        # Sekund przerwy między chunkami
export MAX_RETRIES=3            # Liczba ponowień przy błędzie
```

### Plik konfiguracyjny

Edytuj `config/settings.conf`:

```bash
LLM_35B_URL=http://localhost:8000/v1
LLM_CODER_URL=http://localhost:8001/v1
CHUNK_SIZE=1500
COOLDOWN_TIME=120
```

## 🎮 INTERFEJS TEKSTOWY (TUI)

Uruchom interaktywny interfejs:

```bash
./tui.sh
```

**Dostępne opcje:**
1. Start pipeline (w tle)
2. Stop pipeline
3. Status systemu
4. Przetwórz pojedynczy plik
5. Podgląd logów na żywo
6. Lista plików w input/
7. Lista plików w finish/
8. Wyczyść pliki tymczasowe
9. Test połączenia z API
0. Wyjście

**Skróty komend:**
```bash
./tui.sh status    # Pokaż status
./tui.sh logs      # Podgląd logów
./tui.sh list      # Lista plików
./tui.sh help      # Pomoc
```

## 🔧 KOMENDY PIPELINE

```bash
# Pełna lista komend
./pipeline.sh --help

# Uruchom przetwarzanie wszystkich plików z input/
./pipeline.sh run

# Przetwórz pojedynczy plik
./pipeline.sh process moja_ksiazka.pdf

# Konwertuj plik do TXT
./pipeline.sh convert dokument.doc

# Podziel plik na chunki
./pipeline.sh chunk plik.txt

# Test połączenia z API
./pipeline.sh test-api

# Status procesu
./pipeline.sh status

# Zatrzymaj pipeline
./pipeline.sh stop

# Wyczyść pliki tymczasowe
./pipeline.sh clean
```

## ⏱️ OPTYMALIZACJA DLA RASPBERRY PI 4

System jest zoptymalizowany pod kątem pracy na słabszym sprzęcie:

| Parametr | Wartość | Opis |
|----------|---------|------|
| CHUNK_SIZE | 1500 | Małe fragmenty (ochrona RAM) |
| COOLDOWN_TIME | 120s | Przerwa między chunkami (ochrona CPU) |
| REQUEST_TIMEOUT | 600s | Timeout na żądanie API |
| CHECK_INTERVAL | 60s | Częstotliwość sprawdzania nowych plików |

**Czas przetwarzania:**
- Krótka książka (50 stron): ~30-60 minut
- Średnia książka (200 stron): ~4-8 godzin
- Duża książka (500+ stron): ~12-24 godziny

System może działać **ciągłe przez kilka dni**.

## 📊 MONITOROWANIE

### Logi na żywo

```bash
tail -f logs/pipeline.log
```

### Status systemu

```bash
./status.sh
# lub
./pipeline.sh status
```

### Web UI

```bash
./webui.sh
# Otwórz przeglądarkę: http://localhost:8080
```

## 🛠️ ROZWIĄZYWANIE PROBLEMÓW

### Problem: "Brak narzędzia do konwersji"

**Rozwiązanie:** Zainstaluj brakujące pakiety:
```bash
sudo apt-get update
sudo apt-get install -y pandoc poppler-utils antiword gnumeric
```

### Problem: "Timeout połączenia z API"

**Rozwiązanie:** Sprawdź czy serwery LLM działają:
```bash
curl http://localhost:8000/v1/models
curl http://localhost:8001/v1/models
```

### Problem: "Przegrzewanie Raspberry Pi"

**Rozwiązanie:** Zwiększ czas cooldown:
```bash
export COOLDOWN_TIME=300  # 5 minut przerwy
```

### Problem: "Za mało pamięci RAM"

**Rozwiązanie:** Zmniejsz rozmiar chunka:
```bash
export CHUNK_SIZE=1000
```

## 📝 PRZYKŁAD UŻYCIA

```bash
# 1. Skopiuj książkę do input/
cp ~/Downloads/moja_ksiazka.pdf /workspace/llm_pipeline/input/

# 2. Uruchom pipeline
./start.sh

# 3. Monitoruj postępy
tail -f logs/pipeline.log

# 4. Sprawdź wynik
ls -lh finish/

# 5. Otwórz przetworzoną książkę
cat finish/moja_ksiazka_rewritten.txt
```

## 🔐 BEZPIECZEŃSTWO

- Oryginalne pliki są archiwizowane w `logs/processed_*`
- Chunki są usuwane po zakończeniu przetwarzania
- System działa lokalnie - żadne dane nie opuszczają urządzenia

## 📄 LICENCJA

Projekt na licencji MIT. Używaj odpowiedzialnie.

## 🤝 WSPARCIE

W przypadku problemów sprawdź logi:
```bash
./tui.sh logs
```

Lub uruchom test API:
```bash
./pipeline.sh test-api
```
