#!/bin/bash

#############################################################################
# BOOK PROCESSING MANAGER - GUI TERMINAL EDITION
#############################################################################
# Skrypt do zarządzania przetwarzaniem książek z interfejsem terminalowym
#############################################################################

# ============================================================================
# KONFIGURACJA - UZUPEŁNIJ TE ZMIENNE PRZED UŻYCIEM
# ============================================================================

# GitHub Configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"           # Twój token dostępu do GitHub
GITHUB_USERNAME="${GITHUB_USERNAME:-}"     # Twoja nazwa użytkownika GitHub
GITHUB_REPO_URL="${GITHUB_REPO_URL:-}"     # URL repozytorium GitHub (np. https://github.com/user/repo.git)

# Processing Configuration
DEFAULT_CHUNK_SIZE=4096                    # Domyślna wielkość chunka w tokenach
MAX_FILE_SIZE_MB=100                       # Maksymalny rozmiar pliku wejściowego w MB
OUTPUT_FORMAT="md"                         # Format wyjściowy (md, txt, docx)
DOC_OUTPUT_FORMAT="doc"                    # Format końcowego dokumentu

# Directory Structure
BOOKS_BASE_DIR="/books"
INPUT_SUBDIR="input"
CHUNK_SUBDIR="chunk"
REWRITE_SUBDIR="rewrite"
FINISH_SUBDIR="finish"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         BOOK PROCESSING MANAGER - TERMINAL GUI            ║"
    echo "╠═══════════════════════════════════════════════════════════╣"
    echo "║  Wersja: 1.0                                              ║"
    echo "║  Autor: Shell Script Generator                            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_github_config() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_warning "GITHUB_TOKEN nie jest ustawiony!"
        return 1
    fi
    if [[ -z "$GITHUB_USERNAME" ]]; then
        log_warning "GITHUB_USERNAME nie jest ustawiony!"
        return 1
    fi
    if [[ -z "$GITHUB_REPO_URL" ]]; then
        log_warning "GITHUB_REPO_URL nie jest ustawiony!"
        return 1
    fi
    return 0
}

get_book_dirs() {
    local dirs=()
    for dir in "$BOOKS_BASE_DIR"/book*/; do
        if [[ -d "$dir" ]]; then
            dirs+=("$(basename "$dir")")
        fi
    done
    echo "${dirs[@]}"
}

count_books() {
    local count=0
    for dir in "$BOOKS_BASE_DIR"/book*/; do
        if [[ -d "$dir" ]]; then
            ((count++))
        fi
    done
    echo "$count"
}

list_books_with_index() {
    local index=1
    for dir in "$BOOKS_BASE_DIR"/book*/; do
        if [[ -d "$dir" ]]; then
            local book_name=$(basename "$dir")
            local input_files=$(find "$dir$INPUT_SUBDIR" -type f 2>/dev/null | wc -l)
            local chunk_files=$(find "$dir$CHUNK_SUBDIR" -type f 2>/dev/null | wc -l)
            local rewrite_files=$(find "$dir$REWRITE_SUBDIR" -type f 2>/dev/null | wc -l)
            local finish_files=$(find "$dir$FINISH_SUBDIR" -type f 2>/dev/null | wc -l)
            echo "$index|$book_name|$input_files|$chunk_files|$rewrite_files|$finish_files"
            ((index++))
        fi
    done
}

select_book_interactive() {
    local books=()
    while IFS='|' read -r idx name input chunks rewrite finish; do
        books+=("$idx|$name|$input|$chunks|$rewrite|$finish")
    done < <(list_books_with_index)
    
    if [[ ${#books[@]} -eq 0 ]]; then
        log_error "Nie znaleziono żadnych książek w katalogu $BOOKS_BASE_DIR"
        return 1
    fi
    
    echo ""
    echo "Dostępne książki:"
    echo "─────────────────────────────────────────────────────────────"
    printf "%-5s %-20s %-10s %-10s %-10s %-10s\n" "ID" "Nazwa" "Input" "Chunki" "Rewrite" "Finish"
    echo "─────────────────────────────────────────────────────────────"
    
    for book in "${books[@]}"; do
        IFS='|' read -r idx name input chunks rewrite finish <<< "$book"
        printf "%-5s %-20s %-10s %-10s %-10s %-10s\n" "$idx" "$name" "$input" "$chunks" "$rewrite" "$finish"
    done
    echo "─────────────────────────────────────────────────────────────"
    echo ""
    
    while true; do
        read -p "Wybierz numer książki (1-${#books[@]}) lub 'q' aby anulować: " choice
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 1
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#books[@]} ]]; then
            local selected_book="${books[$((choice-1))]}"
            IFS='|' read -r idx name input chunks rewrite finish <<< "$selected_book"
            echo "$name"
            return 0
        else
            log_error "Nieprawidłowy wybór. Spróbuj ponownie."
        fi
    done
}

# ============================================================================
# FILE CONVERSION FUNCTIONS
# ============================================================================

detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    case "$ext" in
        doc) echo "doc" ;;
        docx) echo "docx" ;;
        odt) echo "odt" ;;
        ods|xlsx|xls) echo "spreadsheet" ;;
        pdf) echo "pdf" ;;
        md|markdown) echo "md" ;;
        txt|text) echo "txt" ;;
        rtf) echo "rtf" ;;
        *) 
            # Try to detect using file command
            local mime=$(file -b --mime-type "$file" 2>/dev/null)
            case "$mime" in
                *pdf*) echo "pdf" ;;
                *word*|*msword*) echo "doc" ;;
                *office*|*opendocument*) echo "odt" ;;
                *text*|*plain*) echo "txt" ;;
                *) echo "unknown" ;;
            esac
            ;;
    esac
}

convert_to_text() {
    local input_file="$1"
    local output_file="$2"
    local file_type=$(detect_file_type "$input_file")
    
    log_info "Konwertowanie pliku: $(basename "$input_file") (typ: $file_type)"
    
    case "$file_type" in
        doc)
            if command -v catdoc &> /dev/null; then
                catdoc "$input_file" > "$output_file" 2>/dev/null
            elif command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t plain -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji .doc"
                return 1
            fi
            ;;
        docx)
            if command -v docx2txt &> /dev/null; then
                docx2txt "$input_file" "$output_file" 2>/dev/null
            elif command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t plain -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji .docx"
                return 1
            fi
            ;;
        odt)
            if command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t plain -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji .odt"
                return 1
            fi
            ;;
        spreadsheet)
            if command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t csv -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji arkuszy kalkulacyjnych"
                return 1
            fi
            ;;
        pdf)
            if command -v pdftotext &> /dev/null; then
                pdftotext "$input_file" "$output_file" 2>/dev/null
            elif command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t plain -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji .pdf"
                return 1
            fi
            ;;
        md|markdown)
            cp "$input_file" "$output_file"
            ;;
        txt|text)
            cp "$input_file" "$output_file"
            ;;
        rtf)
            if command -v unrtf &> /dev/null; then
                unrtf --text "$input_file" > "$output_file" 2>/dev/null
            elif command -v pandoc &> /dev/null; then
                pandoc "$input_file" -t plain -o "$output_file" 2>/dev/null
            else
                log_error "Brak narzędzia do konwersji .rtf"
                return 1
            fi
            ;;
        *)
            log_error "Nieznany typ pliku: $file_type"
            return 1
            ;;
    esac
    
    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        log_success "Pomyślnie skonwertowano do: $(basename "$output_file")"
        return 0
    else
        log_error "Konwersja nie powiodła się"
        return 1
    fi
}

# ============================================================================
# CHUNKING FUNCTIONS
# ============================================================================

estimate_tokens() {
    local text="$1"
    # Przybliżone szacowanie: 1 token ≈ 4 znaki w językach łacińskich
    local char_count=${#text}
    echo $((char_count / 4))
}

split_into_chunks() {
    local input_file="$1"
    local output_dir="$2"
    local chunk_size="${3:-$DEFAULT_CHUNK_SIZE}"
    local overlap="${4:-0}"
    
    log_step "Dzielenie pliku na chunki (rozmiar: $chunk_size tokenów)"
    
    mkdir -p "$output_dir"
    
    local base_name=$(basename "$input_file" | sed 's/\.[^.]*$//')
    local content=$(cat "$input_file")
    local total_chars=${#content}
    local chars_per_chunk=$((chunk_size * 4))  # Konwersja tokenów na znaki
    
    if [[ $chars_per_chunk -lt 1000 ]]; then
        chars_per_chunk=1000
    fi
    
    local chunk_num=1
    local start_pos=0
    
    while [[ $start_pos -lt $total_chars ]]; do
        local end_pos=$((start_pos + chars_per_chunk))
        
        if [[ $end_pos -ge $total_chars ]]; then
            end_pos=$total_chars
        else
            # Spróbuj znaleźć granicę słowa/linii
            local temp_end=$end_pos
            while [[ $temp_end -gt $start_pos ]] && [[ "${content:$temp_end:1}" != $'\n' ]] && [[ "${content:$temp_end:1}" != " " ]]; do
                ((temp_end--))
            done
            if [[ $temp_end -gt $start_pos ]]; then
                end_pos=$temp_end
            fi
        fi
        
        local chunk_content="${content:$start_pos:$((end_pos - start_pos))}"
        local chunk_file=$(printf "%s/chunk_%03d.txt" "$output_dir" "$chunk_num")
        
        echo "$chunk_content" > "$chunk_file"
        
        log_info "Utworzono chunk $chunk_num: $(wc -c < "$chunk_file") znaków"
        
        ((chunk_num++))
        
        # Przesunięcie z overlapem jeśli określono
        if [[ $overlap -gt 0 ]] && [[ $end_pos -lt $total_chars ]]; then
            local overlap_chars=$((overlap * 4))
            start_pos=$((end_pos - overlap_chars))
            if [[ $start_pos -lt 0 ]]; then
                start_pos=0
            fi
        else
            start_pos=$end_pos
        fi
    done
    
    log_success "Utworzono $((chunk_num - 1)) chunków w katalogu: $output_dir"
}

process_all_input_files() {
    local book_dir="$1"
    local chunk_size="${2:-$DEFAULT_CHUNK_SIZE}"
    
    local input_dir="$book_dir/$INPUT_SUBDIR"
    local chunk_dir="$book_dir/$CHUNK_SUBDIR"
    
    if [[ ! -d "$input_dir" ]]; then
        log_error "Katalog input nie istnieje: $input_dir"
        return 1
    fi
    
    log_step "Przetwarzanie wszystkich plików z katalogu: $input_dir"
    
    local temp_dir=$(mktemp -d)
    local converted_count=0
    local chunked_count=0
    
    for file in "$input_dir"/*; do
        if [[ -f "$file" ]]; then
            local base_name=$(basename "$file" | sed 's/\.[^.]*$//')
            local temp_text="$temp_dir/${base_name}.txt"
            
            log_info "Przetwarzanie: $(basename "$file")"
            
            if convert_to_text "$file" "$temp_text"; then
                ((converted_count++))
                
                if split_into_chunks "$temp_text" "$chunk_dir" "$chunk_size"; then
                    ((chunked_count++))
                fi
            fi
        fi
    done
    
    rm -rf "$temp_dir"
    
    log_success "Przetworzono $converted_count plików, utworzono chunki dla $chunked_count plików"
}

# ============================================================================
# GITHUB FUNCTIONS
# ============================================================================

clone_or_pull_repo() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local repo_dir="$book_dir/github_repo"
    
    log_step "Klonowanie/aktualizacja repozytorium GitHub"
    
    if check_github_config; then
        if [[ -d "$repo_dir/.git" ]]; then
            log_info "Repozytorium już istnieje, wykonuję pull..."
            cd "$repo_dir" || return 1
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
            cd - > /dev/null
        else
            log_info "Klonowanie repozytorium..."
            mkdir -p "$repo_dir"
            cd "$repo_dir" || return 1
            git clone "$GITHUB_REPO_URL" . 2>/dev/null || {
                log_error "Nie udało się sklonować repozytorium"
                cd - > /dev/null
                return 1
            }
            cd - > /dev/null
        fi
        log_success "Repozytorium gotowe w: $repo_dir"
        echo "$repo_dir"
        return 0
    else
        log_error "Konfiguracja GitHub niekompletna"
        return 1
    fi
}

upload_chunks_to_github() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local chunk_dir="$book_dir/$CHUNK_SUBDIR"
    local repo_dir="$book_dir/github_repo"
    local github_chunk_dir="${2:-chunks}"
    
    log_step "Wysyłanie chunków do GitHub"
    
    if ! check_github_config; then
        return 1
    fi
    
    if [[ ! -d "$chunk_dir" ]]; then
        log_error "Katalog chunków nie istnieje: $chunk_dir"
        return 1
    fi
    
    # Klonuj repozytorium
    repo_dir=$(clone_or_pull_repo "$book_name") || return 1
    
    # Przygotuj strukturę katalogów w repo
    local target_dir="$repo_dir/$github_chunk_dir/$book_name"
    mkdir -p "$target_dir"
    
    # Kopiuj chunki
    local upload_count=0
    for chunk_file in "$chunk_dir"/*; do
        if [[ -f "$chunk_file" ]]; then
            cp "$chunk_file" "$target_dir/"
            ((upload_count++))
        fi
    done
    
    if [[ $upload_count -eq 0 ]]; then
        log_error "Brak plików do wysłania"
        return 1
    fi
    
    # Commit i push
    cd "$repo_dir" || return 1
    
    git config user.email "script@local" 2>/dev/null
    git config user.name "Book Processor" 2>/dev/null
    
    git add "$github_chunk_dir/$book_name" 2>/dev/null
    
    if git diff --cached --quiet; then
        log_info "Brak zmian do commitowania"
        cd - > /dev/null
        return 0
    fi
    
    git commit -m "Upload chunks for $book_name - $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
    
    # Push z autoryzacją
    local auth_url=$(echo "$GITHUB_REPO_URL" | sed "s|https://|https://$GITHUB_USERNAME:$GITHUB_TOKEN@|")
    
    if git push "$auth_url" HEAD:main 2>/dev/null || git push "$auth_url" HEAD:master 2>/dev/null; then
        log_success "Pomyślnie wysłano $upload_count chunków do GitHub"
        cd - > /dev/null
        return 0
    else
        log_error "Push do GitHub nie powiódł się"
        cd - > /dev/null
        return 1
    fi
}

download_from_github() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local rewrite_dir="$book_dir/$REWRITE_SUBDIR"
    local repo_dir="$book_dir/github_repo"
    local source_dir="${2:-chunks}"
    
    log_step "Pobieranie plików z GitHub"
    
    if ! check_github_config; then
        return 1
    fi
    
    # Klonuj/aktualizuj repozytorium
    repo_dir=$(clone_or_pull_repo "$book_name") || return 1
    
    # Sprawdź czy istnieją chunki w repo
    local github_chunk_dir="$repo_dir/$source_dir/$book_name"
    
    if [[ ! -d "$github_chunk_dir" ]]; then
        log_error "Nie znaleziono chunków w repozytorium: $source_dir/$book_name"
        return 1
    fi
    
    # Kopiuj do katalogu rewrite
    mkdir -p "$rewrite_dir"
    
    local download_count=0
    for chunk_file in "$github_chunk_dir"/*; do
        if [[ -f "$chunk_file" ]]; then
            cp "$chunk_file" "$rewrite_dir/"
            ((download_count++))
        fi
    done
    
    if [[ $download_count -gt 0 ]]; then
        log_success "Pobrano $download_count plików z GitHub do: $rewrite_dir"
        return 0
    else
        log_error "Brak plików do pobrania"
        return 1
    fi
}

analyze_github_repo() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local repo_dir="$book_dir/github_repo"
    
    log_step "Analiza repozytorium GitHub"
    
    if ! check_github_config; then
        return 1
    fi
    
    repo_dir=$(clone_or_pull_repo "$book_name") || return 1
    
    cd "$repo_dir" || return 1
    
    echo ""
    echo "=== Analiza repozytorium ==="
    echo "Lokalizacja: $repo_dir"
    echo ""
    
    # Liczba commitów
    local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    echo "Liczba commitów: $commit_count"
    
    # Ostatni commit
    local last_commit=$(git log -1 --format="%h - %s (%ci)" 2>/dev/null || echo "Brak danych")
    echo "Ostatni commit: $last_commit"
    
    # Struktura katalogów
    echo ""
    echo "Struktura katalogów:"
    find . -type d -not -path './.git*' | head -20
    
    # Pliki chunków
    echo ""
    echo "Pliki chunków:"
    find . -name "chunk_*" -type f 2>/dev/null | head -20
    
    cd - > /dev/null
    
    return 0
}

# ============================================================================
# REWRITE AND MERGE FUNCTIONS
# ============================================================================

rewrite_chunks_to_markdown() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local chunk_dir="$book_dir/$CHUNK_SUBDIR"
    local rewrite_dir="$book_dir/$REWRITE_SUBDIR"
    
    log_step "Przepisywanie chunków do formatu Markdown"
    
    if [[ ! -d "$chunk_dir" ]]; then
        log_error "Katalog chunków nie istnieje: $chunk_dir"
        return 1
    fi
    
    mkdir -p "$rewrite_dir"
    
    local rewrite_count=0
    for chunk_file in "$chunk_dir"/*; do
        if [[ -f "$chunk_file" ]]; then
            local base_name=$(basename "$chunk_file" | sed 's/\.[^.]*$//')
            local output_file="$rewrite_dir/${base_name}.md"
            
            # Dodaj nagłówek Markdown
            {
                echo "---"
                echo "title: \"$base_name\""
                echo "source: \"$(basename "$chunk_file")\""
                echo "generated: \"$(date '+%Y-%m-%d %H:%M:%S')\""
                echo "---"
                echo ""
                echo "# $base_name"
                echo ""
                cat "$chunk_file"
            } > "$output_file"
            
            ((rewrite_count++))
            log_info "Przekonwertowano: $(basename "$output_file")"
        fi
    done
    
    if [[ $rewrite_count -gt 0 ]]; then
        log_success "Przepisano $rewrite_count chunków do formatu .md w katalogu: $rewrite_dir"
        return 0
    else
        log_error "Brak chunków do przepisania"
        return 1
    fi
}

merge_to_doc() {
    local book_name="$1"
    local book_dir="$BOOKS_BASE_DIR/$book_name"
    local rewrite_dir="$book_dir/$REWRITE_SUBDIR"
    local finish_dir="$book_dir/$FINISH_SUBDIR"
    local output_format="${2:-$DOC_OUTPUT_FORMAT}"
    
    log_step "Łączenie plików do jednego dokumentu"
    
    if [[ ! -d "$rewrite_dir" ]]; then
        log_error "Katalog rewrite nie istnieje: $rewrite_dir"
        return 1
    fi
    
    mkdir -p "$finish_dir"
    
    local temp_merged=$(mktemp)
    local file_list=()
    
    # Posortuj pliki alfabetycznie
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(find "$rewrite_dir" -type f \( -name "*.md" -o -name "*.txt" \) -print0 | sort -z)
    
    if [[ ${#file_list[@]} -eq 0 ]]; then
        log_error "Brak plików do połączenia w katalogu: $rewrite_dir"
        rm -f "$temp_merged"
        return 1
    fi
    
    log_info "Znaleziono ${#file_list[@]} plików do połączenia"
    
    # Połącz wszystkie pliki
    for file in "${file_list[@]}"; do
        echo "" >> "$temp_merged"
        echo "---" >> "$temp_merged"
        echo "" >> "$temp_merged"
        cat "$file" >> "$temp_merged"
    done
    
    local output_file="$finish_dir/${book_name}.${output_format}"
    
    # Konwertuj do formatu DOC/DOCX używając pandoc
    if command -v pandoc &> /dev/null; then
        if [[ "$output_format" == "doc" ]] || [[ "$output_format" == "docx" ]]; then
            pandoc "$temp_merged" -t docx -o "${output_file%.${output_format}}.docx" 2>/dev/null
            if [[ -f "${output_file%.${output_format}}.docx" ]]; then
                mv "${output_file%.${output_format}}.docx" "$output_file"
            fi
        else
            cp "$temp_merged" "$output_file"
        fi
    else
        cp "$temp_merged" "$output_file"
    fi
    
    rm -f "$temp_merged"
    
    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        local file_size=$(du -h "$output_file" | cut -f1)
        log_success "Utworzono plik: $output_file (rozmiar: $file_size)"
        return 0
    else
        log_error "Tworzenie pliku końcowego nie powiodło się"
        return 1
    fi
}

# ============================================================================
# MAIN MENU FUNCTIONS
# ============================================================================

show_main_menu() {
    show_banner
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    MENU GŁÓWNE                            ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1. Wybierz książkę i załaduj"
    echo "  2. Chunkuj książkę"
    echo "  3. Wyślij chunki do GitHub"
    echo "  4. Przepisz chunki do formatu .md"
    echo "  5. Analizuj repo GitHub i pobierz książkę"
    echo "  6. Połącz pliki i utwórz dokument .doc"
    echo ""
    echo "  7. Przetwórz wszystkie książki automatycznie"
    echo "  8. Konfiguracja"
    echo "  9. Status systemu"
    echo "  0. Wyjdź"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

option_select_book() {
    log_step "Wybór książki"
    
    local selected_book=$(select_book_interactive)
    
    if [[ -n "$selected_book" ]]; then
        log_success "Wybrano książkę: $selected_book"
        echo "$selected_book"
        return 0
    else
        log_info "Anulowano wybór"
        return 1
    fi
}

option_chunk_book() {
    log_step "Chunkowanie książki"
    
    local book_name=$(select_book_interactive)
    
    if [[ -z "$book_name" ]]; then
        return 1
    fi
    
    read -p "Podaj rozmiar chunka w tokenach (domyślnie $DEFAULT_CHUNK_SIZE): " chunk_size
    chunk_size=${chunk_size:-$DEFAULT_CHUNK_SIZE}
    
    process_all_input_files "$BOOKS_BASE_DIR/$book_name" "$chunk_size"
}

option_upload_to_github() {
    log_step "Wysyłanie do GitHub"
    
    local book_name=$(select_book_interactive)
    
    if [[ -z "$book_name" ]]; then
        return 1
    fi
    
    read -p "Podaj nazwę katalogu w repo GitHub (domyślnie: chunks): " github_dir
    github_dir=${github_dir:-chunks}
    
    upload_chunks_to_github "$book_name" "$github_dir"
}

option_rewrite_chunks() {
    log_step "Przepisywanie chunków do Markdown"
    
    local book_name=$(select_book_interactive)
    
    if [[ -z "$book_name" ]]; then
        return 1
    fi
    
    rewrite_chunks_to_markdown "$book_name"
}

option_download_from_github() {
    log_step "Pobieranie z GitHub"
    
    local book_name=$(select_book_interactive)
    
    if [[ -z "$book_name" ]]; then
        return 1
    fi
    
    read -p "Podaj nazwę katalogu źródłowego w repo (domyślnie: chunks): " source_dir
    source_dir=${source_dir:-chunks}
    
    download_from_github "$book_name" "$source_dir"
}

option_merge_to_doc() {
    log_step "Łączenie do dokumentu .doc"
    
    local book_name=$(select_book_interactive)
    
    if [[ -z "$book_name" ]]; then
        return 1
    fi
    
    read -p "Podaj format wyjściowy [doc/docx/md] (domyślnie: doc): " output_format
    output_format=${output_format:-doc}
    
    merge_to_doc "$book_name" "$output_format"
}

option_auto_process_all() {
    log_step "Automatyczne przetwarzanie wszystkich książek"
    
    local books=($(get_book_dirs))
    
    if [[ ${#books[@]} -eq 0 ]]; then
        log_error "Brak książek do przetworzenia"
        return 1
    fi
    
    read -p "Czy na pewno chcesz przetworzyć wszystkie ${#books[@]} książki? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Anulowano"
        return 1
    fi
    
    read -p "Podaj rozmiar chunka w tokenach (domyślnie $DEFAULT_CHUNK_SIZE): " chunk_size
    chunk_size=${chunk_size:-$DEFAULT_CHUNK_SIZE}
    
    for book in "${books[@]}"; do
        echo ""
        echo "════════════════════════════════════════════"
        log_step "Przetwarzanie książki: $book"
        echo "════════════════════════════════════════════"
        
        process_all_input_files "$BOOKS_BASE_DIR/$book" "$chunk_size"
        rewrite_chunks_to_markdown "$book"
        merge_to_doc "$book" "doc"
        
        log_success "Zakończono przetwarzanie książki: $book"
        echo ""
    done
    
    log_success "Zakończono przetwarzanie wszystkich książek"
}

option_configure() {
    log_step "Konfiguracja"
    
    echo ""
    echo "Aktualna konfiguracja:"
    echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:-(nie ustawiony)}"
    echo "  GITHUB_USERNAME: ${GITHUB_USERNAME:-(nie ustawiony)}"
    echo "  GITHUB_REPO_URL: ${GITHUB_REPO_URL:-(nie ustawiony)}"
    echo "  DEFAULT_CHUNK_SIZE: $DEFAULT_CHUNK_SIZE"
    echo "  OUTPUT_FORMAT: $OUTPUT_FORMAT"
    echo ""
    
    echo "Możesz ustawić zmienne środowiskowe przed uruchomieniem skryptu:"
    echo "  export GITHUB_TOKEN='twój_token'"
    echo "  export GITHUB_USERNAME='twoja_nazwa'"
    echo "  export GITHUB_REPO_URL='https://github.com/user/repo.git'"
    echo ""
    
    read -p "Czy chcesz tymczasowo ustawić token GitHub? [y/N]: " set_token
    if [[ "$set_token" == "y" || "$set_token" == "Y" ]]; then
        read -sp "Podaj token GitHub: " GITHUB_TOKEN
        echo ""
        log_success "Token ustawiony (tylko na tę sesję)"
    fi
    
    read -p "Czy chcesz zmienić domyślny rozmiar chunka? [y/N]: " set_chunk
    if [[ "$set_chunk" == "y" || "$set_chunk" == "Y" ]]; then
        read -p "Nowy rozmiar chunka (tokeny): " DEFAULT_CHUNK_SIZE
        log_success "Rozmiar chunka zmieniony na: $DEFAULT_CHUNK_SIZE"
    fi
}

option_show_status() {
    log_step "Status systemu"
    
    echo ""
    echo "=== STATUS SYSTEMU ==="
    echo ""
    
    echo "Katalogi książek:"
    local total_books=$(count_books)
    echo "  Łączna liczba książek: $total_books"
    echo ""
    
    if [[ $total_books -gt 0 ]]; then
        list_books_with_index | while IFS='|' read -r idx name input chunks rewrite finish; do
            echo "  [$idx] $name"
            echo "      Input:   $input plików"
            echo "      Chunki:  $chunks plików"
            echo "      Rewrite: $rewrite plików"
            echo "      Finish:  $finish plików"
        done
    fi
    
    echo ""
    echo "Narzędzia:"
    echo "  pandoc: $(command -v pandoc &> /dev/null && echo '✓' || echo '✗')"
    echo "  docx2txt: $(command -v docx2txt &> /dev/null && echo '✓' || echo '✗')"
    echo "  pdftotext: $(command -v pdftotext &> /dev/null && echo '✓' || echo '✗')"
    echo "  git: $(command -v git &> /dev/null && echo '✓' || echo '✗')"
    echo "  unrtf: $(command -v unrtf &> /dev/null && echo '✓' || echo '✗')"
    echo "  catdoc: $(command -v catdoc &> /dev/null && echo '✓' || echo '✗')"
    
    echo ""
    echo "Konfiguracja GitHub:"
    check_github_config && echo "  Status: ✓ Skonfigurowane" || echo "  Status: ✗ Nie skonfigurowane"
    
    echo ""
}

# ============================================================================
# COMMAND LINE ARGUMENTS
# ============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -h, --help              Show this help message
  -b, --book NAME         Specify book name directly (skip interactive selection)
  -c, --chunk-size SIZE   Set chunk size in tokens (default: $DEFAULT_CHUNK_SIZE)
  -a, --auto              Auto-process all books without interaction
  -s, --select-book       Select and load a book
  -k, --chunk             Chunk the selected book
  -u, --upload            Upload chunks to GitHub
  -r, --rewrite           Rewrite chunks to Markdown format
  -d, --download          Download from GitHub
  -m, --merge             Merge files into single document
  -g, --github-token TK   Set GitHub token
  -n, --github-user USR   Set GitHub username
  -l, --github-url URL    Set GitHub repository URL
  --status                Show system status
  --configure             Interactive configuration

EXAMPLES:
  $0 --auto                           # Process all books automatically
  $0 -b book1 -k                      # Chunk book1
  $0 -b book1 -k -u                   # Chunk book1 and upload to GitHub
  $0 -b book1 -k -u -r -m             # Full pipeline for book1
  $0 --github-token ABC123 -b book1 -u  # Upload with token

EOF
}

parse_arguments() {
    local book_name=""
    local action=""
    local run_auto=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -b|--book)
                book_name="$2"
                shift 2
                ;;
            -c|--chunk-size)
                DEFAULT_CHUNK_SIZE="$2"
                shift 2
                ;;
            -a|--auto)
                run_auto=true
                shift
                ;;
            -s|--select-book)
                action="select"
                shift
                ;;
            -k|--chunk)
                action="${action}chunk,"
                shift
                ;;
            -u|--upload)
                action="${action}upload,"
                shift
                ;;
            -r|--rewrite)
                action="${action}rewrite,"
                shift
                ;;
            -d|--download)
                action="${action}download,"
                shift
                ;;
            -m|--merge)
                action="${action}merge,"
                shift
                ;;
            -g|--github-token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            -n|--github-user)
                GITHUB_USERNAME="$2"
                shift 2
                ;;
            -l|--github-url)
                GITHUB_REPO_URL="$2"
                shift 2
                ;;
            --status)
                option_show_status
                exit 0
                ;;
            --configure)
                option_configure
                exit 0
                ;;
            *)
                log_error "Nieznana opcja: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute actions
    if [[ "$run_auto" == true ]]; then
        option_auto_process_all
        exit $?
    fi
    
    if [[ -n "$book_name" ]]; then
        log_info "Użyto książki: $book_name"
        
        if [[ -n "$action" ]]; then
            IFS=',' read -ra ACTIONS <<< "$action"
            for act in "${ACTIONS[@]}"; do
                case $act in
                    select)
                        echo "Book: $book_name"
                        ;;
                    chunk)
                        process_all_input_files "$BOOKS_BASE_DIR/$book_name" "$DEFAULT_CHUNK_SIZE"
                        ;;
                    upload)
                        upload_chunks_to_github "$book_name"
                        ;;
                    rewrite)
                        rewrite_chunks_to_markdown "$book_name"
                        ;;
                    download)
                        download_from_github "$book_name"
                        ;;
                    merge)
                        merge_to_doc "$book_name"
                        ;;
                esac
            done
        else
            # Default: show book info
            echo "Book directory: $BOOKS_BASE_DIR/$book_name"
            ls -la "$BOOKS_BASE_DIR/$book_name/" 2>/dev/null || log_error "Book not found"
        fi
        exit $?
    fi
    
    # If no arguments, show interactive menu
    return 1
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

run_interactive_mode() {
    while true; do
        show_main_menu
        
        read -p "Wybierz opcję (0-9): " choice
        
        case $choice in
            1)
                option_select_book
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            2)
                option_chunk_book
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            3)
                option_upload_to_github
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            4)
                option_rewrite_chunks
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            5)
                # First analyze, then offer download
                local book_name=$(select_book_interactive)
                if [[ -n "$book_name" ]]; then
                    analyze_github_repo "$book_name"
                    read -p "Czy pobrać pliki z GitHub? [y/N]: " confirm
                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                        download_from_github "$book_name"
                    fi
                fi
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            6)
                option_merge_to_doc
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            7)
                option_auto_process_all
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            8)
                option_configure
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            9)
                option_show_status
                read -p "Naciśnij Enter aby kontynuować..."
                ;;
            0)
                echo ""
                log_info "Dziękujemy za korzystanie z Book Processing Manager!"
                echo ""
                exit 0
                ;;
            *)
                log_error "Nieprawidłowa opcja. Spróbuj ponownie."
                sleep 2
                ;;
        esac
    done
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    # Check if running with arguments
    if [[ $# -gt 0 ]]; then
        parse_arguments "$@"
        if [[ $? -eq 0 ]]; then
            exit 0
        fi
    fi
    
    # Run interactive mode
    run_interactive_mode
}

# Run main function
main "$@"
