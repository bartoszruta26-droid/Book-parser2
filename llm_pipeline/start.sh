#!/bin/bash
# START SCRIPT - Uruchamia pipeline w tle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"

mkdir -p "$LOGS_DIR"

echo "=========================================="
echo "Uruchamianie LLM Pipeline"
echo "=========================================="

if [[ -f "${LOGS_DIR}/pipeline.pid" ]]; then
    PID=$(cat "${LOGS_DIR}/pipeline.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Pipeline JUZ DZIALA (PID: $PID)"
        exit 0
    else
        rm -f "${LOGS_DIR}/pipeline.pid"
    fi
fi

echo "Sprawdzanie endpointow LLM..."
curl -s --connect-timeout 3 http://localhost:8000/v1/models &>/dev/null && echo "OK: Port 8000" || echo "WARN: Port 8000 niedostepny"
curl -s --connect-timeout 3 http://localhost:8001/v1/models &>/dev/null && echo "OK: Port 8001" || echo "WARN: Port 8001 niedostepny"
echo ""

nohup "${SCRIPT_DIR}/pipeline.sh" run > "${LOGS_DIR}/pipeline.out" 2>&1 &
PID=$!
echo "$PID" > "${LOGS_DIR}/pipeline.pid"

echo "=========================================="
echo "Pipeline URUCHOMIONY (PID: $PID)"
echo "=========================================="
echo ""
echo "Logi: tail -f ${LOGS_DIR}/pipeline.log"
echo "Status: ./status.sh"
echo "Stop: ./stop.sh"
echo "Web UI: ./webui.sh"
