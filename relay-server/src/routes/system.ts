import { FastifyInstance } from 'fastify';
import fs from 'fs/promises';
import path from 'path';

export async function systemRoutes(
  fastify: FastifyInstance,
  options: { ctx: any }
) {
  fastify.get('/fs/ls', async (request, reply) => {
    const { path: reqPath = '' } = request.query as { path?: string };

    try {
      if (!reqPath) {
        // Brute force A-Z drives
        const drives: any[] = [];
        const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
        
        await Promise.all(letters.map(async (letter) => {
          const drivePath = `${letter}:\\`;
          try {
            await fs.access(drivePath);
            drives.push({
              name: drivePath,
              path: drivePath,
              type: 'directory',
              childCount: -1,
              modifiedAt: new Date().toISOString()
            });
          } catch (e) {
            // Ignore if drive doesn't exist
          }
        }));
        
        return reply.send(drives);
      }

      // Read target directory
      const entries = await fs.readdir(reqPath, { withFileTypes: true });
      const nodes: any[] = [];

      for (const entry of entries) {
        if (!entry.isDirectory()) continue; // We only want directories for picking a project folder
        
        const entryPath = path.join(reqPath, entry.name);
        try {
          const stats = await fs.stat(entryPath);
          nodes.push({
            name: entry.name,
            path: entryPath.replace(/\\/g, '/'),
            type: 'directory',
            childCount: -1,
            modifiedAt: stats.mtime.toISOString(),
          });
        } catch (e) {
          // ignore permission errors on system folders
        }
      }
      
      return reply.send(nodes);
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to list directory', details: err.message });
    }
  });

  fastify.post('/fs/mkdir', async (request, reply) => {
    const { path: reqPath } = request.body as { path: string };
    if (!reqPath) {
      return reply.status(400).send({ error: 'path is required' });
    }
    
    try {
      await fs.mkdir(reqPath, { recursive: true });
      return reply.send({ success: true });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to create directory', details: err.message });
    }
  });
}
