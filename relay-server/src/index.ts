import Fastify from 'fastify';
import { spawn } from 'child_process';
import { discover } from './bootstrap/discovery.js';
import { AgentapiService } from './services/agentapi.js';
import { HealthMonitor } from './bootstrap/health.js';
import { config } from './config.js';
import { authMiddleware } from './middleware/auth.js';
import { conversationsRoutes } from './routes/conversations.js';
import { wsRoutes } from './routes/ws.js';
import { TranscriptWatcherService } from './services/transcript-watcher.js';
import { FileWatcherService } from './services/file-watcher.js';
import { GitService } from './services/git.js';
import { filesRoutes } from './routes/files.js';
import { gitRoutes } from './routes/git.js';
import { systemRoutes } from './routes/system.js';
import { BuildDetectorService } from './services/build-detector.js';
import { NotificationService } from './services/notification.js';
import { buildRoutes } from './routes/builds.js';
import { notificationRoutes } from './routes/notifications.js';
import { accountsRoute } from './routes/accounts.js';
import fastifyWebsocket from '@fastify/websocket';
import { errorHandler } from './middleware/error-handler.js';

const fastify = Fastify({
  ignoreTrailingSlash: true,
  logger: {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true
      }
    }
  }
});

// Register global error handler
fastify.setErrorHandler(errorHandler);

async function main() {
  try {
    console.log('[Bootstrap] Discovering Antigravity runtime...');
    const ctx = await discover(config.workspaceDir);
    console.log(`[Bootstrap] Successfully discovered Antigravity! PID: ${ctx.pid}, Ports: ${ctx.lsPorts.join(', ')}, Project ID: ${ctx.projectId}`);

    // Initialize and start services
    const agentapi = new AgentapiService();
    const transcripts = new TranscriptWatcherService();
    const fileWatcher = new FileWatcherService();
    const gitService = new GitService();
    const buildDetector = new BuildDetectorService();
    const notificationService = new NotificationService();
    const healthMonitor = new HealthMonitor([agentapi, transcripts, fileWatcher, gitService, buildDetector, notificationService]);

    await agentapi.start(ctx);
    await transcripts.start(ctx);
    await fileWatcher.start(ctx);
    await gitService.start(ctx);
    await buildDetector.start(ctx);
    await notificationService.start(ctx);
    await healthMonitor.start(ctx);

    // Event hooks
    transcripts.on('transcript:step', (conversationId, event) => {
      notificationService.onTranscriptEvent(conversationId, event);
    });
    buildDetector.on('build:detected', (build) => {
      notificationService.onBuildDetected(build);
    });
    healthMonitor.on('daemon:status', (isActive) => {
      if (fastify.websocketServer) {
        for (const client of fastify.websocketServer.clients) {
          if (client.readyState === 1 /* OPEN */) {
            client.send(JSON.stringify({ type: 'daemon_status', data: { active: isActive } }));
          }
        }
      }
    });

    // Register websocket support
    await fastify.register(fastifyWebsocket);

    // Public test notification endpoint for testing the pipeline manually
    fastify.post('/api/test-notification', async (request, reply) => {
      const body = (request.body as any) || {};
      const title = body.title || 'Antigravity Test';
      const text = body.body || 'This is a test notification from the server!';
      const category = body.category || 'apk_ready';

      notificationService.dispatch({
        category,
        title,
        body: text,
        priority: 'high',
        deduplicationKey: `test_${Date.now()}`
      });
      return { success: true, message: 'Notification dispatched' };
    });

    fastify.post('/api/system/restart-daemon', async (request, reply) => {
      const body = (request.body as any) || {};
      const execPath = body.executablePath;
      if (!execPath) {
        return reply.code(400).send({ success: false, error: 'executablePath is required' });
      }

      console.log(`[System] Attempting to manually restart daemon...`);
      try {
        // Attempt to kill existing process first if it's frozen
        try {
          const { findLanguageServerPid } = await import('./utils/process.js');
          const { exec } = await import('child_process');
          const { promisify } = await import('util');
          const execAsync = promisify(exec);
          
          const pid = await findLanguageServerPid();
          console.log(`[System] Found frozen/existing daemon at PID ${pid}. Killing it...`);
          await execAsync(`taskkill /F /PID ${pid}`);
          // Wait a second for ports to clear
          await new Promise(resolve => setTimeout(resolve, 1000));
        } catch (e: any) {
          console.log(`[System] No existing daemon found to kill, proceeding to spawn.`);
        }

        console.log(`[System] Spawning fresh daemon from: ${execPath}`);
        const p = spawn(execPath, [], { detached: true, shell: true, stdio: 'ignore' });
        p.unref(); // allow the relay server to exit independently
        return { success: true };
      } catch (err: any) {
        console.error('[System] Failed to spawn daemon:', err);
        return reply.code(500).send({ success: false, error: err.message });
      }
    });

    fastify.get('/api/quota', async (request, reply) => {
      const result = await agentapi.getQuotaSummary();
      if (!result.success) {
        reply.code(500).send(result.error);
        return;
      }
      return result.data;
    });

    // Register authentication middleware
    fastify.addHook('preHandler', authMiddleware);

    // Register routes
    fastify.register(conversationsRoutes, {
      prefix: '/api/conversations',
      agentapi,
      transcripts,
      ctx
    });

    fastify.register(systemRoutes, {
      prefix: '/api/system',
      ctx
    });

    fastify.register(filesRoutes, {
      prefix: '/api/files',
      ctx,
      transcripts,
      fileWatcher
    });

    fastify.register(gitRoutes, {
      prefix: '/api/git',
      gitService,
      transcripts,
      ctx
    });

    fastify.register(buildRoutes, {
      prefix: '/api/builds',
      buildDetector,
      ctx
    });

    fastify.register(notificationRoutes, {
      prefix: '/api/notifications',
      notificationService
    });

    fastify.register(accountsRoute, {
      prefix: '/api/accounts'
    });

    fastify.register(wsRoutes, {
      transcripts,
      fileWatcher,
      gitService,
      buildDetector
    });

    fastify.get('/api/health', async (request, reply) => {
      return {
        status: 'connected',
        antigravityPid: ctx.pid,
        antigravityVersion: ctx.ideVersion,
        workspace: ctx.workspaceDir,
        discoveredAt: ctx.discoveredAt,
      };
    });

    // Handle clean shutdown
    let shuttingDown = false;
    const cleanup = async () => {
      if (shuttingDown) return;
      shuttingDown = true;
      console.log('Shutting down server...');
      await buildDetector.stop();
      await notificationService.stop();
      await fileWatcher.stop();
      await gitService.stop();
      await transcripts.stop();
      await healthMonitor.stop();
      await agentapi.stop();
      await fastify.close();
      console.log('Server shut down cleanly.');
      process.exit(0);
    };

    process.on('SIGINT', cleanup);
    process.on('SIGTERM', cleanup);

    await fastify.listen({ port: config.port, host: '0.0.0.0' });
    console.log(`Relay Server listening on port ${config.port}`);
  } catch (err) {
    console.error('Fatal bootstrap error:', err);
    process.exit(1);
  }
}

main();
