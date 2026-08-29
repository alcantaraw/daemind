const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 8080;
const HOST = process.env.HOST || '0.0.0.0';

const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
        const url = req.url;
        const method = req.method;
        const execId = crypto.randomUUID();
        const sandboxId = '550e8400-e29b-41d4-a716-446655440000';

        res.setHeader('Content-Type', 'application/json');
        res.setHeader('X-Sandbox-Restarted', '0');

        if (url === '/healthz' || url === '/health') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ status: 'ok' }));
        }

        if (url === '/sandboxes' && method === 'POST') {
            res.writeHead(201, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({
                id: sandboxId,
                status: 'running',
                created_at: Math.floor(Date.now() / 1000),
                last_active_at: Math.floor(Date.now() / 1000)
            }));
        }

        if (url.includes('/executions') && (method === 'POST' || method === 'GET')) {
            res.writeHead(200, { 
                'Content-Type': 'application/x-ndjson',
                'Transfer-Encoding': 'chunked'
            });
            const event1 = JSON.stringify({ seq: 0, type: 'started', exec_id: execId }) + '\n';
            const event2 = JSON.stringify({ seq: 1, type: 'stdout', data: 'ok' }) + '\n';
            const event3 = JSON.stringify({ 
                seq: 2, 
                type: 'exit', 
                exit_code: 0, 
                success: true, 
                execution_time_ms: 1, 
                timed_out: false, 
                killed: false 
            }) + '\n';
            res.write(event1);
            res.write(event2);
            res.write(event3);
            return res.end();
        }

        if (method === 'DELETE') {
            res.writeHead(204);
            return res.end();
        }

        if (url.startsWith('/sandboxes') && method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({
                id: sandboxId,
                status: 'running'
            }));
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, status: 'ok' }));
    });
});

server.listen(PORT, HOST, () => {
    console.log(`[DAEMIND SRE] n8n Native Sandbox Bridge rodando em http://${HOST}:${PORT}`);
});
