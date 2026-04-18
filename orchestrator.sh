#!/bin/bash
# Krok 7: Orchestrowanie przez n8n i OpenClaw - Skrypt monitorowania i zarządzania zadaniami

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Wartości domyślne
TASKS_DIR="./tasks"
LOGS_DIR="./logs"
CONFIG_FILE="./orchestrator_config.json"
MAX_RETRIES=3
RETRY_DELAY=5
PRIORITY_LOW=1
PRIORITY_MEDIUM=5
PRIORITY_HIGH=10

print_help() {
    echo "=== Orchestrator Zadań (Krok 7) ==="
    echo ""
    echo "Użycie: $0 [opcje] <komenda>"
    echo ""
    echo "Opcje:"
    echo "  --tasks-dir DIR       Katalog z zadaniami (domyślnie: ./tasks)"
    echo "  --logs-dir DIR        Katalog z logami (domyślnie: ./logs)"
    echo "  --max-retries N       Maksymalna liczba powtórzeń (domyślnie: 3)"
    echo "  --retry-delay S       Opóźnienie między próbami w sekundach (domyślnie: 5)"
    echo "  -h, --help            Wyświetl pomoc"
    echo ""
    echo "Komendy:"
    echo "  status                Pokaż status wszystkich zadań"
    echo "  run                   Uruchom oczekujące zadania"
    echo "  retry                 Ponów nieudane zadania"
    echo "  cleanup               Wyczyść zakończone zadania"
    echo "  schedule              Wyświetl harmonogram"
    echo "  notify TYPE MSG       Wyślij powiadomienie (email/telegram/discord)"
    echo ""
    echo "Przykłady:"
    echo "  $0 status"
    echo "  $0 run"
    echo "  $0 notify telegram 'Zadanie zakończone sukcesem'"
}

# Tworzenie struktur katalogów
init_directories() {
    mkdir -p "$TASKS_DIR/pending"
    mkdir -p "$TASKS_DIR/running"
    mkdir -p "$TASKS_DIR/completed"
    mkdir -p "$TASKS_DIR/failed"
    mkdir -p "$LOGS_DIR"
}

# Funkcja logująca
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOGS_DIR/orchestrator.log"
    
    case "$level" in
        INFO) echo -e "${BLUE}[$level]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$level]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[$level]${NC} $message" ;;
        ERROR) echo -e "${RED}[$level]${NC} $message" ;;
        *) echo "[$level] $message" ;;
    esac
}

# Funkcja tworząca nowe zadanie
create_task() {
    local task_name="$1"
    local task_type="$2"
    local priority="${3:-$PRIORITY_MEDIUM}"
    local payload="$4"
    
    local task_id=$(date +%Y%m%d_%H%M%S)_$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo $RANDOM)
    local task_file="$TASKS_DIR/pending/${task_id}.json"
    local timestamp=$(date -Iseconds)
    
    cat > "$task_file" << EOF
{
    "id": "$task_id",
    "name": "$task_name",
    "type": "$task_type",
    "status": "pending",
    "priority": $priority,
    "created_at": "$timestamp",
    "updated_at": "$timestamp",
    "retries": 0,
    "max_retries": $MAX_RETRIES,
    "payload": $payload,
    "result": null,
    "error": null
}
EOF
    
    log_message "INFO" "Utworzono zadanie: $task_id ($task_name)"
    echo "$task_id"
}

# Funkcja pobierająca status zadań
get_task_status() {
    local pending=$(ls -1 "$TASKS_DIR/pending"/*.json 2>/dev/null | wc -l || echo "0")
    local running=$(ls -1 "$TASKS_DIR/running"/*.json 2>/dev/null | wc -l || echo "0")
    local completed=$(ls -1 "$TASKS_DIR/completed"/*.json 2>/dev/null | wc -l || echo "0")
    local failed=$(ls -1 "$TASKS_DIR/failed"/*.json 2>/dev/null | wc -l || echo "0")
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  STATUS ORCHESTRATORA                 ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "  ${YELLOW}Oczekujące:${NC}   $pending"
    echo -e "  ${PURPLE}Uruchomione:${NC}  $running"
    echo -e "  ${GREEN}Zakończone:${NC}   $completed"
    echo -e "  ${RED}Nieudane:${NC}     $failed"
    echo ""
    echo -e "  Razem: $((pending + running + completed + failed))"
    echo ""
}

# Funkcja uruchamiająca zadania
run_pending_tasks() {
    log_message "INFO" "Rozpoczynanie przetwarzania zadań oczekujących..."
    
    local tasks_run=0
    
    # Sortuj zadania po priorytecie (najwyższy pierwszy)
    for task_file in $(ls -t "$TASKS_DIR/pending"/*.json 2>/dev/null); do
        if [[ ! -f "$task_file" ]]; then
            continue
        fi
        
        local task_id=$(basename "$task_file" .json)
        local task_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$task_file" | cut -d'"' -f4)
        local task_type=$(grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*"' "$task_file" | cut -d'"' -f4)
        
        log_message "INFO" "Uruchamianie zadania: $task_id ($task_name)"
        
        # Przenieś do running
        mv "$task_file" "$TASKS_DIR/running/"
        
        # Aktualizuj status
        local running_file="$TASKS_DIR/running/${task_id}.json"
        local timestamp=$(date -Iseconds)
        sed -i "s/\"status\": \"pending\"/\"status\": \"running\"/" "$running_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$running_file"
        
        # Symulacja wykonania zadania (w rzeczywistości tutaj byłoby wywołanie API)
        local success=true
        
        case "$task_type" in
            chunking)
                log_message "INFO" "Wykonywanie chunkingu..."
                # ./chunker -i ./input -o ./chunk 2>/dev/null || success=false
                sleep 1
                ;;
            expansion)
                log_message "INFO" "Wykonywanie ekspansji treści..."
                # ./ollama_expander -i ./chunk -o ./output 2>/dev/null || success=false
                sleep 1
                ;;
            save_results)
                log_message "INFO" "Zapisywanie wyników..."
                # ./save_results.sh -i ./chunk -o ./output 2>/dev/null || success=false
                sleep 1
                ;;
            generate_doc)
                log_message "INFO" "Generowanie dokumentu DOC..."
                # officecli generate --input ./chunks --output ./finish/book.doc 2>/dev/null || success=false
                sleep 1
                ;;
            *)
                log_message "WARNING" "Nieznany typ zadania: $task_type"
                success=false
                ;;
        esac
        
        timestamp=$(date -Iseconds)
        
        if [[ "$success" == true ]]; then
            log_message "SUCCESS" "Zadanie zakończone: $task_id"
            mv "$running_file" "$TASKS_DIR/completed/"
            sed -i "s/\"status\": \"running\"/\"status\": \"completed\"/" "$TASKS_DIR/completed/${task_id}.json"
            sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$TASKS_DIR/completed/${task_id}.json"
        else
            handle_failed_task "$running_file"
        fi
        
        tasks_run=$((tasks_run + 1))
    done
    
    if [[ $tasks_run -eq 0 ]]; then
        log_message "INFO" "Brak zadań do przetworzenia"
    else
        log_message "SUCCESS" "Przetworzono $tasks_run zadań"
    fi
}

# Funkcja obsługująca nieudane zadania
handle_failed_task() {
    local task_file="$1"
    local task_id=$(basename "$task_file" .json)
    
    local retries=$(grep -o '"retries"[[:space:]]*:[[:space:]]*[0-9]*' "$task_file" | grep -o '[0-9]*')
    local max_retries=$(grep -o '"max_retries"[[:space:]]*:[[:space:]]*[0-9]*' "$task_file" | grep -o '[0-9]*')
    
    retries=$((retries + 1))
    
    if [[ $retries -lt $max_retries ]]; then
        log_message "WARNING" "Ponawianie zadania: $task_id (próba $retries/$max_retries)"
        
        local timestamp=$(date -Iseconds)
        sed -i "s/\"retries\": [0-9]*/\"retries\": $retries/" "$task_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$task_file"
        sed -i "s/\"status\": \"running\"/\"status\": \"pending\"/" "$task_file"
        
        mv "$task_file" "$TASKS_DIR/pending/"
        
        log_message "INFO" "Opóźnienie przed ponowną próbą: ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
    else
        log_message "ERROR" "Zadanie przekroczyło limit powtórzeń: $task_id"
        
        local timestamp=$(date -Iseconds)
        sed -i "s/\"status\": \"running\"/\"status\": \"failed\"/" "$task_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$task_file"
        sed -i "s/\"error\": null/\"error\": \"Max retries exceeded\"/" "$task_file"
        
        mv "$task_file" "$TASKS_DIR/failed/"
    fi
}

# Funkcja ponawiająca nieudane zadania
retry_failed_tasks() {
    log_message "INFO" "Ponawianie nieudanych zadań..."
    
    local retried=0
    
    for task_file in "$TASKS_DIR/failed"/*.json; do
        if [[ ! -f "$task_file" ]]; then
            continue
        fi
        
        local task_id=$(basename "$task_file" .json)
        local timestamp=$(date -Iseconds)
        
        # Resetuj licznik powtórzeń i status
        sed -i "s/\"retries\": [0-9]*/\"retries\": 0/" "$task_file"
        sed -i "s/\"status\": \"failed\"/\"status\": \"pending\"/" "$task_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$task_file"
        sed -i "s/\"error\": \"[^\"]*\"/\"error\": null/" "$task_file"
        
        mv "$task_file" "$TASKS_DIR/pending/"
        
        log_message "INFO" "Zadanie przywrócone do kolejki: $task_id"
        retried=$((retried + 1))
    done
    
    if [[ $retried -eq 0 ]]; then
        log_message "INFO" "Brak nieudanych zadań do ponowienia"
    else
        log_message "SUCCESS" "Przywrócono $retried zadań do kolejki"
    fi
}

# Funkcja czyszcząca zakończone zadania
cleanup_completed() {
    log_message "INFO" "Czyszczenie zakończonych zadań..."
    
    local cleaned=0
    
    for task_file in "$TASKS_DIR/completed"/*.json; do
        if [[ ! -f "$task_file" ]]; then
            continue
        fi
        
        rm -f "$task_file"
        cleaned=$((cleaned + 1))
    done
    
    log_message "SUCCESS" "Wyczyszczono $cleaned zakończonych zadań"
}

# Funkcja wysyłająca powiadomienia
send_notification() {
    local type="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    log_message "INFO" "Wysyłanie powiadomienia ($type): $message"
    
    case "$type" in
        email)
            # Przykładowa integracja z mailx/sendmail
            if command -v mail &> /dev/null; then
                echo "$message" | mail -s "Orchestrator Notification" "${NOTIFY_EMAIL:-user@example.com}" 2>/dev/null && \
                    log_message "SUCCESS" "Powiadomienie email wysłane" || \
                    log_message "WARNING" "Nie udało się wysłać email"
            else
                log_message "WARNING" "mail nie jest zainstalowany - pomijam wysyłkę email"
            fi
            ;;
        telegram)
            # Przykładowa integracja z Telegram Bot API
            if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TELEGRAM_CHAT_ID}&text=${message}" > /dev/null 2>&1 && \
                    log_message "SUCCESS" "Powiadomienie Telegram wysłane" || \
                    log_message "WARNING" "Nie udało się wysłać powiadomienia Telegram"
            else
                log_message "WARNING" "Brak konfiguracji Telegram - symulacja wysyłki"
                echo "[TELEGRAM] $timestamp: $message"
            fi
            ;;
        discord)
            # Przykładowa integracja z Discord Webhook
            if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
                curl -s -X POST "$DISCORD_WEBHOOK_URL" \
                    -H "Content-Type: application/json" \
                    -d "{\"content\": \"$message\"}" > /dev/null 2>&1 && \
                    log_message "SUCCESS" "Powiadomienie Discord wysłane" || \
                    log_message "WARNING" "Nie udało się wysłać powiadomienia Discord"
            else
                log_message "WARNING" "Brak konfiguracji Discord - symulacja wysyłki"
                echo "[DISCORD] $timestamp: $message"
            fi
            ;;
        *)
            log_message "WARNING" "Nieznany typ powiadomienia: $type"
            ;;
    esac
}

# Funkcja wyświetlająca harmonogram
show_schedule() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  HARMONOGRAM ZADAŃ (cron-like)        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Przykładowy harmonogram (do skonfigurowania w n8n):"
    echo ""
    echo "  # Chunking nowych dokumentów - co godzinę"
    echo "  0 * * * *  run_chunking"
    echo ""
    echo "  # Ekspansja treści - co 6 godzin"
    echo "  0 */6 * * *  run_expansion"
    echo ""
    echo "  # Generowanie raportów - codziennie o północy"
    echo "  0 0 * * *  generate_reports"
    echo ""
    echo "  # Cleanup - co tydzień w niedzielę"
    echo "  0 0 * * 0  cleanup"
    echo ""
    echo -e "${YELLOW}Uwaga: Harmonogram wymaga konfiguracji w n8n lub cron${NC}"
    echo ""
}

# Dynamiczne skalowanie priorytetów
scale_priorities() {
    log_message "INFO" "Skalowanie priorytetów zadań..."
    
    # Zadania oczekujące dłużej niż 1 godzinę otrzymują wyższy priorytet
    local current_time=$(date +%s)
    local one_hour=3600
    
    for task_file in "$TASKS_DIR/pending"/*.json; do
        if [[ ! -f "$task_file" ]]; then
            continue
        fi
        
        local created_at=$(grep -o '"created_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$task_file" | cut -d'"' -f4)
        local created_ts=$(date -d "$created_at" +%s 2>/dev/null || echo "$current_time")
        local age=$((current_time - created_ts))
        
        if [[ $age -gt $one_hour ]]; then
            local current_priority=$(grep -o '"priority"[[:space:]]*:[[:space:]]*[0-9]*' "$task_file" | grep -o '[0-9]*')
            local new_priority=$((current_priority + 2))
            
            sed -i "s/\"priority\": [0-9]*/\"priority\": $new_priority/" "$task_file"
            
            local task_id=$(basename "$task_file" .json)
            log_message "INFO" "Podwyższono priorytet zadania: $task_id ($current_priority -> $new_priority)"
        fi
    done
    
    log_message "SUCCESS" "Zakończono skalowanie priorytetów"
}

# Inicjalizacja
init_directories

# Parsowanie argumentów
COMMAND=""
NOTIFY_TYPE=""
NOTIFY_MSG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tasks-dir)
            TASKS_DIR="$2"
            shift 2
            ;;
        --logs-dir)
            LOGS_DIR="$2"
            shift 2
            ;;
        --max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --retry-delay)
            RETRY_DELAY="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        status|run|retry|cleanup|schedule|scale)
            COMMAND="$1"
            shift
            ;;
        notify)
            COMMAND="notify"
            NOTIFY_TYPE="$2"
            NOTIFY_MSG="$3"
            shift 3
            ;;
        *)
            if [[ -z "$COMMAND" ]]; then
                echo -e "${RED}Nieznana opcja: $1${NC}"
                print_help
                exit 1
            fi
            ;;
    esac
done

# Wykonanie komendy
case "$COMMAND" in
    status)
        get_task_status
        ;;
    run)
        run_pending_tasks
        ;;
    retry)
        retry_failed_tasks
        ;;
    cleanup)
        cleanup_completed
        ;;
    schedule)
        show_schedule
        ;;
    scale)
        scale_priorities
        ;;
    notify)
        if [[ -n "$NOTIFY_TYPE" ]] && [[ -n "$NOTIFY_MSG" ]]; then
            send_notification "$NOTIFY_TYPE" "$NOTIFY_MSG"
        else
            echo -e "${RED}✗ Brak typu powiadomienia lub wiadomości${NC}"
            print_help
            exit 1
        fi
        ;;
    "")
        # Domyślnie pokaż status
        get_task_status
        ;;
    *)
        echo -e "${RED}✗ Nieznana komenda: $COMMAND${NC}"
        print_help
        exit 1
        ;;
esac

echo ""
log_message "INFO" "Operacja zakończona"
