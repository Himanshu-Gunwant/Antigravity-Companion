import { FastifyInstance, FastifyRequest } from 'fastify';
import bcrypt from 'bcrypt';
import { TranscriptWatcherService } from '../services/transcript-watcher';
import { FileWatcherService } from '../services/file-watcher';
import { GitService } from '../services/git';
import { FileChangeEvent } from '../models/file';
import { GitStatus } from '../models/git';
import { config } from '../config';
import { BuildDetectorService, BuildArtifact } from '../services/build-detector';

export async function wsRoutes(
  fastify: FastifyInstance,
  options: { 
    transcripts: TranscriptWatcherService;
    fileWatcher?: FileWatcherService;
    gitService?: GitService;
    buildDetector?: BuildDetectorService;
  }
) {
  fastify.get('/ws', { websocket: true }, (connection: any, req: FastifyRequest) => {
    const socket = connection.socket || connection;
    const token = (req.query as any).token;

    // Queue messages that arrive while we're doing async auth
    const pendingMessages: (Buffer | string)[] = [];
    let authenticated = false;

    const subscriptions = new Set<string>();

    const onTranscriptStep = (conversationId: string, step: any) => {
      if (subscriptions.has('transcript_all') || subscriptions.has(`transcript:${conversationId}`)) {
        socket.send(JSON.stringify({ type: 'step', data: step }));
      }
    };

    const onFileChange = (event: FileChangeEvent) => {
      if (subscriptions.has('files')) {
        socket.send(JSON.stringify({ type: 'file_change', data: event }));
      }
    };

    const onGitStatusChange = (status: GitStatus) => {
      if (subscriptions.has('git')) {
        socket.send(JSON.stringify({ type: 'git_status', data: status }));
      }
    };

    const onBuildDetected = (artifact: BuildArtifact) => {
      if (subscriptions.has('builds')) {
        socket.send(JSON.stringify({ type: 'build_detected', data: artifact }));
      }
    };

    function processMessage(raw: Buffer | string) {
      try {
        const message = typeof raw === 'string' ? raw : raw.toString('utf-8');
        const msg = JSON.parse(message);
        
        if (msg.type === 'ping') {
          socket.send(JSON.stringify({ type: 'pong' }));
        } else if (msg.type === 'subscribe') {
          if (!Array.isArray(msg.channels)) return;
          for (const channel of msg.channels) {
            if (channel.kind === 'transcript_all') {
              subscriptions.add('transcript_all');
            } else if (channel.kind === 'transcript' && channel.conversationId) {
              subscriptions.add(`transcript:${channel.conversationId}`);
              console.log(`[WS] Client subscribed to transcript:${channel.conversationId}`);
            } else if (channel.kind === 'files') {
              subscriptions.add('files');
              console.log(`[WS] Client subscribed to files`);
            } else if (channel.kind === 'git') {
              subscriptions.add('git');
              console.log(`[WS] Client subscribed to git`);
            } else if (channel.kind === 'builds') {
              subscriptions.add('builds');
              console.log(`[WS] Client subscribed to builds`);
            }
          }
        } else if (msg.type === 'unsubscribe') {
          if (!Array.isArray(msg.channels)) return;
          for (const channel of msg.channels) {
            if (channel.kind === 'transcript_all') {
              subscriptions.delete('transcript_all');
            } else if (channel.kind === 'transcript' && channel.conversationId) {
              subscriptions.delete(`transcript:${channel.conversationId}`);
            } else if (channel.kind === 'files') {
              subscriptions.delete('files');
            } else if (channel.kind === 'git') {
              subscriptions.delete('git');
            } else if (channel.kind === 'builds') {
              subscriptions.delete('builds');
            }
          }
        }
      } catch (err) {
        console.warn('[WS] Failed to parse message:', (err as Error).message);
      }
    }

    // Register message handler IMMEDIATELY (before async auth)
    // to avoid losing messages during bcrypt.compare()
    socket.on('message', (raw: Buffer | string) => {
      if (authenticated) {
        processMessage(raw);
      } else {
        // Queue the message — will be replayed after auth succeeds
        if (pendingMessages.length < 100) {
          pendingMessages.push(raw);
        } else {
          console.warn('[WS] Pending message queue full, dropping message');
        }
      }
    });

    let isClosed = false;
    socket.on('close', () => {
      isClosed = true;
      options.transcripts.removeListener('transcript:step', onTranscriptStep);
      if (options.fileWatcher) {
        options.fileWatcher.removeListener('file:change', onFileChange);
      }
      if (options.gitService) {
        options.gitService.removeListener('git:status-change', onGitStatusChange);
      }
      if (options.buildDetector) {
        options.buildDetector.removeListener('build:detected', onBuildDetected);
      }
    });

    // Now do async auth
    if (!token || !config.apiKeyHash) {
      socket.close(1008, 'Unauthorized');
      return;
    }

    bcrypt.compare(token, config.apiKeyHash).then(valid => {
      if (!valid) {
        socket.close(1008, 'Unauthorized');
        return;
      }

      // Auth succeeded — set up event forwarding and replay queued messages
      authenticated = true;
      if (isClosed) return; // Don't add listener to closed socket
      options.transcripts.on('transcript:step', onTranscriptStep);
      if (options.fileWatcher) {
        options.fileWatcher.on('file:change', onFileChange);
      }
      if (options.gitService) {
        options.gitService.on('git:status-change', onGitStatusChange);
      }
      if (options.buildDetector) {
        options.buildDetector.on('build:detected', onBuildDetected);
      }
      
      console.log(`[WS] Auth OK, replaying ${pendingMessages.length} queued messages`);
      
      // Replay any messages that arrived during auth
      for (const msg of pendingMessages) {
        processMessage(msg);
      }
      pendingMessages.length = 0;
    }).catch(() => {
      socket.close(1008, 'Unauthorized');
    });
  });
}
