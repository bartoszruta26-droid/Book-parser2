#!/bin/bash
# Krok 6: Zapis wyników - Skrypt generujący podsumowania w formacie .txt i .md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Wartości domyślne
INPUT_DIR="./chunk"
OUTPUT_DIR="./output"
SUMMARY_FORMAT="both"  # txt, md, both
INCLUDE_METADATA=true
GENERATE_TOC=true

print_help() {
    echo "=== Skrypt Zapisu Wyników (Krok 6) ==="
    echo ""
    echo "Użycie: $0 [opcje]"
    echo ""
    echo "Opcje:"
    echo "  -i, --input DIR       Katalog z chunkami (domyślnie: ./chunk)"
    echo "  -o, --output DIR      Katalog wyjściowy na podsumowania (domyślnie: ./output)"
    echo "  -f, --format FORMAT   Format outputu: txt, md, both (domyślnie: both)"
    echo "  --no-metadata         Nie dołączaj metadanych"
    echo "  --no-toc              Nie generuj spisu treści"
    echo "  -h, --help            Wyświetl pomoc"
    echo ""
    echo "Przykłady:"
    echo "  $0 -i ./chunk -o ./output"
    echo "  $0 -f md --no-metadata"
}

# Parsowanie argumentów
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -f|--format)
            SUMMARY_FORMAT="$2"
            shift 2
            ;;
        --no-metadata)
            INCLUDE_METADATA=false
            shift
            ;;
        --no-toc)
            GENERATE_TOC=false
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Nieznana opcja: $1${NC}"
            print_help
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Krok 6: Zapis Wyników                ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Tworzenie katalogu wyjściowego
mkdir -p "$OUTPUT_DIR"

# Sprawdzenie czy katalog z chunkami istnieje
if [[ ! -d "$INPUT_DIR" ]]; then
    echo -e "${RED}✗ Katalog z chunkami nie istnieje: $INPUT_DIR${NC}"
    exit 1
fi

# Liczenie chunków
CHUNK_COUNT=$(ls -1 "$INPUT_DIR"/*.json 2>/dev/null | wc -l || echo "0")

if [[ "$CHUNK_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}⊘ Brak chunków w katalogu $INPUT_DIR${NC}"
    exit 0
fi

echo -e "${YELLOW}Znaleziono $CHUNK_COUNT chunków${NC}"
echo ""

# Generowanie timestampu
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

# Funkcja generująca podsumowanie w formacie TXT
generate_txt_summary() {
    local output_file="$1"
    
    echo -e "${YELLOW}Generowanie podsumowania TXT...${NC}"
    
    {
        echo "=============================================="
        echo "  PODSUMOWANIE PRZETWARZANIA DOKUMENTÓW"
        echo "=============================================="
        echo ""
        echo "Data generacji: $DATE_HUMAN"
        echo "Liczba przetworzonych chunków: $CHUNK_COUNT"
        echo "Katalog źródłowy: $(readlink -f "$INPUT_DIR")"
        echo ""
        
        if [[ "$INCLUDE_METADATA" == true ]]; then
            echo "----------------------------------------------"
            echo "  METADANE"
            echo "----------------------------------------------"
            echo ""
            
            # Analiza plików źródłowych
            declare -A source_files
            total_tokens=0
            
            for chunk_file in "$INPUT_DIR"/*.json; do
                if [[ -f "$chunk_file" ]]; then
                    # Ekstrakcja nazwy pliku źródłowego z JSON (uproszczona)
                    source=$(grep -o '"source_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$chunk_file" | head -1 | cut -d'"' -f4)
                    if [[ -n "$source" ]]; then
                        source_files["$source"]=$((${source_files["$source"]:-0} + 1))
                    fi
                    
                    # Ekstrakcja liczby tokenów
                    tokens=$(grep -o '"token_count"[[:space:]]*:[[:space:]]*[0-9]*' "$chunk_file" | head -1 | grep -o '[0-9]*')
                    if [[ -n "$tokens" ]]; then
                        total_tokens=$((total_tokens + tokens))
                    fi
                fi
            done
            
            echo "Pliki źródłowe:"
            for src in "${!source_files[@]}"; do
                echo "  - $src: ${source_files[$src]} chunków"
            done
            echo ""
            echo "Szacunkowa łączna liczba tokenów: $total_tokens"
            echo ""
        fi
        
        if [[ "$GENERATE_TOC" == true ]]; then
            echo "----------------------------------------------"
            echo "  SPIS TREŚCI (lista chunków)"
            echo "----------------------------------------------"
            echo ""
            
            idx=1
            for chunk_file in "$INPUT_DIR"/*.json; do
                if [[ -f "$chunk_file" ]]; then
                    filename=$(basename "$chunk_file")
                    title=$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$chunk_file" | head -1 | cut -d'"' -f4)
                    
                    if [[ -n "$title" ]]; then
                        printf "  %3d. [%s] %s\n" "$idx" "$filename" "$title"
                    else
                        printf "  %3d. %s\n" "$idx" "$filename"
                    fi
                    idx=$((idx + 1))
                fi
            done
            echo ""
        fi
        
        echo "----------------------------------------------"
        echo "  STATUS PRZETWARZANIA"
        echo "----------------------------------------------"
        echo ""
        echo "  ✓ Chunking zakończony sukcesem"
        echo "  ✓ Wszystkie chunki zapisane w formacie JSON"
        echo "  ✓ Wygenerowano podsumowanie"
        echo ""
        echo "=============================================="
        echo "  KONIEC PODSUMOWANIA"
        echo "=============================================="
        
    } > "$output_file"
    
    echo -e "${GREEN}✓ Zapisano: $output_file${NC}"
}

# Funkcja generująca podsumowanie w formacie Markdown
generate_md_summary() {
    local output_file="$1"
    
    echo -e "${YELLOW}Generowanie podsumowania MD...${NC}"
    
    {
        echo "# Podsumowanie Przetwarzania Dokumentów"
        echo ""
        echo "**Data generacji:** $DATE_HUMAN"
        echo ""
        echo "**Liczba przetworzonych chunków:** $CHUNK_COUNT"
        echo ""
        local abs_path=$(readlink -f "$INPUT_DIR")
        echo "**Katalog źródłowy:** \`$abs_path\`"
        echo ""
        
        if [[ "$INCLUDE_METADATA" == true ]]; then
            echo "## Metadane"
            echo ""
            
            # Analiza plików źródłowych
            declare -A source_files
            total_tokens=0
            
            for chunk_file in "$INPUT_DIR"/*.json; do
                if [[ -f "$chunk_file" ]]; then
                    source=$(grep -o '"source_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$chunk_file" | head -1 | cut -d'"' -f4)
                    if [[ -n "$source" ]]; then
                        source_files["$source"]=$((${source_files["$source"]:-0} + 1))
                    fi
                    
                    tokens=$(grep -o '"token_count"[[:space:]]*:[[:space:]]*[0-9]*' "$chunk_file" | head -1 | grep -o '[0-9]*')
                    if [[ -n "$tokens" ]]; then
                        total_tokens=$((total_tokens + tokens))
                    fi
                fi
            done
            
            echo "### Pliki źródłowe"
            echo ""
            echo "| Plik | Liczba chunków |"
            echo "|------|----------------|"
            for src in "${!source_files[@]}"; do
                echo "| $src | ${source_files[$src]} |"
            done
            echo ""
            echo "**Szacunkowa łączna liczba tokenów:** $total_tokens"
            echo ""
        fi
        
        if [[ "$GENERATE_TOC" == true ]]; then
            echo "## Spis Treści"
            echo ""
            
            idx=1
            for chunk_file in "$INPUT_DIR"/*.json; do
                if [[ -f "$chunk_file" ]]; then
                    filename=$(basename "$chunk_file")
                    title=$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$chunk_file" | head -1 | cut -d'"' -f4)
                    
                    if [[ -n "$title" ]]; then
                        echo "$idx. **$title** (\`$filename\`)"
                    else
                        echo "$idx. \`$filename\`"
                    fi
                    idx=$((idx + 1))
                fi
            done
            echo ""
        fi
        
        echo "## Status Przetwarzania"
        echo ""
        echo "- [x] Chunking zakończony sukcesem"
        echo "- [x] Wszystkie chunki zapisane w formacie JSON"
        echo "- [x] Wygenerowano podsumowanie"
        echo ""
        echo "---"
        echo ""
        echo "*Generowane automatycznie przez save_results.sh*"
        
    } > "$output_file"
    
    echo -e "${GREEN}✓ Zapisano: $output_file${NC}"
}

# Funkcja eksportująca do HTML (opcjonalnie)
export_to_html() {
    local md_file="$1"
    local html_file="$2"
    
    if command -v pandoc &> /dev/null; then
        echo -e "${YELLOW}Eksportowanie do HTML...${NC}"
        pandoc "$md_file" -o "$html_file" 2>/dev/null && \
            echo -e "${GREEN}✓ Zapisano: $html_file${NC}" || \
            echo -e "${YELLOW}⊘ Eksport HTML nie powiódł się${NC}"
    else
        echo -e "${YELLOW}⊘ pandoc nie zainstalowany - pomijam eksport HTML${NC}"
    fi
}

# Funkcja eksportująca do PDF (opcjonalnie)
export_to_pdf() {
    local md_file="$1"
    local pdf_file="$2"
    
    if command -v pandoc &> /dev/null; then
        echo -e "${YELLOW}Eksportowanie do PDF...${NC}"
        pandoc "$md_file" -o "$pdf_file" 2>/dev/null && \
            echo -e "${GREEN}✓ Zapisano: $pdf_file${NC}" || \
            echo -e "${YELLOW}⊘ Eksport PDF nie powiódł się${NC}"
    else
        echo -e "${YELLOW}⊘ pandoc nie zainstalowany - pomijam eksport PDF${NC}"
    fi
}

# Główne wywołanie
case "$SUMMARY_FORMAT" in
    txt)
        generate_txt_summary "$OUTPUT_DIR/summary_${TIMESTAMP}.txt"
        ;;
    md)
        generate_md_summary "$OUTPUT_DIR/summary_${TIMESTAMP}.md"
        ;;
    both)
        generate_txt_summary "$OUTPUT_DIR/summary_${TIMESTAMP}.txt"
        generate_md_summary "$OUTPUT_DIR/summary_${TIMESTAMP}.md"
        ;;
    *)
        echo -e "${RED}✗ Nieznany format: $SUMMARY_FORMAT${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  Krok 6 zakończony sukcesnie!         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Wygenerowane pliki:${NC}"
ls -la "$OUTPUT_DIR"/summary_${TIMESTAMP}.* 2>/dev/null || echo "  Brak plików"
echo ""
