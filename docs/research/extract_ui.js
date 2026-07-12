const WebSocket = require('ws');
const fs = require('fs');

const wsUrl = "ws://127.0.0.1:9222/devtools/page/F0A7EB3F23C35196B8CB1BA08A8EE65A";
const ws = new WebSocket(wsUrl);

ws.on('open', function open() {
  console.log("Connected to Antigravity UI");
  
  // 1. Get outerHTML
  ws.send(JSON.stringify({
    id: 1,
    method: 'Runtime.evaluate',
    params: {
      expression: 'document.documentElement.outerHTML',
      returnByValue: true
    }
  }));

  // 2. Extract CSS styles
  ws.send(JSON.stringify({
    id: 2,
    method: 'Runtime.evaluate',
    params: {
      expression: 'Array.from(document.styleSheets).map(s => { try { return Array.from(s.cssRules).map(r => r.cssText).join("\\n"); } catch(e) { return ""; } }).join("\\n")',
      returnByValue: true
    }
  }));
});

ws.on('message', function incoming(data) {
  const response = JSON.parse(data);
  
  if (response.id === 1 && response.result) {
    fs.writeFileSync('antigravity_ui.html', response.result.result.value);
    console.log("Saved HTML structure to antigravity_ui.html");
  }
  
  if (response.id === 2 && response.result) {
    fs.writeFileSync('antigravity_styles.css', response.result.result.value);
    console.log("Saved CSS styles to antigravity_styles.css");
    process.exit(0);
  }
  
  if (response.error) {
    console.error(response.error);
    process.exit(1);
  }
});

ws.on('error', function error(err) {
  console.error("WebSocket Error:", err);
});
