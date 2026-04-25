#!/bin/bash
# ==============================================================================
# LLM Book Rewriting Pipeline - Bash Edition
# Przeznaczenie: Raspberry Pi 4 (optymalizacja pamięci i CPU)
# Architektura: Input -> Convert -> Chunk -> Coder(Analiza) -> 35B(Pisanie) -> Coder(Scalanie) -> Finish
# 
# URUCHOMIENIE Z DOWOLNEGO KATALOGU:
#   /workspace/llm_pipeline/pipeline.sh run
#   lub
#   cd /workspace/llm_pipeline && ./pipeline.sh run
#
# OBSŁUGIWANE FORMATY: .txt .md .doc .docx .xls .xlsx .odt .ods .ppt .pptx .pdf
# ==============================================================================

set -euo pipefail

# --- KONFIGURACJA ŚCIEŻEK (Działa z każdego katalogu) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIR_INPUT="${SCRIPT_DIR}/input"
DIR_FINISH="${SCRIPT_DIR}/finish"
DIR_CHUNK="${SCRIPT_DIR}/chunk"
DIR_LOGS="${SCRIPT_DIR}/logs"
DIR_TMP="${SCRIPT_DIR}/temp"
FILE_CONFIG="${SCRIPT_DIR}/config/settings.conf"
FILE_LOCK="${DIR_LOGS}/pipeline.lock"
FILE_PID="${DIR_LOGS}/pipeline.pid"

# --- KONFIGURACJA MODELI I SIECI ---
LLM_35B_URL="${LLM_35B_URL:-http://localhost:8000/v1}"
LLM_CODER_URL="${LLM_CODER_URL:-http://localhost:8001/v1}"
MODEL_35B="${MODEL_35B:-Qwen/Qwen3.6-35B-A3B}"
MODEL_CODER="${MODEL_CODER:-Qwen/Qwen-Coder}"

# --- PARAMETRY PRZETWARZANIA (Optymalizacja dla RPi4) ---
CHUNK_SIZE="${CHUNK_SIZE:-1500}"
CHUNK_OVERLAP="${CHUNK_OVERLAP:-200}"
COOLDOWN_TIME="${COOLDOWN_TIME:-120}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-600}"
MAX_RETRIES="${MAX_RETRIES:-3}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

# --- NARZĘDZIA KONWERSJI ---
SUPPORTED_EXTS=("txt" "md" "doc" "docx" "odt" "pdf" "xls" "xlsx" "ods" "ppt" "pptx")

# --- LOGOWANIE ---
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "${DIR_LOGS}/pipeline.log"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- INICJALIZACJA ---
init_dirs() {
    mkdir -p "$DIR_INPUT" "$DIR_FINISH" "$DIR_CHUNK" "$DIR_LOGS" "$DIR_TMP" "${SCRIPT_DIR}/config"
    touch "${DIR_LOGS}/pipeline.log" 2>/dev/null || true
    log_info "Zainicjowano katalogi robocze."
}

load_config() {
    if [[ -f "$FILE_CONFIG" ]]; then
        source "$FILE_CONFIG"
        log_info "Wczytano konfigurację z $FILE_CONFIG"
    fi
}

# --- KONWERSJA DOKUMENTÓW DO TXT ---
convert_to_txt() {
    local input_file="$1"
    local output_file="$2"
    local filename
    filename=$(basename "$input_file")
    local extension="${filename##*.}"
    
    log_info "Konwersja $filename (${extension}) do TXT"
    
    case "$extension" in
        txt|md)
            cat "$input_file" > "$output_file"
            ;;
        doc)
            if command -v antiword &>/dev/null; then
                antiword -t "$input_file" > "$output_file" 2>/dev/null || true
            fi
            if [[ ! -s "$output_file" ]] && command -v pandoc &>/dev/null; then
                pandoc -f doc -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            ;;
        docx)
            if command -v pandoc &>/dev/null; then
                pandoc -f docx -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            if [[ ! -s "$output_file" ]]; then
                unzip -p "$input_file" word/document.xml 2>/dev/null | sed -e 's/<[^>]*>//g' > "$output_file" || true
            fi
            ;;
        pdf)
            if command -v pdftotext &>/dev/null; then
                pdftotext -layout "$input_file" "$output_file" 2>/dev/null || true
            elif command -v pandoc &>/dev/null; then
                pandoc -f pdf -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            ;;
        odt)
            if command -v pandoc &>/dev/null; then
                pandoc -f odt -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            if [[ ! -s "$output_file" ]]; then
                unzip -p "$input_file" content.xml 2>/dev/null | sed -e 's/<[^>]*>//g' > "$output_file" || true
            fi
            ;;
        xls|xlsx)
            if command -v ssconvert &>/dev/null; then
                ssconvert "$input_file" "${DIR_TMP}/temp.csv" 2>/dev/null && cat "${DIR_TMP}/temp.csv" > "$output_file"
            elif command -v pandoc &>/dev/null; then
                pandoc -f "${extension}" -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            ;;
        ods)
            if command -v ssconvert &>/dev/null; then
                ssconvert "$input_file" "${DIR_TMP}/temp.csv" 2>/dev/null && cat "${DIR_TMP}/temp.csv" > "$output_file"
            elif command -v pandoc &>/dev/null; then
                pandoc -f ods -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            ;;
        ppt|pptx)
            if command -v pandoc &>/dev/null; then
                pandoc -f "${extension}" -t plain "$input_file" -o "$output_file" 2>/dev/null || true
            fi
            ;;
        *)
            log_error "Nieobslugiwany format: $extension"
            return 1
            ;;
    esac
    
    if [[ ! -s "$output_file" ]]; then
        log_error "Konwersja nieudana dla $filename"
        return 1
    fi
    
    # Czyszczenie tekstu
    sed -i 's/[[:space:]]\+/ /g' "$output_file"
    sed -i '/^$/d' "$output_file" 2>/dev/null || true
    
    log_info "Konwersja zakonczona: $(wc -c < "$output_file") bajtow"
    return 0
}

# --- CHUNKING ---
split_into_chunks() {
    local input_file="$1"
    local book_id="$2"
    local chunk_dir="${DIR_CHUNK}/${book_id}"
    
    mkdir -p "$chunk_dir"
    
    local total_chars
    total_chars=$(wc -c < "$input_file")
    local effective_size=$((CHUNK_SIZE - OVERLAP_SIZE))
    local num_chunks=$(( (total_chars + effective_size - 1) / effective_size ))
    
    log_info "Podzial na chunki: $total_chars znakow, ~$num_chunks chunkow"
    
    local start=0
    local chunk_num=0
    
    while [[ $start -lt $total_chars ]]; do
        local end=$((start + CHUNK_SIZE))
        [[ $end -gt $total_chars ]] && end=$total_chars
        
        chunk_num=$((chunk_num + 1))
        local chunk_file="${chunk_dir}/chunk_$(printf '%04d' $chunk_num).txt"
        
        dd if="$input_file" bs=1 skip=$start count=$((end - start)) 2>/dev/null > "$chunk_file"
        
        log_info "Utworzono chunk $chunk_num"
        
        start=$((end - OVERLAP_SIZE))
        [[ $start -ge $total_chars ]] && break
        [[ $start -le $((chunk_num - 1)) ]] && break
    done
    
    echo "$chunk_num"
}

# --- KOMUNIKACJA Z LLM ---
call_llm() {
    local url="$1"
    local model="$2"
    local prompt="$3"
    local system_prompt="${4:-You are a helpful assistant.}"
    local max_tokens="${5:-4096}"
    local temperature="${6:-0.7}"
    
    local retry=0
    
    while [[ $retry -lt $MAX_RETRIES ]]; do
        log_info "Wywolanie LLM: $model (proba $((retry + 1)))"
        
        local escaped_prompt
        escaped_prompt=$(echo "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
        local escaped_system
        escaped_system=$(echo "$system_prompt" | sed 's/\\/\\\\/g; s/"/\\"/g')
        
        local response
        response=$(curl -s -w "\n%{http_code}" -X POST "$url/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"system\",\"content\":\"$escaped_system\"},{\"role\":\"user\",\"content\":\"$escaped_prompt\"}],\"max_tokens\":$max_tokens,\"temperature\":$temperature,\"stream\":false}" \
            --max-time "$PROCESSING_TIMEOUT" 2>/dev/null) || true
        
        local http_code
        http_code=$(echo "$response" | tail -1)
        local body
        body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" == "200" ]]; then
            local content
            content=$(echo "$body" | grep -o '"content"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"content"[[:space:]]*:[[:space:]]*"//;s/"$//')
            if [[ -n "$content" ]]; then
                echo "$content"
                return 0
            fi
        fi
        
        log_warn "Blad LLM: HTTP $http_code, proba $((retry + 1))"
        retry=$((retry + 1))
        sleep $((30 * retry))
    done
    
    log_error "LLM nie odpowiedzialo po $MAX_RETRIES probach"
    return 1
}

# --- PROCES PRZETWARZANIA CHUNKA ---
process_chunk() {
    local chunk_file="$1"
    local chunk_id="$2"
    local book_title="$3"
    local context_before="$4"
    local context_after="$5"
    
    local chunk_content
    chunk_content=$(cat "$chunk_file")
    
    # KROK 1: Qwen-Coder - Analiza stylu
    log_info "Chunk $chunk_id: Qwen-Coder analizuje styl..."
    local analysis_prompt="Analizuj fragment książki '$book_title'. Zidentyfikuj: 1. Styl narracji 2. Wątki i postacie 3. Strukturę akapitów. Fragment: $chunk_content"
    
    local style_analysis
    style_analysis=$(call_llm "$LLM_CODER_URL" "$MODEL_CODER" "$analysis_prompt" "Jestes ekspertem od analizy literackiej." 2048) || return 1
    
    # KROK 2: Qwen3.6 - Pisanie treści
    log_info "Chunk $chunk_id: Qwen3.6 pisze nowa tresc..."
    local rewrite_prompt="Na podstawie analizy: $style_analysis oraz oryginalnego fragmentu: $chunk_content napisz NOWA kreatywna wersje rozdzialu książki '$book_title'. Kontekst poprzedni: $context_before. Kontekst nastepny: $context_after. Napisz minimum 1000 slow w jezyku polskim."
    
    local new_content
    new_content=$(call_llm "$LLM_35B_URL" "$MODEL_35B" "$rewrite_prompt" "Jestes znanym pisarzem. Twórz wciągające treści w języku polskim." 8192 0.8) || return 1
    
    # KROK 3: Qwen-Coder - Wygladzanie
    log_info "Chunk $chunk_id: Qwen-Coder sklada i wygladza tresc..."
    local finalize_prompt="Scal i wygładź treść rozdziału: $new_content Popraw płynność przejść, sprawdź gramatykę. Odpowiedz TYLKO finalną wersją tekstu."
    
    local final_content
    final_content=$(call_llm "$LLM_CODER_URL" "$MODEL_CODER" "$finalize_prompt" "Jestes redaktorem literackim." 4096) || return 1
    
    echo "$final_content"
}

# --- PROCES PRZETWARZANIA KSIAZKI ---
process_book() {
    local input_file="$1"
    local filename
    filename=$(basename "$input_file")
    local book_id
    book_id="$(date +%Y%m%d_%H%M%S)_$(echo "$filename" | md5sum | cut -c1-8)"
    local book_title="${filename%.*}"
    
    log_info "=========================================="
    log_info "ROZPOCZECIE PRZETWARZANIA: $filename"
    log_info "Book ID: $book_id"
    log_info "=========================================="
    
    # Konwersja do TXT
    local txt_file="${DIR_TMP}/${book_id}_source.txt"
    if ! convert_to_txt "$input_file" "$txt_file"; then
        log_error "Nie udalo sie przekonwertowac $filename"
        return 1
    fi
    
    # Podzial na chunki
    local num_chunks
    num_chunks=$(split_into_chunks "$txt_file" "$book_id" 2>&1 | grep -E '^[0-9]+$' | tail -1)
    if [[ -z "$num_chunks" ]] || ! [[ "$num_chunks" =~ ^[0-9]+$ ]]; then
        num_chunks=1
    fi
    log_info "Podzielono na $num_chunks chunkow"
    
    # Przygotowanie pliku wynikowego
    local output_file="${DIR_FINISH}/${book_title}_rewritten_$(date +%Y%m%d).txt"
    : > "$output_file"
    
    # Naglowek
    cat >> "$output_file" << EOFHEADER
================================================================================
PRZETWORZONA KSIAZKA: $book_title
Zrodlo: $filename
Data przetworzenia: $(date)
Liczba chunkow: $num_chunks
Model glowny: $MODEL_35B
Model analityczny: $MODEL_CODER
================================================================================

EOFHEADER
    
    # Przetwarzanie chunkow
    local prev_context=""
    local next_context=""
    
    for ((i=1; i<=num_chunks; i++)); do
        local chunk_file="${DIR_CHUNK}/${book_id}/chunk_$(printf '%04d' $i).txt"
        
        if [[ ! -f "$chunk_file" ]]; then
            log_warn "Brak chunka $i, pomijam"
            continue
        fi
        
        log_info "Przetwarzanie chunka $i/$num_chunks"
        
        # Pobierz kontekst nastepny
        if [[ $i -lt $num_chunks ]]; then
            local next_chunk="${DIR_CHUNK}/${book_id}/chunk_$(printf '%04d' $((i+1))).txt"
            next_context=$(head -c 500 "$next_chunk" 2>/dev/null | tr '\n' ' ')
        else
            next_context=""
        fi
        
        # Przetworz chunk
        local result
        if result=$(process_chunk "$chunk_file" "$i" "$book_title" "$prev_context" "$next_context"); then
            echo "$result" >> "$output_file"
            echo "" >> "$output_file"
            echo "--- KONIEC ROZDZIALU $i ---" >> "$output_file"
            echo "" >> "$output_file"
            
            prev_context=$(tail -c 1000 "$output_file" | tr '\n' ' ')
            log_info "Chunk $i zakonczony sukcesem"
        else
            log_error "Blad przetwarzania chunka $i"
        fi
        
        # Cooldown
        if [[ $i -lt $num_chunks ]]; then
            log_info "Cooldown: $COOLDOWN_TIME sekund..."
            sleep "$COOLDOWN_TIME"
        fi
    done
    
    # Podsumowanie
    cat >> "$output_file" << EOFOOTER

================================================================================
KONIEC PRZETWORZONEJ KSIAZKI
Wygenerowano: $(date)
================================================================================
EOFOOTER
    
    # Cleanup
    rm -rf "${DIR_CHUNK}/${book_id}"
    
    log_info "=========================================="
    log_info "ZAKONCZONO: $filename"
    log_info "Wynik: $output_file"
    log_info "=========================================="
    
    return 0
}

# --- GLOWNA PETLA PIPELINE ---
run_pipeline() {
    log_info "Uruchomienie pipeline..."
    
    while true; do
        local files_processed=0
        
        shopt -s nullglob
        for ext in txt md doc docx xls xlsx odt ods ppt pptx pdf; do
            for file in "$DIR_INPUT"/*."$ext"; do
                [[ -f "$file" ]] || continue
                
                local bname
                bname=$(basename "$file")
                local marker="${file}.processing"
                
                if [[ -f "$marker" ]]; then
                    log_info "Plik $bname jest juz przetwarzany, pomijam"
                    continue
                fi
                
                touch "$marker"
                
                if process_book "$file"; then
                    mv "$file" "${DIR_LOGS}/processed_${bname}" 2>/dev/null || true
                    files_processed=$((files_processed + 1))
                else
                    log_error "Nie udalo sie przetworzyc $bname"
                fi
                
                rm -f "$marker"
                sleep 60
            done
        done
        shopt -u nullglob
        
        if [[ $files_processed -eq 0 ]]; then
            log_info "Brak nowych plikow. Sprawdzenie za $CHECK_INTERVAL sekund..."
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# --- HELP ---
show_help() {
    cat << EOF
LLM Pipeline - Pure Shell Implementation

Uzycie:
  $0 [komenda] [argumenty]

Komendy:
  start     Uruchom pipeline w tle
  stop      Zatrzymaj pipeline
  status    Pokaz status
  process   Przetworz pojedynczy plik
  convert   Konwertuj plik do TXT
  chunk     Podziel plik na chunki
  test-api  Test polaczenia z API LLM
  clean     Wyczysc pliki tymczasowe
  run       Uruchom petle przetwarzania (wewnetrzne)
  help      Pokaz ta pomoc

Przyklady:
  $0 start              # Uruchom w tle
  $0 process book.pdf   # Przetworz pojedynczy plik
  $0 convert doc.docx   # Konwertuj do TXT
  $0 chunk file.txt     # Podziel na chunki
  $0 test-api           # Test API

EOF
}

# --- MAIN ---
main() {
    init_dirs
    
    case "${1:-run}" in
        start)
            nohup "$0" run > "${DIR_LOGS}/pipeline.out" 2>&1 &
            echo $! > "${DIR_LOGS}/pipeline.pid"
            log_info "Pipeline uruchomiony w tle (PID: $(cat ${DIR_LOGS}/pipeline.pid))"
            ;;
        stop)
            if [[ -f "${DIR_LOGS}/pipeline.pid" ]]; then
                kill "$(cat ${DIR_LOGS}/pipeline.pid)" 2>/dev/null || true
                rm -f "${DIR_LOGS}/pipeline.pid"
                log_info "Pipeline zatrzymany"
            else
                log_warn "Pipeline nie jest uruchomiony"
            fi
            ;;
        status)
            if [[ -f "${DIR_LOGS}/pipeline.pid" ]] && kill -0 "$(cat ${DIR_LOGS}/pipeline.pid)" 2>/dev/null; then
                echo "Pipeline: URUCHOMIONY (PID: $(cat ${DIR_LOGS}/pipeline.pid))"
            else
                echo "Pipeline: ZATRZYMANI"
            fi
            echo ""
            echo "Pliki wejsciowe: $(find "$DIR_INPUT" -type f 2>/dev/null | wc -l)"
            echo "Pliki wyjsciowe: $(find "$DIR_FINISH" -type f -name '*.txt' 2>/dev/null | wc -l)"
            echo ""
            echo "Ostatnie logi:"
            tail -20 "${DIR_LOGS}/pipeline.log" 2>/dev/null || echo "Brak logow"
            ;;
        process)
            if [[ -n "${2:-}" ]] && [[ -f "$2" ]]; then
                process_book "$2"
            else
                echo "Uzycie: $0 process <plik>"
                exit 1
            fi
            ;;
        run)
            run_pipeline
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Nieznana komenda: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
