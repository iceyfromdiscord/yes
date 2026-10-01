cat << 'EOF' > start_webshell.sh
#!/bin/bash

# Configuration
PORT=3000
DIR="$HOME/web_shell_app"
mkdir -p "$DIR/public"
cd "$DIR" || exit 1

# Helper function to generate an error HTML page and display it
show_error_html() {
    local ERR_MSG="$1"
    cat << HTMLEOF > public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Web Shell - Execution Error</title>
  <style>
    body { background-color: #1a1a1a; color: #ff5555; font-family: monospace; padding: 40px; }
    .card { background: #282828; border-left: 5px solid #ff5555; padding: 20px; border-radius: 4px; box-shadow: 0 4px 10px rgba(0,0,0,0.5); }
    h1 { margin-top: 0; color: #ff6e6e; font-size: 20px; }
    pre { background: #111; padding: 15px; border-radius: 4px; overflow-x: auto; color: #f8f8f2; }
  </style>
</head>
<body>
  <div class="card">
    <h1>⚠️ Web Shell Setup Failed</h1>
    <p>An error occurred during non-interactive execution:</p>
    <pre>${ERR_MSG}</pre>
  </div>
</body>
</html>
HTMLEOF

    # Serve the error HTML static page temporarily using Python or Node
    if command -v python3 &> /dev/null; then
        (cd public && python3 -m http.server $PORT &> /dev/null) &
    fi

    sleep 1
    URL="http://localhost:$PORT"
    if command -v xdg-open &> /dev/null; then
        xdg-open "$URL" &> /dev/null
    elif command -v google-chrome &> /dev/null; then
        google-chrome "$URL" &> /dev/null
    elif command -v firefox &> /dev/null; then
        firefox "$URL" &> /dev/null
    elif command -v wslview &> /dev/null; then
        wslview "$URL" &> /dev/null
    fi

    echo "[!] Fatal error encountered. Opening error page at $URL"
    exit 1
}

# 1. Non-interactive dependency check
if ! command -v node &> /dev/null; then
    # Test non-interactive sudo (fails instantly if password is required)
    if ! sudo -n true 2>/dev/null; then
        show_error_html "Node.js is not installed, and non-interactive 'sudo' privileges are unavailable.\nSudo requires password input or user is not in sudoers."
    fi

    # Attempt non-interactive installation
    DEBIAN_FRONTEND=noninteractive sudo apt-get update -y > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y nodejs npm build-essential > /dev/null 2>&1

    if ! command -v node &> /dev/null; then
        show_error_html "Failed to automatically install Node.js/NPM via apt."
    fi
fi

# 2. Initialize project non-interactively
if [ ! -f "package.json" ]; then
    npm init -y > /dev/null 2>&1
    NPM_ERR=$(npm install express ws node-pty 2>&1)
    if [ $? -ne 0 ]; then
        show_error_html "npm install failed:\n\n${NPM_ERR}"
    fi
fi

# 3. Write server.js
cat << 'JSEOF' > server.js
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const pty = require('node-pty');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(express.static(path.join(__dirname, 'public')));

wss.on('connection', (ws) => {
  const shell = process.env.SHELL || 'bash';
  const ptyProcess = pty.spawn(shell, [], {
    name: 'xterm-color',
    cols: 80,
    rows: 24,
    cwd: process.env.HOME,
    env: process.env
  });

  ptyProcess.onData((data) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(data);
  });

  ws.on('message', (msg) => {
    ptyProcess.write(msg.toString());
  });

  ws.on('close', () => ptyProcess.kill());
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`[+] Web Shell listening on http://localhost:${PORT}`);
});
JSEOF

# 4. Write public/index.html (Success UI)
cat << 'HTMLEOF' > public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Interactive VM Shell</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
  <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
  <style>
    body { background-color: #1e1e1e; margin: 0; padding: 15px; height: 100vh; box-sizing: border-box; }
    #terminal { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="terminal"></div>
  <script>
    const term = new Terminal({ cursorBlink: true, theme: { background: '#1e1e1e' } });
    term.open(document.getElementById('terminal'));

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${protocol}//${location.host}`);

    ws.onmessage = (event) => term.write(event.data);
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    });
  </script>
</body>
</html>
HTMLEOF

# 5. Start Server & Open Browser
PORT=$PORT node server.js &
SERVER_PID=$!
sleep 2

URL="http://localhost:$PORT"
if command -v xdg-open &> /dev/null; then
    xdg-open "$URL" &> /dev/null
elif command -v google-chrome &> /dev/null; then
    google-chrome "$URL" &> /dev/null
elif command -v firefox &> /dev/null; then
    firefox "$URL" &> /dev/null
elif command -v wslview &> /dev/null; then
    wslview "$URL" &> /dev/null
fi

trap "kill $SERVER_PID 2>/dev/null; exit 0" INT
wait $SERVER_PID
EOF
chmod +x start_webshell.sh
