const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');

console.log("Locating Antigravity DevTools port...");

const portFile = 'C:\\Users\\Himanshu\\AppData\\Roaming\\Antigravity\\DevToolsActivePort';
const port = fs.readFileSync(portFile, 'utf8').split('\n')[0].trim();
console.log("Active DevTools Port: " + port);

http.get(`http://127.0.0.1:${port}/json`, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const targets = JSON.parse(data);
    const pageTarget = targets.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
    
    if (!pageTarget) {
      console.error("Could not find the Antigravity page target.");
      process.exit(1);
    }

    console.log(`Found target: ${pageTarget.title || pageTarget.url}`);
    startSniffing(pageTarget.webSocketDebuggerUrl);
  });
}).on('error', (err) => {
  console.error("Error connecting to DevTools: ", err.message);
});

function startSniffing(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let logs = [];
  if (fs.existsSync('network_log.json')) {
    try {
      logs = JSON.parse(fs.readFileSync('network_log.json', 'utf8'));
    } catch (e) {
      logs = [];
    }
  }

  ws.on('open', () => {
    console.log("Connected! Enabling Network domain...");
    ws.send(JSON.stringify({
      id: 1,
      method: 'Network.enable'
    }));
    console.log("\n*** SNIFFER ACTIVE ***");
    console.log("Waiting for POST requests. Type your message in Antigravity now...");
  });

  ws.on('message', (data) => {
    const msg = JSON.parse(data);
    
    if (msg.method === 'Network.requestWillBeSent') {
      const req = msg.params.request;
      
      // We only care about POST requests (gRPC-Web uses POST)
      if (req.method === 'POST') {
        console.log(`\n[+] Intercepted POST to: ${req.url}`);
        
        const logEntry = {
          url: req.url,
          headers: req.headers,
          postData: req.postData,
          timestamp: new Date().toISOString()
        };
        
        logs.push(logEntry);
        fs.writeFileSync('network_log.json', JSON.stringify(logs, null, 2));
        console.log("Saved request to network_log.json!");
      }
    }
  });

  ws.on('error', (err) => console.error("WS Error:", err));
}
