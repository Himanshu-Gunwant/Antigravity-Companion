import { FastifyInstance } from 'fastify';
import { BuildDetectorService } from '../services/build-detector';
import { createReadStream } from 'fs';
import * as fsPromises from 'fs/promises';
import * as path from 'path';

export async function buildRoutes(
  fastify: FastifyInstance,
  options: { buildDetector: BuildDetectorService; ctx: any }
) {
  const { buildDetector, ctx } = options;

  fastify.get('/', async (request, reply) => {
    const builds = buildDetector.listBuilds();
    return reply.send(builds.map(b => ({
      ...b,
      downloadUrl: `/api/builds/${b.id}/download`,
    })));
  });

  fastify.get('/:id/download', async (request, reply) => {
    const { id } = request.params as { id: string };
    const build = buildDetector.getBuild(id);
    if (!build) return reply.status(404).send({ error: 'Build not found' });

    try {
      const realPath = await fsPromises.realpath(build.absolutePath);
      // Extra path traversal protection
      if (!realPath.toLowerCase().startsWith(ctx.workspaceDir.toLowerCase())) {
        return reply.status(403).send({ error: 'Path traversal blocked' });
      }

      const fileBuffer = await fsPromises.readFile(realPath);
      
      return reply
        .header('Content-Type', 'application/octet-stream')
        .header('Content-Disposition', `attachment; filename="${build.fileName}"`)
        .send(fileBuffer);
    } catch (e: any) {
      return reply.status(500).send({ error: 'Failed to read artifact', details: e.message });
    }
  });
}
