#!/bin/bash
# ==============================================================================
# LLM Pipeline - Terminal User Interface (TUI)
# Interfejs tekstowy dla systemu przetwarzania książek
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SCRIPT="${SCRIPT_DIR}/pipeline.sh"
LOGS_DIR="${SCRIPT_DIR}/logs"
INPUT_DIR="${SCRIPT_DIR}/input"
FINISH_DIR="${SCRIPT_DIR}/finish"
PID_FILE="${LOGS_DIR}/pipeline.pid"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funkcje pomocnicze
clear_screen() {
    clear
}

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        LLM BOOK REWRITING PIPELINE - TERMINAL UI             ║"
    echo "║        Qwen-Coder + Qwen3.6-35B-A3B                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_menu() {
    echo -e "${YELLOW}=== MENU GŁÓWNE ===${NC}"
    echo "  [1] Start pipeline (w tle)"
    echo "  [2] Stop pipeline"
    echo "  [3] Status systemu"
    echo "  [4] Przetwórz pojedynczy plik"
    echo "  [5] Podgląd logów na żywo"
    echo "  [6] Lista plików w input/"
    echo "  [7] Lista plików w finish/"
    echo "  [8] Wyczyść pliki tymczasowe"
    echo "  [9] Test połączenia z API"
    echo "  [0] Wyjście"
    echo ""
}

get_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "${GREEN}URUCHOMIONY${NC} (PID: $(cat "$PID_FILE"))"
        return 0
    else
        echo -e "${RED}ZATRZYMANI${NC}"
        return 1
    fi
}

show_status() {
    echo -e "${CYAN}=== STATUS SYSTEMU ===${NC}"
    echo -n "Status pipeline: "
    get_status
    echo ""
    echo "Pliki w input/:     $(find "$INPUT_DIR" -type f 2>/dev/null | wc -l)"
    echo "Pliki w finish/:    $(find "$FINISH_DIR" -type f -name '*.txt' 2>/dev/null | wc -l)"
    echo "Chunki w chunk/:    $(find "${SCRIPT_DIR}/chunk" -type f 2>/dev/null | wc -l)"
    echo ""
    echo "Ostatnie 5 logów:"
    tail -5 "${LOGS_DIR}/pipeline.log" 2>/dev/null || echo "  Brak logów"
    echo ""
}

show_logs_live() {
    echo -e "${CYAN}=== PODGLĄD LOGÓW NA ŻYWO ===${NC}"
    echo "(Ctrl+C aby wyjść)"
    sleep 2
    tail -f "${LOGS_DIR}/pipeline.log" 2>/dev/null || echo "Brak pliku logów"
}

list_input_files() {
    echo -e "${CYAN}=== PLIKI W KATALOGU input/ ===${NC}"
    if [[ -d "$INPUT_DIR" ]]; then
        local count=0
        shopt -s nullglob
        for ext in txt md doc docx xls xlsx odt ods ppt pptx pdf; do
            for file in "$INPUT_DIR"/*."$ext"; do
                if [[ -f "$file" ]]; then
                    echo "  📄 $(basename "$file") ($(wc -c < "$file") bajtów)"
                    ((count++)) || true
                fi
            done
        done
        shopt -u nullglob
        if [[ $count -eq 0 ]]; then
            echo "  Brak plików"
        fi
    else
        echo "  Katalog nie istnieje"
    fi
    echo ""
}

list_finish_files() {
    echo -e "${CYAN}=== PLIKI W KATALOGU finish/ ===${NC}"
    if [[ -d "$FINISH_DIR" ]]; then
        local count=0
        shopt -s nullglob
        for file in "$FINISH_DIR"/*.txt; do
            if [[ -f "$file" ]]; then
                echo "  ✅ $(basename "$file") ($(wc -c < "$file") bajtów)"
                ((count++)) || true
            fi
        done
        shopt -u nullglob
        if [[ $count -eq 0 ]]; then
            echo "  Brak przetworzonych plików"
        fi
    else
        echo "  Katalog nie istnieje"
    fi
    echo ""
}

process_single_file() {
    echo -e "${CYAN}=== PRZETWARZANIE POJEDYNCZEGO PLIKU ===${NC}"
    list_input_files
    
    read -p "Podaj nazwę pliku do przetworzenia: " filename
    
    if [[ -z "$filename" ]]; then
        echo "Anulowano."
        return
    fi
    
    # Sprawdź czy plik istnieje z dowolnym rozszerzeniem
    local full_path=""
    for ext in txt md doc docx xls xlsx odt ods ppt pptx pdf; do
        if [[ -f "${INPUT_DIR}/${filename}" ]]; then
            full_path="${INPUT_DIR}/${filename}"
            break
        elif [[ -f "${INPUT_DIR}/${filename}.${ext}" ]]; then
            full_path="${INPUT_DIR}/${filename}.${ext}"
            break
        fi
    done
    
    if [[ -z "$full_path" ]] || [[ ! -f "$full_path" ]]; then
        echo -e "${RED}Błąd: Plik nie znaleziony${NC}"
        return
    fi
    
    echo "Przetwarzanie: $full_path"
    if [[ -x "$PIPELINE_SCRIPT" ]]; then
        "$PIPELINE_SCRIPT" process "$full_path"
    else
        echo -e "${RED}Błąd: Skrypt pipeline.sh nie jest wykonalny${NC}"
    fi
}

test_api_connection() {
    echo -e "${CYAN}=== TEST POŁĄCZENIA Z API ===${NC}"
    
    if [[ -x "$PIPELINE_SCRIPT" ]]; then
        "$PIPELINE_SCRIPT" test-api
    else
        echo -e "${RED}Błąd: Skrypt pipeline.sh nie jest wykonalny${NC}"
    fi
}

clean_temp_files() {
    echo -e "${CYAN}=== CZYSZCZENIE PLIKÓW TYMCZASOWYCH ===${NC}"
    
    read -p "Czy na pewno chcesz wyczyścić pliki tymczasowe? (t/n): " confirm
    if [[ "$confirm" == "t" ]] || [[ "$confirm" == "T" ]]; then
        rm -rf "${SCRIPT_DIR}/chunk/"* 2>/dev/null || true
        rm -rf "${SCRIPT_DIR}/temp/"* 2>/dev/null || true
        echo -e "${GREEN}Wyczyszczono katalogi robocze${NC}"
    else
        echo "Anulowano."
    fi
}

# Główna pętla TUI
main_loop() {
    while true; do
        clear_screen
        print_header
        show_status
        print_menu
        
        read -p "Wybierz opcję [0-9]: " choice
        
        case $choice in
            1)
                echo -e "${GREEN}Uruchamianie pipeline...${NC}"
                if [[ -x "$PIPELINE_SCRIPT" ]]; then
                    "$PIPELINE_SCRIPT" start
                else
                    echo -e "${RED}Błąd: Skrypt pipeline.sh nie jest wykonalny${NC}"
                fi
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            2)
                echo -e "${YELLOW}Zatrzymywanie pipeline...${NC}"
                if [[ -x "$PIPELINE_SCRIPT" ]]; then
                    "$PIPELINE_SCRIPT" stop
                else
                    echo -e "${RED}Błąd: Skrypt pipeline.sh nie jest wykonalny${NC}"
                fi
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            3)
                show_status
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            4)
                process_single_file
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            5)
                show_logs_live
                ;;
            6)
                list_input_files
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            7)
                list_finish_files
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            8)
                clean_temp_files
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            9)
                test_api_connection
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            0)
                echo -e "${CYAN}Do widzenia!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Nieprawidłowa opcja${NC}"
                sleep 2
                ;;
        esac
    done
}

# Obsługa argumentów wiersza poleceń
case "${1:-tui}" in
    tui|--tui)
        main_loop
        ;;
    status|--status|-s)
        print_header
        show_status
        ;;
    logs|--logs|-l)
        print_header
        show_logs_live
        ;;
    list|--list)
        print_header
        list_input_files
        list_finish_files
        ;;
    help|--help|-h)
        echo "LLM Pipeline TUI"
        echo ""
        echo "Użycie: $0 [opcja]"
        echo ""
        echo "Opcje:"
        echo "  tui, --tui      Uruchom interfejs tekstowy (domyślnie)"
        echo "  status, -s      Pokaż status systemu"
        echo "  logs, -l        Podgląd logów na żywo"
        echo "  list            Lista plików wejściowych i wyjściowych"
        echo "  help, -h        Pokaż tę pomoc"
        ;;
    *)
        echo "Nieznana opcja: $1"
        echo "Użyj '$0 help' aby uzyskać pomoc."
        exit 1
        ;;
esac
