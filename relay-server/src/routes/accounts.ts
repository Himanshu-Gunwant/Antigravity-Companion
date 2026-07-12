import { FastifyInstance } from 'fastify';
import { extractAccount, listAccounts, swapAccount } from '../services/accountService.js';

export async function accountsRoute(fastify: FastifyInstance) {
  fastify.post('/extract', async (request, reply) => {
    const body = (request.body as any) || {};
    const { profileName, executablePath } = body;
    
    if (!profileName || !executablePath) {
      return reply.code(400).send({ success: false, error: 'profileName and executablePath are required' });
    }

    try {
      const result = await extractAccount(profileName, executablePath);
      return reply.send(result);
    } catch (err: any) {
      console.error('[AccountsRoute] Failed to extract account:', err);
      return reply.code(500).send({ success: false, error: err.message });
    }
  });

  fastify.get('/', async (request, reply) => {
    try {
      const result = await listAccounts();
      return reply.send(result);
    } catch (err: any) {
      console.error('[AccountsRoute] Failed to list accounts:', err);
      return reply.code(500).send({ success: false, error: err.message });
    }
  });

  fastify.post('/swap', async (request, reply) => {
    const body = (request.body as any) || {};
    const { profileName, executablePath } = body;
    
    if (!profileName || !executablePath) {
      return reply.code(400).send({ success: false, error: 'profileName and executablePath are required' });
    }

    try {
      const result = await swapAccount(profileName, executablePath);
      return reply.send(result);
    } catch (err: any) {
      console.error('[AccountsRoute] Failed to swap account:', err);
      return reply.code(500).send({ success: false, error: err.message });
    }
  });
}
