#!/bin/bash
# WEB UI - Interfejs webowy w czystym Bash, port 8080

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"
INPUT_DIR="${SCRIPT_DIR}/input"
FINISH_DIR="${SCRIPT_DIR}/finish"
PORT="${WEBUI_PORT:-8080}"

generate_html() {
    local status="ZATRZYMANI"
    local status_class="stopped"
    local pid="N/A"
    
    if [[ -f "${LOGS_DIR}/pipeline.pid" ]] && kill -0 "$(cat ${LOGS_DIR}/pipeline.pid 2>/dev/null)" 2>/dev/null; then
        status="URUCHOMIONY"
        status_class="running"
        pid=$(cat "${LOGS_DIR}/pipeline.pid")
    fi
    
    local input_count=$(find "$INPUT_DIR" -type f 2>/dev/null | wc -l)
    local finish_count=$(find "$FINISH_DIR" -type f -name '*.txt' 2>/dev/null | wc -l)
    
    local e8000="X"; curl -s --connect-timeout 1 http://localhost:8000/v1/models &>/dev/null && e8000="OK"
    local e8001="X"; curl -s --connect-timeout 1 http://localhost:8001/v1/models &>/dev/null && e8001="OK"
    
    local logs=""
    [[ -f "${LOGS_DIR}/pipeline.log" ]] && logs=$(tail -30 "${LOGS_DIR}/pipeline.log" 2>/dev/null | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g')
    
    cat << HTMLEOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>LLM Pipeline</title>
<meta http-equiv="refresh" content="30">
<style>body{font-family:sans-serif;background:#1a1a2e;color:#eee;padding:20px}
.card{background:rgba(255,255,255,0.05);border-radius:10px;padding:20px;margin:10px 0}
h1{color:#00d9ff}.running{color:#00b894}.stopped{color:#636e72}
.btn{display:inline-block;padding:10px 20px;margin:5px;border-radius:5px;text-decoration:none;color:white}
.start{background:#00b894}.stop{background:#e74c3c}.refresh{background:#3498db}
.logs{background:#1e1e1e;padding:10px;border-radius:5px;max-height:300px;overflow:auto;font-size:12px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:15px}</style></head>
<body><h1>LLM Pipeline Dashboard</h1>
<div class="grid">
<div class="card"><h2>Status</h2><p class="$status_class"><b>$status</b></p>
<p>PID: $pid</p><p>Pliki wejsciowe: $input_count</p><p>Pliki wyjsciowe: $finish_count</p></div>
<div class="card"><h2>Endpointy</h2><p>Port 8000 (Qwen3.6): $e8000</p><p>Port 8001 (Coder): $e8001</p></div>
<div class="card"><h2>Sterowanie</h2>
<a href="/start" class="btn start">Start</a>
<a href="/stop" class="btn stop">Stop</a>
<a href="/" class="btn refresh">Odswiez</a></div></div>
<div class="card"><h2>Logi</h2><div class="logs"><pre>$logs</pre></div></div>
</body></html>
HTMLEOF
}

handle_request() {
    local path="$1"
    case "$path" in
        "/"|"/index.html")
            local html=$(generate_html)
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo "Content-Length: ${#html}"
            echo "Connection: close"
            echo ""
            echo "$html"
            ;;
        "/start") "${SCRIPT_DIR}/start.sh" >/dev/null 2>&1 & sleep 1; echo -e "HTTP/1.1 302 Found\nLocation: /\n\n" ;;
        "/stop") "${SCRIPT_DIR}/stop.sh" >/dev/null 2>&1 & sleep 1; echo -e "HTTP/1.1 302 Found\nLocation: /\n\n" ;;
        *) echo -e "HTTP/1.1 404 Not Found\nContent-Length: 9\n\nNot Found" ;;
    esac
}

echo "=========================================="
echo "Web UI na porcie $PORT"
echo "Otwórz: http://localhost:$PORT"
echo "=========================================="

while true; do
    { read -r request; } < <(nc -l -p "$PORT" -q 1 2>/dev/null || nc -l "$PORT" 2>/dev/null) || continue
    path=$(echo "$request" | awk '{print $2}')
    handle_request "$path"
done
