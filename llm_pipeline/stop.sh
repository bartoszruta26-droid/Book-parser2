#!/bin/bash
# STOP SCRIPT - Zatrzymuje pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"

echo "=========================================="
echo "Zatrzymywanie LLM Pipeline"
echo "=========================================="

if [[ ! -f "${LOGS_DIR}/pipeline.pid" ]]; then
    echo "Pipeline NIE jest uruchomiony (brak PID)"
    exit 0
fi

PID=$(cat "${LOGS_DIR}/pipeline.pid")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Pipeline NIE dziala (proces nie istnieje)"
    rm -f "${LOGS_DIR}/pipeline.pid"
    exit 0
fi

echo "Zatrzymywanie procesu $PID..."
kill -TERM "$PID" 2>/dev/null || true

for i in {1..30}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "Pipeline zatrzymany"
        rm -f "${LOGS_DIR}/pipeline.pid"
        exit 0
    fi
    sleep 1
done

kill -9 "$PID" 2>/dev/null || true
rm -f "${LOGS_DIR}/pipeline.pid"
echo "Pipeline ZATRZYMANI"
