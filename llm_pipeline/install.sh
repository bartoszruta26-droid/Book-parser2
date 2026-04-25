#!/bin/bash
# INSTALL SCRIPT - Instaluje zaleznosci

set -euo pipefail

echo "=========================================="
echo "Instalacja zaleznosci LLM Pipeline"
echo "=========================================="

apt-get update -qq || true

echo "[1/3] Podstawowe narzedzia..."
apt-get install -y -qq curl wget unzip zip sed grep gawk 2>/dev/null || true

echo "[2/3] Konwertery dokumentow..."
apt-get install -y -qq pandoc poppler-utils antiword wv unrtf 2>/dev/null || true

echo "[3/3] Gnumeric (arkusze)..."
apt-get install -y -qq gnumeric 2>/dev/null || true

echo ""
echo "Sprawdzanie:"
command -v curl && echo "  OK: curl" || echo "  BRAK: curl"
command -v pandoc && echo "  OK: pandoc" || echo "  BRAK: pandoc"
command -v pdftotext && echo "  OK: pdftotext" || echo "  BRAK: pdftotext"
command -v antiword && echo "  OK: antiword" || echo "  BRAK: antiword"

echo ""
echo "=========================================="
echo "Instalacja zakonczona!"
echo ""
echo "Nastepne kroki:"
echo "1. Uruchom vLLM serwery:"
echo "   vllm serve Qwen/Qwen3.6-35B-A3B --port 8000"
echo "   vllm serve Qwen/Qwen-Coder --port 8001"
echo ""
echo "2. ./start.sh"
echo "=========================================="
