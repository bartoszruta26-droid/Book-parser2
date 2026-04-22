#!/bin/bash

# =============================================================================
# Book Manager - Terminal GUI Script
# =============================================================================
# Konfiguracja GitHub - uzupełnij te zmienne przed użyciem
# =============================================================================

GITHUB_TOKEN=""           # Twój token dostępu do GitHub
GITHUB_USERNAME=""        # Twoja nazwa użytkownika GitHub
GITHUB_REPO_URL=""        # URL repozytorium GitHub (np. https://github.com/user/repo.git)
GITHUB_REPO_NAME=""       # Nazwa repozytorium (np. repo)

# =============================================================================
# Katalogi bazowe
# =============================================================================

BOOKS_DIR="/books"
TEMP_DIR="/tmp/book_manager_$$"

# =============================================================================
# Funkcje pomocnicze
# =============================================================================

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

mkdir -p "$TEMP_DIR"

# Sprawdzenie czy dialog/whiptail jest dostępny
if command -v dialog &> /dev/null; then
    DIALOG_CMD="dialog"
elif command -v whiptail &> /dev/null; then
    DIALOG_CMD="whiptail"
else
    echo "Błąd: Wymagany jest dialog lub whiptail. Zainstaluj: apt-get install dialog"
    exit 1
fi

# Funkcja do wyświetlania komunikatów
show_message() {
    $DIALOG_CMD --title "Informacja" --msgbox "$1" 10 60
}

show_error() {
    $DIALOG_CMD --title "Błąd" --msgbox "BŁĄD: $1" 10 60
}

# Funkcja do wyboru książki
select_book() {
    local books=()
    local i=0
    
    for dir in "$BOOKS_DIR"/*/; do
        if [ -d "$dir" ]; then
            book_name=$(basename "$dir")
            books+=("$book_name" "Katalog: $dir")
            ((i++))
        fi
    done
    
    if [ ${#books[@]} -eq 0 ]; then
        show_error "Brak książek w katalogu $BOOKS_DIR"
        return 1
    fi
    
    SELECTED_BOOK=$($DIALOG_CMD --title "Wybierz książkę" \
        --menu "Wybierz książkę z listy:" 15 60 4 "${books[@]}" 2>&1 >/dev/tty)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    BOOK_PATH="$BOOKS_DIR/$SELECTED_BOOK"
    show_message "Wybrano książkę: $SELECTED_BOOK\nŚcieżka: $BOOK_PATH"
    return 0
}

# Funkcja do ładowania książki (opcja 1)
load_book() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    $DIALOG_CMD --title "Ładowanie książki" --menubox "Wybierz plik książki z katalogu input:" 15 60 4 \
        "$(ls -1 "$BOOK_PATH/input/" 2>/dev/null | while read f; do echo \"$f\" \"Plik: $BOOK_PATH/input/$f\"; done)" \
        2>"$TEMP_DIR/load_result"
    
    if [ $? -eq 0 ]; then
        LOADED_FILE=$(cat "$TEMP_DIR/load_result")
        show_message "Załadowano plik: $LOADED_FILE"
        return 0
    fi
    return 1
}

# Funkcja do chunkowania książki (opcja 2)
chunk_book() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    local chunk_size=${1:-1000}
    
    $DIALOG_CMD --title "Chunkowanie" --inputbox "Podaj rozmiar chunka (liczba linii):" 8 60 "$chunk_size" \
        2>"$TEMP_DIR/chunk_size"
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    chunk_size=$(cat "$TEMP_DIR/chunk_size")
    
    if ! [[ "$chunk_size" =~ ^[0-9]+$ ]]; then
        show_error "Nieprawidłowy rozmiar chunka"
        return 1
    fi
    
    mkdir -p "$BOOK_PATH/chunk"
    
    local chunk_num=1
    for file in "$BOOK_PATH/input/"*; do
        if [ -f "$file" ]; then
            split -l "$chunk_size" "$file" "$BOOK_PATH/chunk/chunk_"
            
            # Zmień nazwy chunków na bardziej czytelne
            for chunk in "$BOOK_PATH/chunk/chunk_"*; do
                mv "$chunk" "$BOOK_PATH/chunk/${SELECTED_BOOK}_chunk_${chunk_num}.txt"
                ((chunk_num++))
            done
        fi
    done
    
    local chunk_count=$(ls -1 "$BOOK_PATH/chunk/"*.txt 2>/dev/null | wc -l)
    show_message "Utworzono $chunk_count chunków w katalogu:\n$BOOK_PATH/chunk"
    return 0
}

# Funkcja do wysyłania do GitHub (opcja 3)
send_to_github() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_URL" ]; then
        show_error "Skonfiguruj zmienne GitHub:\nGITHUB_TOKEN, GITHUB_USERNAME, GITHUB_REPO_URL"
        return 1
    fi
    
    # Klonowanie repozytorium
    local repo_dir="$TEMP_DIR/github_repo"
    rm -rf "$repo_dir"
    
    $DIALOG_CMD --title "GitHub" --infobox "Klonowanie repozytorium..." 5 60
    sleep 1
    
    git clone "$GITHUB_REPO_URL" "$repo_dir" 2>"$TEMP_DIR/git_error"
    if [ $? -ne 0 ]; then
        show_error "Błąd klonowania repozytorium:\n$(cat "$TEMP_DIR/git_error")"
        return 1
    fi
    
    # Kopiowanie chunków do repozytorium
    local target_dir="$repo_dir/books/$SELECTED_BOOK/chunk"
    mkdir -p "$target_dir"
    cp "$BOOK_PATH/chunk/"* "$target_dir/" 2>/dev/null
    
    # Konfiguracja Git
    cd "$repo_dir"
    git config user.email "bookmanager@local"
    git config user.name "Book Manager"
    
    # Dodawanie i commit
    git add .
    git commit -m "Dodano chunki książki: $SELECTED_BOOK" 2>"$TEMP_DIR/git_error"
    
    if [ $? -ne 0 ]; then
        # Jeśli nie ma zmian do commit
        if grep -q "nothing to commit" "$TEMP_DIR/git_error"; then
            show_message "Brak nowych zmian do wysłania"
            return 0
        fi
        show_error "Błąd commit:\n$(cat "$TEMP_DIR/git_error")"
        return 1
    fi
    
    # Push z tokenem
    local auth_url=$(echo "$GITHUB_REPO_URL" | sed "s|https://|https://$GITHUB_TOKEN@|")
    
    $DIALOG_CMD --title "GitHub" --infobox "Wysyłanie zmian do GitHub..." 5 60
    sleep 1
    
    git push "$auth_url" HEAD:main 2>"$TEMP_DIR/git_error" || \
    git push "$auth_url" HEAD:master 2>"$TEMP_DIR/git_error"
    
    if [ $? -ne 0 ]; then
        show_error "Błąd push:\n$(cat "$TEMP_DIR/git_error")"
        return 1
    fi
    
    show_message "Pomyślnie wysłano chunki do GitHub:\n$GITHUB_REPO_URL"
    return 0
}

# Funkcja do przepisywania chunków do formatu MD (opcja 4)
rewrite_to_md() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    mkdir -p "$BOOK_PATH/rewrite"
    
    local md_count=0
    for chunk in "$BOOK_PATH/chunk/"*.txt; do
        if [ -f "$chunk" ]; then
            local basename=$(basename "$chunk" .txt)
            local md_file="$BOOK_PATH/rewrite/${basename}.md"
            
            # Konwersja do Markdown z podstawowym formatowaniem
            {
                echo "# Rozdział: $basename"
                echo ""
                echo "---"
                echo ""
                cat "$chunk"
                echo ""
                echo "---"
                echo ""
                echo "*Źródło: $SELECTED_BOOK*"
            } > "$md_file"
            
            ((md_count++))
        fi
    done
    
    show_message "Przepisano $md_count plików do formatu .md w katalogu:\n$BOOK_PATH/rewrite"
    return 0
}

# Funkcja do analizy i pobierania z GitHub (opcja 5)
analyze_and_download() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO_URL" ]; then
        show_error "Skonfiguruj zmienne GitHub:\nGITHUB_TOKEN, GITHUB_USERNAME, GITHUB_REPO_URL"
        return 1
    fi
    
    # Klonowanie repozytorium
    local repo_dir="$TEMP_DIR/github_repo"
    rm -rf "$repo_dir"
    
    $DIALOG_CMD --title "GitHub" --infobox "Analiza i pobieranie z GitHub..." 5 60
    sleep 1
    
    git clone "$GITHUB_REPO_URL" "$repo_dir" 2>"$TEMP_DIR/git_error"
    if [ $? -ne 0 ]; then
        show_error "Błąd klonowania repozytorium:\n$(cat "$TEMP_DIR/git_error")"
        return 1
    fi
    
    # Analiza struktury repozytorium
    local repo_structure=$(find "$repo_dir" -type f -name "*.md" -o -name "*.txt" 2>/dev/null | head -20)
    
    $DIALOG_CMD --title "Struktura Repozytorium" --textbox <(echo "$repo_structure") 20 80
    
    # Pobieranie plików książki
    local source_dir="$repo_dir/books/$SELECTED_BOOK"
    local target_dir="$BOOK_PATH/rewrite"
    
    if [ -d "$source_dir" ]; then
        mkdir -p "$target_dir"
        cp -r "$source_dir/"* "$target_dir/" 2>/dev/null
        
        local file_count=$(find "$target_dir" -type f | wc -l)
        show_message "Pobrano pliki z GitHub do:\n$target_dir\nLiczba plików: $file_count"
    else
        show_error "Nie znaleziono katalogu książki w repozytorium:\nbooks/$SELECTED_BOOK"
        return 1
    fi
    
    return 0
}

# Funkcja do łączenia plików w jeden dokument DOC (opcja 6)
merge_to_doc() {
    if [ -z "$SELECTED_BOOK" ]; then
        select_book || return 1
    fi
    
    mkdir -p "$BOOK_PATH/finish"
    
    local output_file="$BOOK_PATH/finish/${SELECTED_BOOK}.doc"
    
    # Łączenie wszystkich plików z katalogu rewrite
    {
        echo "Książka: $SELECTED_BOOK"
        echo "Wygenerowano: $(date)"
        echo ""
        echo "=========================================="
        echo ""
        
        for file in "$BOOK_PATH/rewrite/"*.md "$BOOK_PATH/rewrite/"*.txt; do
            if [ -f "$file" ]; then
                echo "----------------------------------------"
                echo "Plik: $(basename "$file")"
                echo "----------------------------------------"
                cat "$file"
                echo ""
            fi
        done
    } > "$output_file"
    
    show_message "Utworzono plik DOC:\n$output_file"
    return 0
}

# =============================================================================
# Główne menu
# =============================================================================

main_menu() {
    while true; do
        $DIALOG_CMD --title "Book Manager" \
            --menu "Wybierz opcję:" 20 70 12 \
            "1" "Wybierz książkę i załaduj" \
            "2" "Chunkuj książkę" \
            "3" "Wyślij chunki do GitHub" \
            "4" "Przepisz chunki do formatu .md" \
            "5" "Analizuj GitHub i pobierz książkę" \
            "6" "Połącz pliki i utwórz .doc" \
            "Q" "Wyjście" \
            2>"$TEMP_DIR/menu_result"
        
        if [ $? -ne 0 ]; then
            clear
            echo "Koniec programu."
            exit 0
        fi
        
        choice=$(cat "$TEMP_DIR/menu_result")
        
        case $choice in
            1)
                load_book
                ;;
            2)
                chunk_book
                ;;
            3)
                send_to_github
                ;;
            4)
                rewrite_to_md
                ;;
            5)
                analyze_and_download
                ;;
            6)
                merge_to_doc
                ;;
            [Qq])
                clear
                echo "Koniec programu."
                exit 0
                ;;
        esac
    done
}

# =============================================================================
# Uruchomienie programu
# =============================================================================

main_menu
