#!/usr/bin/env node

/**
 * CDP Proxy Server for Daytona (Built-in modules only)
 * 
 * This proxy fixes the WebSocket URL issue where Chrome CDP returns localhost
 * URLs that are not accessible externally. It rewrites the URLs to use the
 * proper Daytona proxy domain.
 */

// Usage tip: To override Chrome binary, set CHROME_BIN env var before running this script.
// Example:
//   export CHROME_BIN="/ms-playwright/chromium-1169/chrome-linux/chrome"
//   node cdp_proxy_simple.js
// This makes your setup portable and configurable for different environments.

const http = require('http');
const url = require('url');
const { execSync } = require('child_process');

// Configuration
const CHROME_PORT = process.env.CDP_STANDALONE_PORT || 9221;
const PROXY_PORT = process.env.CDP_PORT || 9223;
const EXTERNAL_HOST = process.env.DAYTONA_HOST || process.env.EXTERNAL_HOST;

console.log('=== CDP Proxy Server Starting ===');
console.log(`Chrome CDP Port: ${CHROME_PORT}`);
console.log(`Proxy Port: ${PROXY_PORT}`);
console.log(`External Host: ${EXTERNAL_HOST || 'auto-detect'}`);

// Function to detect external host from request headers
function getExternalHost(req) {
  if (EXTERNAL_HOST) {
    return EXTERNAL_HOST;
  }
  
  // Try to get Daytona sandbox ID from hostname
  try {
    const hostname = execSync('hostname', { encoding: 'utf8' }).trim();
    
    // Check if this looks like a Daytona sandbox ID (UUID format)
    if (hostname.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)) {
      const daytonaHost = `${PROXY_PORT}-${hostname}.proxy.daytona.work`;
      return daytonaHost;
    }
  } catch (error) {
    // Ignore hostname detection errors
  }
  
  // Fallback to request headers - use the actual host from the request
  const host = req.headers.host;
  if (host && host.includes('.proxy.daytona.work')) {
    return host;
  }
  
  const xForwardedHost = req.headers['x-forwarded-host'];
  const xOriginalHost = req.headers['x-original-host'];
  
  // For other proxy setups, prioritize the forwarded host
  const detectedHost = xForwardedHost || xOriginalHost || host;
  
  return detectedHost || 'localhost';
}

// Function to rewrite CDP JSON responses
function rewriteCdpResponse(body, externalHost) {
  try {
    const data = JSON.parse(body);
    
    // Handle array of targets (from /json endpoint)
    if (Array.isArray(data)) {
      return data.map(target => rewriteTarget(target, externalHost));
    }
    
    // Handle single target or browser info - rewrite ANY object that might contain URLs
    if (data && typeof data === 'object') {
      return rewriteTarget(data, externalHost);
    }
    
    return data;
  } catch (error) {
    return body;
  }
}

// Function to rewrite individual target URLs - comprehensive coverage for all CDP endpoints
function rewriteTarget(target, externalHost) {
  const rewritten = { ...target };
  
  // All possible WebSocket URL fields that CDP might return
  const wsFields = [
    'webSocketDebuggerUrl',    // Standard page WebSocket URL
    'webSocketUrl',            // Browser-level WebSocket URL (Playwright)
    'websocketUrl',            // Alternative casing
    'webSocketURL',            // Alternative casing
    'wsUrl',                   // Short form
    'debuggerUrl'              // Alternative naming
  ];
  
  // All possible HTTP URL fields that might need rewriting
  const httpFields = [
    'devtoolsFrontendUrl',     // DevTools frontend URL
    'devtoolsUrl',             // Alternative naming
    'frontendUrl',             // Short form
    'url',                     // Generic URL field
    'targetUrl',               // Target page URL
    'faviconUrl',              // Favicon URL
    'thumbnailUrl'             // Thumbnail URL
  ];
  
    // Rewrite all WebSocket URLs - preserve paths and query params
  wsFields.forEach(field => {
    if (rewritten[field] && typeof rewritten[field] === 'string') {
      const originalUrl = rewritten[field];
      rewritten[field] = rewritten[field]
        .replace(/ws:\/\/localhost:(\d+)(\/.*)?/, `wss://${externalHost}$2`)
        .replace(/ws:\/\/127\.0\.0\.1:(\d+)(\/.*)?/, `wss://${externalHost}$2`)
        .replace(/ws:\/\/0\.0\.0\.0:(\d+)(\/.*)?/, `wss://${externalHost}$2`)
        .replace(/ws:\/\/\[::]:(\d+)(\/.*)?/, `wss://${externalHost}$2`);
      
      if (originalUrl !== rewritten[field]) {
        console.log(`🔄 Rewrote WebSocket ${field}: ${originalUrl} → ${rewritten[field]}`);
      }
    }
  });
  
  // Rewrite HTTP URLs only for DevTools/CDP endpoints - preserve paths  
  httpFields.forEach(field => {
    if (rewritten[field] && typeof rewritten[field] === 'string') {
      // Only rewrite if it looks like a CDP-related URL
      if (rewritten[field].includes('devtools') || 
          rewritten[field].includes('localhost:') ||
          rewritten[field].includes('127.0.0.1:')) {
        const originalUrl = rewritten[field];
        rewritten[field] = rewritten[field]
          .replace(/https?:\/\/localhost:(\d+)(\/.*)?/, `https://${externalHost}$2`)
          .replace(/https?:\/\/127\.0\.0\.1:(\d+)(\/.*)?/, `https://${externalHost}$2`)
          .replace(/https?:\/\/0\.0\.0\.0:(\d+)(\/.*)?/, `https://${externalHost}$2`)
          .replace(/https?:\/\/\[::]:(\d+)(\/.*)?/, `https://${externalHost}$2`);
        
        if (originalUrl !== rewritten[field]) {
          console.log(`🔄 Rewrote HTTP ${field}: ${originalUrl} → ${rewritten[field]}`);
        }
      }
    }
  });
  
  return rewritten;
}

// Function to proxy HTTP requests
function proxyRequest(req, res, externalHost) {
  const options = {
    hostname: '127.0.0.1',
    port: CHROME_PORT,
    path: req.url,
    method: req.method,
    headers: { ...req.headers }
  };
  
  // Remove host header to avoid conflicts
  delete options.headers.host;
  
  const proxyReq = http.request(options, (proxyRes) => {
    // Check if this is a CDP JSON response that needs rewriting
    // Rewrite ALL endpoints to ensure comprehensive coverage
    if (req.url === '/json' || 
        req.url.startsWith('/json/') || 
        req.url.includes('list') || 
        req.url.includes('new') || 
        req.url.includes('activate') || 
        req.url.includes('close') || 
        req.url.includes('version') ||
        (proxyRes.headers['content-type'] && proxyRes.headers['content-type'].includes('application/json'))) {
      let body = Buffer.alloc(0);
      proxyRes.on('data', (chunk) => {
        body = Buffer.concat([body, chunk]);
      });
      
      proxyRes.on('end', () => {
        try {
          const bodyString = body.toString('utf8');
          const rewrittenData = rewriteCdpResponse(bodyString, externalHost);
          const rewrittenBody = JSON.stringify(rewrittenData, null, 2);
          
          // Update Content-Length header for the rewritten response
          const responseHeaders = { ...proxyRes.headers };
          responseHeaders['content-length'] = Buffer.byteLength(rewrittenBody, 'utf8');
          
          res.writeHead(proxyRes.statusCode, responseHeaders);
          res.end(rewrittenBody);
        } catch (error) {
          // Send original response on error
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          res.end(body);
        }
      });
    } else {
      // For other requests (non-JSON endpoints), copy headers and pipe the response
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    }
  });
  
  proxyReq.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        error: 'Bad Gateway', 
        message: 'Chrome CDP server is not available',
        details: err.message 
      }));
    }
  });
  
  // Pipe request body if present
  req.pipe(proxyReq);
}

// Wait for Chrome CDP to be available
async function waitForChrome() {
  console.log('Waiting for Chrome CDP to be available...');
  const maxRetries = 30;
  
  for (let i = 0; i < maxRetries; i++) {
    try {
      const options = {
        hostname: '127.0.0.1',
        port: CHROME_PORT,
        path: '/json',
        method: 'GET',
        timeout: 2000
      };
      
      await new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
          if (res.statusCode === 200) {
            resolve();
          } else {
            reject(new Error(`HTTP ${res.statusCode}`));
          }
        });
        req.on('error', reject);
        req.on('timeout', () => {
          req.destroy();
          reject(new Error('Timeout'));
        });
        req.end();
      });
      
      console.log('✅ Chrome CDP is available');
      return true;
    } catch (error) {
      console.log(`⏳ Waiting for Chrome CDP... (attempt ${i + 1}/${maxRetries})`);
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
  
  console.log('❌ Chrome CDP is not available after waiting');
  return false;
}

// Utility: Check if Chrome is running on the CDP port
function isChromeRunning() {
  try {
    const net = require('net');
    return new Promise((resolve) => {
      const socket = net.createConnection({ port: CHROME_PORT, host: '127.0.0.1' }, () => {
        socket.end();
        resolve(true);
      });
      socket.on('error', () => resolve(false));
    });
  } catch (e) {
    return Promise.resolve(false);
  }
}


// Utility: Start Chrome with CDP port (visible in noVNC)
function startChrome() {
   // Make sure X server is running before starting Chrome
  try {
    console.log('Checking X server status...');
    execSync('pgrep Xvfb || (echo "Starting Xvfb" && Xvfb :99 -screen 0 1920x1080x24 -ac &)');
    execSync('for i in {1..5}; do if [ -e /tmp/.X11-unix/X99 ]; then echo "X server ready"; break; fi; sleep 1; done');
  } catch (e) {
    console.warn('Warning: X server check failed, Chrome might not start properly');
  }
  const chromeCmd = process.env.CHROME_BIN || '/ms-playwright/chromium-1169/chrome-linux/chrome';
  const chromeArgs = [
    // '--headless', // Removed for noVNC visibility
    '--disable-gpu',
    '--disable-dbus',
    '--disable-dev-shm-usage', 
    '--disable-setuid-sandbox',
    '--disable-background-networking',
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-breakpad',
    '--disable-client-side-phishing-detection',
    '--disable-component-update',
    '--disable-default-apps',
    '--disable-features=TranslateUI,VizDisplayCompositor',
    '--disable-hang-monitor',
    '--disable-ipc-flooding-protection',
    '--disable-popup-blocking',
    '--disable-prompt-on-repost',
    '--disable-renderer-backgrounding',
    '--disable-sync',
    '--disable-web-resources',
    '--metrics-recording-only',
    '--no-first-run',
    '--safebrowsing-disable-auto-update',
    '--enable-automation',
    '--password-store=basic',
    '--use-mock-keychain',
    // Safe infobar removal (uncommented):
    '--disable-infobars',
    '--disable-notifications',
    '--disable-translate',
    '--disable-extensions',
    '--disable-logging',
    '--disable-component-extensions-with-background-pages',
    // Keep these commented - they can break CDP:
    // '--disable-web-security',
    // '--disable-blink-features=AutomationControlled',
    // '--allow-running-insecure-content',
    `--remote-debugging-port=${CHROME_PORT}`,
    '--remote-debugging-address=0.0.0.0',
    '--user-data-dir=/tmp/persistent-chrome',
    'about:blank'
];
  const { spawn } = require('child_process');
  console.log(`Launching Chrome: ${chromeCmd} ${chromeArgs.join(' ')}`);
  const chromeProc = spawn(chromeCmd, chromeArgs, {
    detached: true,
    env: {
      ...process.env,
      DISPLAY: ':99'  // Ensure Chrome uses X11 display for noVNC
    },    stdio: 'ignore'
  });
  chromeProc.unref();
}

// Create HTTP server
const server = http.createServer((req, res) => {
  const externalHost = getExternalHost(req);
  proxyRequest(req, res, externalHost);
});

// Handle WebSocket upgrades (simplified)
server.on('upgrade', (req, socket, head) => {
  const externalHost = getExternalHost(req);
  
  // Create connection to Chrome
  const chromeReq = http.request({
    hostname: '127.0.0.1',
    port: CHROME_PORT,
    path: req.url,
    method: req.method,
    headers: req.headers
  });
  
  chromeReq.on('upgrade', (chromeRes, chromeSocket, chromeHead) => {
    // Forward the complete upgrade response from Chrome to client
    socket.write(`HTTP/1.1 ${chromeRes.statusCode} ${chromeRes.statusMessage}\r\n`);
    
    // Forward all headers from Chrome's response
    Object.keys(chromeRes.headers).forEach(key => {
      socket.write(`${key}: ${chromeRes.headers[key]}\r\n`);
    });
    
    socket.write('\r\n');
    
    // Forward any initial data
    if (chromeHead && chromeHead.length > 0) {
      socket.write(chromeHead);
    }
    
    // Pipe data between client and Chrome
    socket.pipe(chromeSocket);
    chromeSocket.pipe(socket);
    
    // Handle connection errors
    socket.on('error', () => chromeSocket.destroy());
    chromeSocket.on('error', () => socket.destroy());
  });
  
  chromeReq.on('error', (err) => {
    socket.end();
  });
  
  chromeReq.end();
});

// Start the proxy server
async function startProxy() {
  // Full automation: Start Chrome if not running
  if (!(await isChromeRunning())) {
    console.log('Chrome is not running. Starting Chrome...');
    startChrome();
    // Wait for Chrome to be ready
    await new Promise(resolve => setTimeout(resolve, 3000));
  } else {
    console.log('Chrome is already running.');
  }
  // Wait for Chrome to be ready (with timeout)
  const chromeReady = await waitForChrome();
  if (!chromeReady) {
    console.log('⚠️ Starting proxy anyway - Chrome might start later');
  }

  // Start server
  server.listen(PROXY_PORT, '0.0.0.0', () => {
    console.log(`✅ CDP Proxy Server listening on port ${PROXY_PORT}`);
    console.log(`   Proxying Chrome CDP from port ${CHROME_PORT}`);
    console.log(`   Access via: http://0.0.0.0:${PROXY_PORT}/json`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully');
    server.close(() => {
      console.log('CDP Proxy Server stopped');
      process.exit(0);
    });
  });

  process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully');
    server.close(() => {
      console.log('CDP Proxy Server stopped');
      process.exit(0);
    });
  });
}

// Start the proxy
startProxy().catch(error => {
  console.error('Failed to start CDP proxy:', error);
  process.exit(1);
});
