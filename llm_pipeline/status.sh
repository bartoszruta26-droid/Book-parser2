#!/bin/bash
# STATUS SCRIPT - Pokazuje status systemu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"
INPUT_DIR="${SCRIPT_DIR}/input"
FINISH_DIR="${SCRIPT_DIR}/finish"
CHUNK_DIR="${SCRIPT_DIR}/chunk"

echo "=========================================="
echo "STATUS LLM PIPELINE"
echo "=========================================="
echo ""

echo "PROCES:"
if [[ -f "${LOGS_DIR}/pipeline.pid" ]] && kill -0 "$(cat ${LOGS_DIR}/pipeline.pid 2>/dev/null)" 2>/dev/null; then
    echo "  URUCHOMIONY (PID: $(cat ${LOGS_DIR}/pipeline.pid))"
else
    echo "  ZATRZYMANI"
fi
echo ""

echo "ENDPOINTY LLM:"
curl -s --connect-timeout 2 http://localhost:8000/v1/models &>/dev/null && echo "  Port 8000 (Qwen3.6-35B-A3B): OK" || echo "  Port 8000 (Qwen3.6-35B-A3B): NIEDOSTEPNY"
curl -s --connect-timeout 2 http://localhost:8001/v1/models &>/dev/null && echo "  Port 8001 (Qwen-Coder): OK" || echo "  Port 8001 (Qwen-Coder): NIEDOSTEPNY"
echo ""

echo "PLIKI:"
echo "  Wejsciowe (input/):     $(find "$INPUT_DIR" -type f 2>/dev/null | wc -l)"
echo "  Wyjsciowe (finish/):    $(find "$FINISH_DIR" -type f -name '*.txt' 2>/dev/null | wc -l)"
echo "  Chunki (chunk/):        $(find "$CHUNK_DIR" -type d -name '20*' 2>/dev/null | wc -l)"
echo ""

echo "OSTATNIE LOGI:"
tail -10 "${LOGS_DIR}/pipeline.log" 2>/dev/null || echo "  Brak logow"
echo ""

echo "=========================================="
echo "Web UI: ./webui.sh"
echo "Start: ./start.sh | Stop: ./stop.sh"
echo "=========================================="
