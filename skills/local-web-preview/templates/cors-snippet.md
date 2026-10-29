# CORS snippet for sandboxed iframe previews

OpenCode's Review pane renders preview HTML inside a sandbox **without `allow-same-origin`**.
That makes the page's origin `null`, so every `fetch` to your local port is cross-origin.
`GET` may pass, but `POST` with `Content-Type: application/json` triggers an `OPTIONS`
preflight. Without CORS headers the browser reports `Failed to fetch`.

## Node.js (http.createServer)

```js
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400'
};

const server = http.createServer((req, res) => {
  // preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS_HEADERS);
    res.end();
    return;
  }

  const sendJson = (code, obj) => {
    res.writeHead(code, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...CORS_HEADERS
    });
    res.end(JSON.stringify(obj));
  };

  // ... your routes ...
});
```

Also add `...CORS_HEADERS` to static file responses and to 403/404 responses.

## Python (http.server)

```python
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
}

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        for k, v in CORS.items():
            self.send_header(k, v)
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()
```

## Flask

```python
from flask import Flask
from flask_cors import CORS

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})
```

## Verify

```bash
curl.exe -i -X OPTIONS http://127.0.0.1:8770/api/anything \
  -H "Origin: null" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type"
# expect: HTTP/1.1 204 + Access-Control-Allow-Origin: *
```
