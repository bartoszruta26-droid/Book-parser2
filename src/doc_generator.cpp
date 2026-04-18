#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <filesystem>
#include <algorithm>
#include <ctime>
#include <iomanip>

namespace fs = std::filesystem;

// Struktura metadanych dokumentu
struct DocumentMetadata {
    std::string title;
    std::string author;
    std::string date;
    std::string language;
    int total_chunks;
    int total_tokens;
};

// Klasa do obsługi logowania
class DocGeneratorLogger {
private:
    std::ofstream log_file;
    bool verbose;

public:
    DocGeneratorLogger(const std::string& log_path, bool verbose_mode = false) : verbose(verbose_mode) {
        fs::create_directories(fs::path(log_path).parent_path());
        log_file.open(log_path, std::ios::app);
        if (log_file.is_open()) {
            log("=== Nowa sesja generowania dokumentu DOC ===");
        }
    }

    void log(const std::string& message, bool always = false) {
        auto now = std::chrono::system_clock::now();
        auto time_t_now = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&time_t_now), "%Y-%m-%d %H:%M:%S");

        std::string log_entry = "[" + ss.str() + "] " + message;

        if (always || verbose) {
            std::cout << log_entry << std::endl;
        }

        if (log_file.is_open()) {
            log_file << log_entry << std::endl;
            log_file.flush();
        }
    }

    ~DocGeneratorLogger() {
        if (log_file.is_open()) {
            log_file.close();
        }
    }
};

// Klasa do parsowania JSON (uproszczona)
class SimpleJSONParser {
public:
    static std::string extractString(const std::string& json, const std::string& key) {
        std::string search_key = "\"" + key + "\"";
        size_t pos = json.find(search_key);
        if (pos == std::string::npos) return "";
        
        pos = json.find(":", pos);
        if (pos == std::string::npos) return "";
        
        pos = json.find("\"", pos);
        if (pos == std::string::npos) return "";
        
        size_t end_pos = json.find("\"", pos + 1);
        if (end_pos == std::string::npos) return "";
        
        return json.substr(pos + 1, end_pos - pos - 1);
    }

    static int extractInt(const std::string& json, const std::string& key) {
        std::string search_key = "\"" + key + "\"";
        size_t pos = json.find(search_key);
        if (pos == std::string::npos) return 0;
        
        pos = json.find(":", pos);
        if (pos == std::string::npos) return 0;
        
        size_t start = pos + 1;
        while (start < json.length() && (json[start] == ' ' || json[start] == '\t')) {
            start++;
        }
        
        size_t end = start;
        while (end < json.length() && std::isdigit(json[end])) {
            end++;
        }
        
        if (start == end) return 0;
        return std::stoi(json.substr(start, end - start));
    }
};

// Klasa generująca dokument DOC
class DocGenerator {
private:
    std::string input_dir;
    std::string output_file;
    DocumentMetadata metadata;
    DocGeneratorLogger* logger;
    bool verbose;

public:
    DocGenerator(const std::string& input, const std::string& output, bool verbose_mode = false) 
        : input_dir(input), output_file(output), verbose(verbose_mode) {
        logger = new DocGeneratorLogger("./logs/doc_generator.log", verbose_mode);
        metadata.total_chunks = 0;
        metadata.total_tokens = 0;
        metadata.language = "pl";
        metadata.date = getCurrentDate();
    }

    ~DocGenerator() {
        delete logger;
    }

    std::string getCurrentDate() {
        auto now = std::chrono::system_clock::now();
        auto time_t_now = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&time_t_now), "%Y-%m-%d");
        return ss.str();
    }

    bool loadChunks() {
        logger->log("Ładowanie chunków z katalogu: " + input_dir);
        
        if (!fs::exists(input_dir)) {
            logger->log("Błąd: Katalog nie istnieje: " + input_dir, true);
            return false;
        }

        std::vector<std::string> chunk_files;
        for (const auto& entry : fs::directory_iterator(input_dir)) {
            if (entry.path().extension() == ".json") {
                chunk_files.push_back(entry.path().string());
            }
        }

        if (chunk_files.empty()) {
            logger->log("Błąd: Brak plików JSON w katalogu", true);
            return false;
        }

        // Sortowanie plików
        std::sort(chunk_files.begin(), chunk_files.end());

        metadata.total_chunks = chunk_files.size();
        logger->log("Znaleziono " + std::to_string(metadata.total_chunks) + " chunków");

        // Ładowanie metadanych z pierwszego chunka
        std::ifstream first_chunk(chunk_files[0]);
        if (first_chunk.is_open()) {
            std::stringstream buffer;
            buffer << first_chunk.rdbuf();
            std::string json_content = buffer.str();
            
            metadata.title = SimpleJSONParser::extractString(json_content, "title");
            metadata.author = SimpleJSONParser::extractString(json_content, "author");
            metadata.language = SimpleJSONParser::extractString(json_content, "language");
            
            if (metadata.title.empty()) {
                metadata.title = "Dokument Wygenerowany";
            }
            if (metadata.author.empty()) {
                metadata.author = "Nieznany Autor";
            }
        }

        // Liczenie tokenów
        for (const auto& file : chunk_files) {
            std::ifstream chunk(file);
            if (chunk.is_open()) {
                std::stringstream buffer;
                buffer << chunk.rdbuf();
                std::string json_content = buffer.str();
                int tokens = SimpleJSONParser::extractInt(json_content, "token_count");
                metadata.total_tokens += tokens;
            }
        }

        logger->log("Łączna liczba tokenów: " + std::to_string(metadata.total_tokens));
        return true;
    }

    bool generateDOC() {
        logger->log("Generowanie dokumentu DOC: " + output_file);

        // Tworzenie katalogu wyjściowego
        fs::create_directories(fs::path(output_file).parent_path());

        std::ofstream doc(output_file, std::ios::binary);
        if (!doc.is_open()) {
            logger->log("Błąd: Nie można utworzyć pliku: " + output_file, true);
            return false;
        }

        // Generowanie prostego formatu DOC (RTF jako alternatywa)
        // Format RTF jest bardziej kompatybilny i łatwiejszy do wygenerowania
        
        std::string rtf_content = generateRTFContent();
        doc.write(rtf_content.c_str(), rtf_content.length());
        doc.close();

        logger->log("Dokument wygenerowany sukcesnie", true);
        return true;
    }

    std::string generateRTFContent() {
        std::stringstream rtf;
        
        // Nagłówek RTF
        rtf << "{\\rtf1\\ansi\\ansicpg1250\\deff0\n";
        rtf << "{\\fonttbl\n";
        rtf << "{\\f0\\fswiss\\fcharset238 Arial;}\n";
        rtf << "{\\f1\\froman\\fcharset238 Times New Roman;}\n";
        rtf << "}\n";
        rtf << "{\\colortbl ;\\red0\\green0\\blue0;\\red0\\green0\\blue128;}\n";
        rtf << "\\viewkind4\\uc1\\pard\\f0\\fs24\n";
        rtf << "\\lang1045\n\n";

        // Strona tytułowa
        rtf << "\\pard\\qc\\sb200\\sa200\n";
        rtf << "\\b\\fs48 " << escapeRTF(metadata.title) << "\\b0\\fs24\\par\n";
        rtf << "\\sb400\\par\n";
        rtf << "\\fs28 Autor: " << escapeRTF(metadata.author) << "\\par\n";
        rtf << "Data: " << escapeRTF(metadata.date) << "\\par\n";
        rtf << "Język: " << escapeRTF(metadata.language) << "\\par\n";
        rtf << "Liczba chunków: " << std::to_string(metadata.total_chunks) << "\\par\n";
        rtf << "Szacowana liczba tokenów: " << std::to_string(metadata.total_tokens) << "\\par\n";
        rtf << "\\page\n\n";

        // Spis treści
        rtf << "\\pard\\qc\\b\\fs32 Spis Treści\\b0\\fs24\\par\n";
        rtf << "\\sb200\\sa200\\par\n";
        rtf << "\\pard\\li400\n";
        
        int chunk_num = 1;
        for (const auto& entry : fs::directory_iterator(input_dir)) {
            if (entry.path().extension() == ".json") {
                std::ifstream chunk(entry.path().string());
                if (chunk.is_open()) {
                    std::stringstream buffer;
                    buffer << chunk.rdbuf();
                    std::string json_content = buffer.str();
                    
                    std::string title = SimpleJSONParser::extractString(json_content, "title");
                    std::string subtitle = SimpleJSONParser::extractString(json_content, "subtitle");
                    
                    if (!title.empty()) {
                        rtf << "\\pard\\li400 " << std::to_string(chunk_num) << ". ";
                        rtf << "\\b " << escapeRTF(title) << "\\b0";
                        if (!subtitle.empty()) {
                            rtf << " - " << escapeRTF(subtitle);
                        }
                        rtf << "\\par\n";
                    }
                    chunk_num++;
                }
            }
        }
        rtf << "\\page\n\n";

        // Zawartość chunków
        rtf << "\\pard\\qc\\b\\fs32 Zawartość Dokumentu\\b0\\fs24\\par\n";
        rtf << "\\sb200\\sa200\\par\n";

        chunk_num = 1;
        for (const auto& entry : fs::directory_iterator(input_dir)) {
            if (entry.path().extension() == ".json") {
                std::ifstream chunk(entry.path().string());
                if (chunk.is_open()) {
                    std::stringstream buffer;
                    buffer << chunk.rdbuf();
                    std::string json_content = buffer.str();
                    
                    std::string title = SimpleJSONParser::extractString(json_content, "title");
                    std::string content = SimpleJSONParser::extractString(json_content, "content");
                    std::string subtitle = SimpleJSONParser::extractString(json_content, "subtitle");
                    
                    rtf << "\\pard\\sb200\\sa100\\b\\fs28 Rozdział " << std::to_string(chunk_num);
                    if (!title.empty()) {
                        rtf << ": " << escapeRTF(title);
                    }
                    rtf << "\\b0\\fs24\\par\n";
                    
                    if (!subtitle.empty()) {
                        rtf << "\\i " << escapeRTF(subtitle) << "\\i0\\par\n";
                    }
                    
                    rtf << "\\sb100\\sa100\\par\n";
                    
                    // Dodawanie treści (proste formatowanie)
                    if (!content.empty()) {
                        rtf << escapeRTF(content) << "\\par\n";
                    }
                    
                    rtf << "\\page\n\n";
                    chunk_num++;
                }
            }
        }

        // Stopka
        rtf << "\\pard\\qc\\sb200\\sa200\n";
        rtf << "\\fs18\\i Dokument wygenerowany automatycznie przez DocGenerator\\i0\\par\n";
        rtf << "\\fs18 Data generacji: " << getCurrentDate() << "\\par\n";
        
        rtf << "}";
        
        return rtf.str();
    }

    std::string escapeRTF(const std::string& text) {
        std::string result;
        for (char c : text) {
            switch (c) {
                case '\\': result += "\\\\"; break;
                case '{': result += "\\{"; break;
                case '}': result += "\\}"; break;
                default:
                    if (static_cast<unsigned char>(c) > 127) {
                        // Znaki Unicode - konwersja na format RTF
                        std::stringstream ss;
                        ss << "\\'" << std::hex << static_cast<unsigned char>(c);
                        result += ss.str();
                    } else {
                        result += c;
                    }
                    break;
            }
        }
        return result;
    }

    void printSummary() {
        std::cout << "\n========================================" << std::endl;
        std::cout << "  PODSUMOWANIE GENEROWANIA DOKUMENTU  " << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "\n";
        std::cout << "  Tytuł: " << metadata.title << std::endl;
        std::cout << "  Autor: " << metadata.author << std::endl;
        std::cout << "  Data: " << metadata.date << std::endl;
        std::cout << "  Język: " << metadata.language << std::endl;
        std::cout << "  Liczba chunków: " << metadata.total_chunks << std::endl;
        std::cout << "  Liczba tokenów: " << metadata.total_tokens << std::endl;
        std::cout << "  Plik wyjściowy: " << output_file << std::endl;
        std::cout << "\n========================================" << std::endl;
    }
};

void printHelp(const char* program_name) {
    std::cout << "=== DocGenerator - Generator Dokumentów DOC (Krok 8) ===" << std::endl;
    std::cout << std::endl;
    std::cout << "Użycie: " << program_name << " [opcje]" << std::endl;
    std::cout << std::endl;
    std::cout << "Opcje:" << std::endl;
    std::cout << "  -i, --input DIR       Katalog z chunkami (domyślnie: ./chunk)" << std::endl;
    std::cout << "  -o, --output FILE     Plik wyjściowy DOC/RTF (domyślnie: ./finish/book.doc)" << std::endl;
    std::cout << "  -t, --title TITLE     Tytuł dokumentu" << std::endl;
    std::cout << "  -a, --author AUTHOR   Autor dokumentu" << std::endl;
    std::cout << "  -l, --lang LANG       Język dokumentu (domyślnie: pl)" << std::endl;
    std::cout << "  -v, --verbose         Tryb szczegółowy" << std::endl;
    std::cout << "  -h, --help            Wyświetl pomoc" << std::endl;
    std::cout << std::endl;
    std::cout << "Przykłady:" << std::endl;
    std::cout << "  " << program_name << " -i ./chunk -o ./finish/book.doc" << std::endl;
    std::cout << "  " << program_name << " -i ./chunk -o ./finish/book.rtf --title \"Moja Książka\"" << std::endl;
    std::cout << std::endl;
}

int main(int argc, char* argv[]) {
    std::string input_dir = "./chunk";
    std::string output_file = "./finish/book.doc";
    std::string custom_title = "";
    std::string custom_author = "";
    std::string language = "pl";
    bool verbose = false;

    // Parsowanie argumentów
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        
        if ((arg == "-i" || arg == "--input") && i + 1 < argc) {
            input_dir = argv[++i];
        }
        else if ((arg == "-o" || arg == "--output") && i + 1 < argc) {
            output_file = argv[++i];
        }
        else if ((arg == "-t" || arg == "--title") && i + 1 < argc) {
            custom_title = argv[++i];
        }
        else if ((arg == "-a" || arg == "--author") && i + 1 < argc) {
            custom_author = argv[++i];
        }
        else if ((arg == "-l" || arg == "--lang") && i + 1 < argc) {
            language = argv[++i];
        }
        else if (arg == "-v" || arg == "--verbose") {
            verbose = true;
        }
        else if (arg == "-h" || arg == "--help") {
            printHelp(argv[0]);
            return 0;
        }
        else {
            std::cerr << "Nieznana opcja: " << arg << std::endl;
            printHelp(argv[0]);
            return 1;
        }
    }

    std::cout << "\033[0;34m========================================\033[0m" << std::endl;
    std::cout << "\033[0;34m  Krok 8: Generowanie Dokumentu DOC     \033[0m" << std::endl;
    std::cout << "\033[0;34m========================================\033[0m" << std::endl;
    std::cout << std::endl;

    DocGenerator generator(input_dir, output_file, verbose);
    
    if (!generator.loadChunks()) {
        std::cerr << "\033[0;31m✗ Błąd ładowania chunków\033[0m" << std::endl;
        return 1;
    }

    if (!generator.generateDOC()) {
        std::cerr << "\033[0;31m✗ Błąd generowania dokumentu\033[0m" << std::endl;
        return 1;
    }

    generator.printSummary();

    std::cout << "\n\033[0;32m✓ Dokument wygenerowany sukcesnie!\033[0m" << std::endl;
    std::cout << "\033[1;33mNastępne kroki:\033[0m" << std::endl;
    std::cout << "  1. Otwórz plik w Microsoft Word lub LibreOffice" << std::endl;
    std::cout << "  2. Zweryfikuj formatowanie i strukturę" << std::endl;
    std::cout << "  3. W razie potrzeby przekonwertuj do .docx" << std::endl;
    std::cout << std::endl;

    return 0;
}
