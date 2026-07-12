import { FastifyRequest, FastifyReply } from 'fastify';
import bcrypt from 'bcrypt';
import { config } from '../config.js';

const API_KEY_HEADER = 'x-relay-api-key';

const keyCache = new Map<string, { valid: boolean, expires: number }>();

export async function authMiddleware(request: FastifyRequest, reply: FastifyReply) {
  // Allow options requests, health endpoint, or the websocket endpoint without header-based auth
  if (
    request.method === 'OPTIONS' || 
    (request.url === '/api/health' && request.method === 'GET') ||
    (request.url === '/api/test-notification' && request.method === 'POST') ||
    request.url.startsWith('/ws')
  ) {
    return;
  }
  
  const key = request.headers[API_KEY_HEADER] as string;
  if (!key) {
    return reply.status(401).send({ error: 'Missing API key' });
  }

  if (!config.apiKeyHash) {
    return reply.status(500).send({ error: 'API key hash not configured on server' });
  }

  const now = Date.now();
  const cached = keyCache.get(key);
  if (cached && cached.expires > now) {
    if (!cached.valid) return reply.status(403).send({ error: 'Invalid API key' });
    return;
  }

  const valid = await bcrypt.compare(key, config.apiKeyHash);
  keyCache.set(key, { valid, expires: now + 3600000 }); // cache for 1 hour

  if (!valid) {
    return reply.status(403).send({ error: 'Invalid API key' });
  }
}
