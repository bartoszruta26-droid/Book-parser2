# LLM Pipeline - Qwen Agent + Qwen-Coder + Qwen3.6-35B-A3B

System przetwarzania ksiazek w 100% Bash (bez Pythona). Raspberry Pi 4 optimized.

## Formaty: .txt .md .doc .docx .xls .xlsx .odt .ods .ppt .pptx .pdf

## Architektura Pipeline

```
input/book.pdf -> Konwersja TXT -> Chunking -> 
Qwen-Coder (analiza) -> Qwen3.6 (pisanie) -> Qwen-Coder (wygladzanie) -> 
finish/book_rewritten.txt
```

## Instalacja

```bash
./install.sh
```

## Uruchomienie vLLM

```bash
vllm serve Qwen/Qwen3.6-35B-A3B --port 8000
vllm serve Qwen/Qwen-Coder --port 8001
```

## Start Pipeline

```bash
./start.sh        # W tle
./status.sh       # Status
./stop.sh         # Stop
./webui.sh        # Web UI port 8080
```

## Pojedynczy plik

```bash
./pipeline.sh process book.pdf
```

## Konfiguracja

```bash
export CHUNK_SIZE=2000        # znakow/chunk
export COOLDOWN_TIME=180      # sekund przerwy
export PROCESSING_TIMEOUT=7200 # 2h na chunk
```

## Struktura

- input/ - wrzuc ksiazki
- finish/ - gotowe wyniki
- chunk/ - tymczasowe chunki
- logs/ - logi i archiwum
