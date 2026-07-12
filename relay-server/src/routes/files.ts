import { FastifyInstance } from 'fastify';
import fs from 'fs/promises';
import path from 'path';
import { FileNode } from '../models/file';
import { TranscriptWatcherService } from '../services/transcript-watcher';
import { FileWatcherService } from '../services/file-watcher';

export async function isWorkspaceAllowed(
  targetWorkspace: string,
  workspaceDir: string,
  transcripts: TranscriptWatcherService
): Promise<boolean> {
  const normTarget = path.normalize(targetWorkspace).toLowerCase().replace(/\\/g, '/');
  const normDefault = path.normalize(workspaceDir).toLowerCase().replace(/\\/g, '/');
  
  if (normTarget === normDefault) return true;
  
  const conversations = await transcripts.listConversations();
  for (const c of conversations) {
    if (c.workspace) {
      const normW = path.normalize(c.workspace).toLowerCase().replace(/\\/g, '/');
      if (normTarget === normW) return true;
    }
  }
  return false;
}

// Path traversal validation helper
export async function validatePath(requestedPath: string, workspaceDir: string): Promise<string> {
  const cleanPath = requestedPath.replace(/^[\/\\]+/, '');
  const resolvedPath = path.resolve(workspaceDir, cleanPath);
  
  const normWorkspace = path.normalize(workspaceDir).toLowerCase();
  
  let realPath: string;
  try {
    realPath = await fs.realpath(resolvedPath);
  } catch (err: any) {
    if (err.code === 'ENOENT') {
      let currentDir = path.dirname(resolvedPath);
      let realParent: string | undefined;
      
      // Traverse up until we find a directory that actually exists
      while (currentDir !== path.dirname(currentDir)) {
        try {
          realParent = await fs.realpath(currentDir);
          break;
        } catch (e: any) {
          if (e.code === 'ENOENT') {
            currentDir = path.dirname(currentDir);
          } else {
            throw e;
          }
        }
      }
      
      if (!realParent) {
        throw new Error('Path traversal blocked: unable to resolve base path');
      }
      
      const normParent = path.normalize(realParent).toLowerCase();
      if (!normParent.startsWith(normWorkspace)) {
        throw new Error('Path traversal blocked');
      }
      return resolvedPath;
    }
    throw err;
  }
  
  const normReal = path.normalize(realPath).toLowerCase();
  if (!normReal.startsWith(normWorkspace)) {
    throw new Error('Path traversal blocked');
  }
  return realPath;
}

export async function filesRoutes(
  fastify: FastifyInstance,
  options: { ctx: any; transcripts: TranscriptWatcherService; fileWatcher: FileWatcherService }
) {
  const { ctx, transcripts, fileWatcher } = options;

  const getWorkspaceDir = async (request: any): Promise<string> => {
    const query = request.query || {};
    const body = request.body || {};
    const workspace = query.workspace || body.workspace;
    if (!workspace) return ctx.workspaceDir;
    
    const resolvedWorkspace = path.resolve(workspace).replace(/\\/g, '/');
    const allowed = await isWorkspaceAllowed(resolvedWorkspace, ctx.workspaceDir, transcripts);
    if (!allowed) {
      throw new Error('Workspace access not allowed');
    }
    
    if (fileWatcher) {
      await fileWatcher.watchWorkspace(resolvedWorkspace, ctx);
    }
    
    return resolvedWorkspace;
  };

  fastify.get('/', async (request, reply) => {
    const { path: reqPath = '' } = request.query as { path?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const targetDir = await validatePath(reqPath, workspaceDir);
      
      const entries = await fs.readdir(targetDir, { withFileTypes: true });
      const nodes: FileNode[] = [];
      
      for (const entry of entries) {
        const isExcluded = ['.git', 'node_modules', '.dart_tool', '.gradle', '.DS_Store'].includes(entry.name);
        if (isExcluded) continue;
        
        const entryPath = path.join(targetDir, entry.name);
        const relativePath = path.relative(workspaceDir, entryPath).replace(/\\/g, '/');
        const stats = await fs.stat(entryPath);
        
        if (entry.isDirectory()) {
          const children = await fs.readdir(entryPath);
          const childCount = children.filter(name => !['.git', 'node_modules', '.dart_tool', '.gradle', '.DS_Store'].includes(name)).length;
          nodes.push({
            name: entry.name,
            path: relativePath,
            type: 'directory',
            childCount,
            modifiedAt: stats.mtime.toISOString(),
          });
        } else if (entry.isFile()) {
          nodes.push({
            name: entry.name,
            path: relativePath,
            type: 'file',
            sizeBytes: stats.size,
            modifiedAt: stats.mtime.toISOString(),
          });
        }
      }
      
      return reply.send(nodes);
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to list directory', details: err.message });
    }
  });

  fastify.get('/content', async (request, reply) => {
    const { path: reqPath = '' } = request.query as { path?: string };
    try {
      const workspaceDir = await getWorkspaceDir(request);
      const targetFile = await validatePath(reqPath, workspaceDir);
      const stats = await fs.stat(targetFile);
      
      if (!stats.isFile()) {
        return reply.status(400).send({ error: 'Target is not a file' });
      }
      
      if (stats.size > 1024 * 1024) {
        return reply.status(400).send({ error: 'File size exceeds 1MB limit' });
      }
      
      const content = await fs.readFile(targetFile, 'utf-8');
      return reply.send({
        content,
        sizeBytes: stats.size,
      });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to read file', details: err.message });
    }
  });

  fastify.get('/tree', async (request, reply) => {
    const { depth = '3' } = request.query as { depth?: string };
    const maxDepth = parseInt(depth, 10);

    try {
      const workspaceDir = await getWorkspaceDir(request);

      const buildTree = async (currentDir: string, currentDepth: number): Promise<any> => {
        const relativePath = path.relative(workspaceDir, currentDir).replace(/\\/g, '/');
        const name = path.basename(currentDir) || 'root';
        
        const stats = await fs.stat(currentDir);
        const node: any = {
          name,
          path: relativePath,
          type: 'directory',
          modifiedAt: stats.mtime.toISOString(),
          children: [],
        };

        if (currentDepth >= maxDepth) {
          return node;
        }

        try {
          const entries = await fs.readdir(currentDir, { withFileTypes: true });
          for (const entry of entries) {
            const isExcluded = ['.git', 'node_modules', '.dart_tool', '.gradle', '.DS_Store'].includes(entry.name);
            if (isExcluded) continue;
            
            const entryPath = path.join(currentDir, entry.name);
            const entryRelativePath = path.relative(workspaceDir, entryPath).replace(/\\/g, '/');
            
            if (entry.isDirectory()) {
              const childNode = await buildTree(entryPath, currentDepth + 1);
              node.children.push(childNode);
            } else if (entry.isFile()) {
              const entryStats = await fs.stat(entryPath);
              node.children.push({
                name: entry.name,
                path: entryRelativePath,
                type: 'file',
                sizeBytes: entryStats.size,
                modifiedAt: entryStats.mtime.toISOString(),
              });
            }
          }
        } catch (e) {
          // Ignore read errors
        }
        return node;
      };

      const rootNode = await buildTree(workspaceDir, 0);
      return reply.send(rootNode);
    } catch (err: any) {
      if (err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to build file tree', details: err.message });
    }
  });

  fastify.post('/', async (request, reply) => {
    const { path: reqPath, type, content = '', workspace, base64Encoded } = request.body as {
      path: string;
      type: 'file' | 'directory';
      content?: string;
      workspace?: string;
      base64Encoded?: boolean;
    };

    if (!reqPath || !type) {
      return reply.status(400).send({ error: 'path and type are required' });
    }

    try {
      const workspaceDir = await getWorkspaceDir({ query: { workspace } });
      const targetPath = await validatePath(reqPath, workspaceDir);

      if (type === 'directory') {
        await fs.mkdir(targetPath, { recursive: true });
      } else {
        // Ensure parent directory exists
        await fs.mkdir(path.dirname(targetPath), { recursive: true });
        if (base64Encoded) {
          await fs.writeFile(targetPath, Buffer.from(content, 'base64'));
        } else {
          await fs.writeFile(targetPath, content, 'utf-8');
        }
      }

      return reply.send({ success: true });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: `Failed to create ${type}`, details: err.message });
    }
  });

  fastify.delete('/', async (request, reply) => {
    const query = (request.query as any) || {};
    const body = (request.body as any) || {};
    const reqPath = query.path || body.path;

    if (!reqPath) {
      return reply.status(400).send({ error: 'path is required' });
    }

    try {
      const workspaceDir = await getWorkspaceDir(request);
      const targetPath = await validatePath(reqPath, workspaceDir);

      const stats = await fs.stat(targetPath);
      if (stats.isDirectory()) {
        await fs.rm(targetPath, { recursive: true, force: true });
      } else {
        await fs.unlink(targetPath);
      }

      return reply.send({ success: true });
    } catch (err: any) {
      if (err.message === 'Path traversal blocked' || err.message === 'Workspace access not allowed') {
        return reply.status(403).send({ error: err.message });
      }
      return reply.status(500).send({ error: 'Failed to delete target', details: err.message });
    }
  });
}
