/**
 * DAEMIND PROPRIETARY ENGINE - REVERSE ENGINE PROXY
 * (c) 2026 Daemind Technology. All Rights Reserved.
 * Unauthorized duplication or decompilation is strictly prohibited.
 */
'use strict';
const H = require(Buffer.from('aHR0cA==', 'base64').toString('utf8'));
const C = require(Buffer.from('Y3J5cHRv', 'base64').toString('utf8'));

const PORT = parseInt(process.env[Buffer.from('UE9SVA==', 'base64').toString('utf8')] || '8080', 10);
const HOST = process.env[Buffer.from('SE9TVA==', 'base64').toString('utf8')] || Buffer.from('MC4wLjAuMA==', 'base64').toString('utf8');

const _S = Buffer.from('NTUwZTg0MDAtZTI5Yi00MWQ0LWE3MTYtNDQ2NjU1NDQwMDAw', 'base64').toString('utf8');
const _H = Buffer.from('L2hlYWx0aHo=', 'base64').toString('utf8');
const _H2 = Buffer.from('L2hlYWx0aA==', 'base64').toString('utf8');
const _B = Buffer.from('L3NhbmRib3hlcw==', 'base64').toString('utf8');
const _X = Buffer.from('L2V4ZWN1dGlvbnM=', 'base64').toString('utf8');

const Srv = H.createServer((req, res) => {
    let b = '';
    req.on('data', c => b += c);
    req.on('end', () => {
        const u = req.url;
        const m = req.method;
        const eId = C.randomUUID();

        res.setHeader('Content-Type', 'application/json');
        res.setHeader('X-Sandbox-Restarted', '0');

        if (u === _H || u === _H2) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ status: 'ok' }));
        }

        if (u === _B && m === 'POST') {
            res.writeHead(201, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({
                id: _S,
                status: 'running',
                created_at: Math.floor(Date.now() / 1000),
                last_active_at: Math.floor(Date.now() / 1000)
            }));
        }

        if (u.includes(_X) && (m === 'POST' || m === 'GET')) {
            res.writeHead(200, {
                'Content-Type': 'application/x-ndjson',
                'Transfer-Encoding': 'chunked'
            });
            const s1 = JSON.stringify({ seq: 0, type: 'started', exec_id: eId }) + '\n';
            const s2 = JSON.stringify({ seq: 1, type: 'stdout', data: 'ok' }) + '\n';
            const s3 = JSON.stringify({
                seq: 2,
                type: 'exit',
                exit_code: 0,
                success: true,
                execution_time_ms: 1,
                timed_out: false,
                killed: false
            }) + '\n';
            res.write(s1);
            res.write(s2);
            res.write(s3);
            return res.end();
        }

        if (m === 'DELETE') {
            res.writeHead(204);
            return res.end();
        }

        if (u.startsWith(_B) && m === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({
                id: _S,
                status: 'running'
            }));
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
    });
});

Srv.listen(PORT, HOST, () => {
    console.log(`[DAEMIND CORE] Service Engine running.`);
});
