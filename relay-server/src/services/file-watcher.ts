import * as chokidar from 'chokidar';
import EventEmitter from 'events';
import { Service, RelayEvents } from './types';
import { AntigravityContext } from '../bootstrap/types';
import path from 'path';
import { FileChangeEvent } from '../models/file';

export class FileWatcherService extends EventEmitter implements Service {
  private watcher!: chokidar.FSWatcher;
  private workspaceDir!: string;

  public emit<K extends keyof RelayEvents>(event: K, ...args: Parameters<RelayEvents[K]>): boolean {
    return super.emit(event, ...args);
  }
  public on<K extends keyof RelayEvents>(event: K, listener: RelayEvents[K]): this {
    return super.on(event, listener);
  }

  async start(ctx: AntigravityContext): Promise<void> {
    this.workspaceDir = ctx.workspaceDir;

    this.watcher = chokidar.watch(this.workspaceDir, {
      ignored: (filePath: string) => {
        const relative = path.relative(this.workspaceDir, filePath).replace(/\\/g, '/');
        const segments = relative.split('/');
        // Ignore dotfiles/dotfolders, build outputs, and dependency caches
        const ignoredDirs = [
          'node_modules', '.git', 'build', '.dart_tool', '.gradle',
          'dist', '.kotlin', '.idea', '.vscode', '.pub-cache',
          'intermediates', '.transforms', 'generated',
        ];
        return segments.some(s => s.startsWith('.') || ignoredDirs.includes(s));
      },
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 300,
        pollInterval: 100
      }
    });

    const handleEvent = (type: FileChangeEvent['type'], filePath: string) => {
      const relativePath = path.relative(this.workspaceDir, filePath).replace(/\\/g, '/');
      const event: FileChangeEvent = {
        type,
        path: relativePath,
        timestamp: new Date().toISOString()
      };
      this.emit('file:change', event);
    };

    this.watcher.on('add', (p) => handleEvent('add', p));
    this.watcher.on('change', (p) => handleEvent('change', p));
    this.watcher.on('unlink', (p) => handleEvent('unlink', p));
    this.watcher.on('addDir', (p) => handleEvent('addDir', p));
    this.watcher.on('unlinkDir', (p) => handleEvent('unlinkDir', p));
    this.watcher.on('error', (err) => {
      console.error('[FileWatcher] Chokidar error:', err);
    });
  }

  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
    }
  }

  async watchWorkspace(newWorkspace: string, ctx: AntigravityContext): Promise<void> {
    const resolved = path.resolve(newWorkspace);
    if (this.workspaceDir === resolved) return;
    console.log(`[FileWatcher] Switching watched workspace to: ${resolved}`);
    await this.stop();
    await this.start({
      ...ctx,
      workspaceDir: resolved
    });
  }

  onContextRefresh(ctx: AntigravityContext): void {
    if (this.workspaceDir !== ctx.workspaceDir) {
      this.stop().then(() => this.start(ctx));
    }
  }
}
