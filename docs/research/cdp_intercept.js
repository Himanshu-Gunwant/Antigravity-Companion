// Intercept fetch calls in the Antigravity Electron app via CDP
// to discover the exact API format for sending user messages

const WebSocket = require('ws');
const http = require('http');

const CDP_PORT = 58806;
const WS_URL = process.argv[2] || `ws://127.0.0.1:${CDP_PORT}/devtools/page/0CFA0C6F72301152B2DE4878BDA5B0E9`;

async function main() {
  const ws = new WebSocket(WS_URL);
  let msgId = 0;
  
  function send(method, params = {}) {
    const id = ++msgId;
    return new Promise((resolve, reject) => {
      const handler = (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.id === id) {
          ws.removeListener('message', handler);
          if (msg.error) reject(new Error(JSON.stringify(msg.error)));
          else resolve(msg.result);
        }
      };
      ws.on('message', handler);
      ws.send(JSON.stringify({ id, method, params }));
    });
  }

  ws.on('open', async () => {
    try {
      // Enable network domain to capture requests
      await send('Network.enable');
      console.log('[CDP] Network enabled, waiting for requests...');
      
      // Also inject a fetch interceptor to capture request bodies
      await send('Runtime.evaluate', {
        expression: `
          if (!window.__fetchIntercepted) {
            window.__fetchIntercepted = true;
            window.__capturedCalls = [];
            const origFetch = window.fetch;
            window.fetch = function(...args) {
              const url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
              const opts = args[1] || {};
              if (url && (url.includes('SendUserCascade') || url.includes('Cascade') || url.includes('language_server'))) {
                const entry = { url, method: opts.method, headers: opts.headers, bodyType: typeof opts.body };
                // Try to capture body as text if it's not binary
                if (opts.body && typeof opts.body === 'string') {
                  entry.bodyText = opts.body.substring(0, 500);
                }
                window.__capturedCalls.push(entry);
                console.log('[FETCH INTERCEPTOR]', JSON.stringify(entry));
              }
              return origFetch.apply(this, args);
            };
            'Interceptor installed';
          } else {
            'Already installed';
          }
        `
      });
      console.log('[CDP] Fetch interceptor installed');

      // Listen for Network events  
      ws.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.method === 'Network.requestWillBeSent') {
          const req = msg.params.request;
          if (req.url.includes('SendUserCascade') || req.url.includes('cascade') || req.url.includes('CascadeMessage')) {
            console.log('\n[NETWORK] ===========================');
            console.log(`URL: ${req.url}`);
            console.log(`Method: ${req.method}`);
            console.log(`Headers: ${JSON.stringify(req.headers, null, 2)}`);
            if (req.postData) {
              console.log(`PostData (first 500): ${req.postData.substring(0, 500)}`);
            }
            console.log('===========================\n');
          }
        }
      });

      // Wait for user to send a message in Antigravity
      console.log('\n>>> Now send a message in the Antigravity UI. Waiting to capture the request...\n');
      
      // Poll for captured calls periodically
      setInterval(async () => {
        try {
          const result = await send('Runtime.evaluate', {
            expression: 'JSON.stringify(window.__capturedCalls || [])'
          });
          const calls = JSON.parse(result.result.value || '[]');
          if (calls.length > 0) {
            console.log('[CAPTURED]', JSON.stringify(calls, null, 2));
          }
        } catch (e) {}
      }, 3000);

    } catch (err) {
      console.error('Error:', err);
    }
  });
  
  ws.on('error', (err) => console.error('WS Error:', err.message));
}

main();
