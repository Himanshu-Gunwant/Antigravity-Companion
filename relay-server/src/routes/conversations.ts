import { FastifyInstance } from 'fastify';
import { AgentapiService } from '../services/agentapi.js';
import { OverviewService } from '../services/overview.js';
import path from 'path';
import fs from 'fs';

export async function conversationsRoutes(
  fastify: FastifyInstance,
  options: { agentapi: AgentapiService, transcripts: any, ctx: any }
) {
  const { agentapi, transcripts, ctx } = options;
  const overviewService = ctx ? new OverviewService(ctx.brainDir) : null;

  fastify.get('/:id/overview', async (request, reply) => {
    if (!overviewService) return reply.status(500).send({ error: 'Context not found' });
    const { id } = request.params as { id: string };
    try {
      const overview = await overviewService.getConversationOverview(id);
      return overview;
    } catch (err: any) {
      return reply.status(500).send({ error: err.message });
    }
  });

  fastify.get('/:id/artifacts/:filename', async (request, reply) => {
    const { id, filename } = request.params as { id: string, filename: string };
    if (!ctx) return reply.status(500).send({ error: 'Context not found' });
    
    try {
      // Security: Prevent path traversal
      const safeName = path.basename(filename);
      const safeId = path.basename(id);
      const artifactDir = path.join(ctx.brainDir, safeId);
      const filePath = path.join(artifactDir, safeName);
      
      if (!filePath.startsWith(artifactDir)) {
        return reply.status(403).send({ error: 'Path traversal blocked' });
      }

      const ext = path.extname(filePath).toLowerCase();
      
      let contentType = 'application/octet-stream';
      if (ext === '.md') contentType = 'text/markdown';
      else if (ext === '.png') contentType = 'image/png';
      else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
      
      const stream = fs.createReadStream(filePath);
      stream.on('error', (err: NodeJS.ErrnoException) => {
        if (err.code === 'ENOENT') {
          reply.status(404).send({ error: 'Artifact not found' });
        } else {
          reply.status(500).send({ error: 'Error reading artifact' });
        }
      });
      return reply.type(contentType).send(stream);
    } catch (err: any) {
      return reply.status(500).send({ error: 'Internal Server Error' });
    }
  });

  fastify.get('/:id/artifacts', async (request, reply) => {
    const { id } = request.params as { id: string };
    if (!ctx) return reply.status(500).send({ error: 'Context not found' });
    
    try {
      const safeId = path.basename(id);
      const artifactDir = path.join(ctx.brainDir, safeId);
      
      let entries: { filename: string, isMedia: boolean, modifiedAt: string, absolutePath: string }[] = [];
      try {
        const files = await fs.promises.readdir(artifactDir, { withFileTypes: true });
        for (const file of files) {
          if (file.isFile() && !file.name.endsWith('.jsonl') && !file.name.startsWith('.')) {
            // Check if it's an image
            const isMedia = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4'].some(ext => file.name.toLowerCase().endsWith(ext));
            
            // We ignore JSON metadata files as they are just backing metadata for MD files
            if (file.name.endsWith('.json') && !file.name.endsWith('.jsonl')) continue;

            const stats = await fs.promises.stat(path.join(artifactDir, file.name));
            const absolutePath = path.join(artifactDir, file.name).replace(/\\/g, '/');
            entries.push({
              filename: file.name,
              isMedia,
              modifiedAt: stats.mtime.toISOString(),
              absolutePath,
            });
          }
        }
      } catch (err: any) {
        if (err.code !== 'ENOENT') throw err;
      }
      
      // Sort newest first
      entries.sort((a, b) => new Date(b.modifiedAt).getTime() - new Date(a.modifiedAt).getTime());
      
      return reply.send({ artifacts: entries });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to list artifacts', details: err.message });
    }
  });

  fastify.get('/:id/history', async (request, reply) => {
    const { id } = request.params as { id: string };
    const { limit, beforeIndex } = request.query as { limit?: string, beforeIndex?: string };
    
    try {
      const parsedLimit = limit ? parseInt(limit, 10) : undefined;
      const parsedBeforeIndex = beforeIndex ? parseInt(beforeIndex, 10) : undefined;
      
      const history = await transcripts.getHistory(id, { limit: parsedLimit, beforeIndex: parsedBeforeIndex });
      return reply.send({ history });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to fetch history', details: err.message });
    }
  });

  fastify.get('/', async (request, reply) => {
    try {
      const conversations = await transcripts.listConversations();
      return reply.send({ conversations });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to list conversations', details: err.message });
    }
  });

  fastify.post('/', async (request, reply) => {
    const { prompt, model, modelChange, selectedModel } = request.body as { 
      prompt: string; 
      model?: 'flash_lite' | 'flash' | 'pro'; 
      modelChange?: { from: string; to: string };
      selectedModel?: string;
    };
    if (!prompt) {
      request.log.error({ body: request.body, headers: request.headers }, 'Missing prompt in request');
      return reply.status(400).send({ error: 'prompt is required', receivedBody: request.body });
    }

    const result = await agentapi.newConversation(prompt, model, modelChange, selectedModel);
    if (!result.success || !result.data) {
      return reply.status(500).send({ error: result.error?.message || 'Failed to create conversation' });
    }

    return reply.status(201).send({
      id: result.data.conversationId,
      createdAt: new Date().toISOString(),
    });
  });

  fastify.get('/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const result = await agentapi.getConversationMetadata(id);
    if (!result.success || !result.data) {
      return reply.status(404).send({ error: result.error?.message || 'Conversation not found' });
    }

    return reply.status(200).send(result.data);
  });

  fastify.get('/:id/messages', async (request, reply) => {
    const { id } = request.params as { id: string };
    try {
      const history = await transcripts.getHistory(id);
      return reply.send({ messages: history });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to retrieve history', details: err.message });
    }
  });

  fastify.post('/:id/messages', async (request, reply) => {
    const { id } = request.params as { id: string };
    const { content, modelChange, model } = request.body as { content: string; modelChange?: { from: string; to: string }; model?: string };
    if (!content) {
      return reply.status(400).send({ error: 'content is required' });
    }
    console.log(`[Relay] sendMessage called for ${id} with model: ${model}`);

    const result = await agentapi.sendMessage(id, content, modelChange, model);
    if (!result.success) {
      return reply.status(500).send({ error: result.error?.message || 'Failed to send message' });
    }

    return reply.status(200).send({});
  });

  fastify.post('/projects/new', async (request, reply) => {
    console.log('[Relay] HIT POST /projects/new endpoint!');
    const { targetDirectory } = request.body as { targetDirectory: string };
    if (!targetDirectory) {
      return reply.status(400).send({ error: 'targetDirectory is required' });
    }
    
    try {
      const crypto = await import('crypto');
      const newProjectId = crypto.randomUUID();
      const name = path.basename(targetDirectory) || 'Remote Project';
      
      const success = await agentapi.createProject(newProjectId, name, targetDirectory);
      
      if (success) {
        return reply.send({ success: true, message: 'Project initialized remotely!', projectId: newProjectId });
      } else {
        return reply.status(500).send({ error: 'Failed to create project via Language Server.' });
      }
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to launch project', details: err.message });
    }
  });
}
