import { FastifyInstance } from 'fastify';
import { GitService } from '../services/git';
import { TranscriptWatcherService } from '../services/transcript-watcher';
import { isWorkspaceAllowed } from './files.js';
import path from 'path';

export async function gitRoutes(
  fastify: FastifyInstance,
  options: { gitService: GitService; transcripts: TranscriptWatcherService; ctx: any }
) {
  const { gitService, transcripts, ctx } = options;

  const getWorkspaceDir = async (request: any): Promise<string> => {
    const { workspace, subPath } = (request.query || request.body || {}) as { workspace?: string; subPath?: string };
    
    let resolvedWorkspace = ctx.workspaceDir;
    if (workspace) {
      resolvedWorkspace = path.resolve(workspace).replace(/\\/g, '/');
      const allowed = await isWorkspaceAllowed(resolvedWorkspace, ctx.workspaceDir, transcripts);
      if (!allowed) {
        throw new Error('Workspace access not allowed');
      }
    }
    
    if (subPath) {
      const cleanSubPath = subPath.replace(/^[\/\\]+/, '');
      const finalDir = path.resolve(resolvedWorkspace, cleanSubPath);
      const normFinal = path.normalize(finalDir).toLowerCase();
      const normWorkspace = path.normalize(resolvedWorkspace).toLowerCase();
      if (!normFinal.startsWith(normWorkspace)) {
        throw new Error('Path traversal blocked');
      }
      return finalDir;
    }
    
    return resolvedWorkspace;
  };

  fastify.get('/status', async (request, reply) => {
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const status = await gitService.status(workspaceDir);
      return reply.send(status);
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to get git status', details: err.message });
    }
  });

  fastify.get('/diff', async (request, reply) => {
    const { file, staged } = request.query as { file?: string; staged?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const diff = await gitService.diff(file, staged === 'true', workspaceDir);
      return reply.send({ diff });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to get git diff', details: err.message });
    }
  });

  fastify.get('/log', async (request, reply) => {
    const { count = '20' } = request.query as { count?: string };
    const parsedCount = parseInt(count, 10);
    const validCount = isNaN(parsedCount) || parsedCount <= 0 ? 20 : parsedCount;
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const log = await gitService.log(validCount, workspaceDir);
      return reply.send(log);
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to get git log', details: err.message });
    }
  });

  fastify.get('/show/:hash', async (request, reply) => {
    const { hash } = request.params as { hash: string };
    const { file } = request.query as { file?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const content = await gitService.show(hash, file, workspaceDir);
      return reply.send({ content });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to show commit content', details: err.message });
    }
  });

  fastify.post('/add', async (request, reply) => {
    const { files } = request.body as { files: string[] };
    if (!files || !Array.isArray(files)) {
      return reply.status(400).send({ error: 'Missing or invalid files array' });
    }
    try {
      const workspaceDir = await getWorkspaceDir(request);
      await gitService.add(files, workspaceDir);
      return reply.send({ success: true });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to git add', details: err.message });
    }
  });

  fastify.post('/commit', async (request, reply) => {
    const { message } = request.body as { message: string };
    if (!message || typeof message !== 'string') {
      return reply.status(400).send({ error: 'Missing or invalid commit message' });
    }
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const output = await gitService.commit(message, workspaceDir);
      return reply.send({ output });
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to commit', details: err.message });
    }
  });

  fastify.post('/push', async (request, reply) => {
    const { remote, branch } = request.body as { remote?: string; branch?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const output = await gitService.push(remote, branch, workspaceDir);
      return reply.send({ output });
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to push', details: err.message });
    }
  });

  fastify.post('/pull', async (request, reply) => {
    const { remote, branch } = request.body as { remote?: string; branch?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const output = await gitService.pull(remote, branch, workspaceDir);
      return reply.send({ output });
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to pull', details: err.message });
    }
  });
}
