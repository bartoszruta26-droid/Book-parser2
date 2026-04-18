# Makefile for Document Chunker

CXX = g++
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra
TARGET = chunker
SRC = src/chunker.cpp

.PHONY: all clean test install help

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
	rm -rf chunk/*
	rm -rf logs/*

test: $(TARGET)
	@echo "Tworzenie plikow testowych..."
	mkdir -p input
	echo "# Rozdzial 1" > input/test1.txt
	./$(TARGET) -v

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/

help:
	@echo "Dostepne cele:"
	@echo "  all     - Kompilacja programu (domyslny)"
	@echo "  clean   - Usuwa pliki wynikowe i czysci katalogi"
	@echo "  test    - Kompiluje i uruchamia testy"
	@echo "  install - Instaluje program w /usr/local/bin"
	@echo "  help    - Wyswietla te pomoc"
