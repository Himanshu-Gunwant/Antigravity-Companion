import * as chokidar from 'chokidar';
import * as path from 'path';
import * as fs from 'fs/promises';
import { randomUUID, createHash } from 'crypto';
import EventEmitter from 'events';
import { Service, RelayEvents } from './types';
import { AntigravityContext } from '../bootstrap/types';

export interface BuildArtifact {
  id: string;
  name: string;
  type: 'apk' | 'aab' | 'web' | 'exe' | 'other';
  fileName: string;
  absolutePath: string;
  sizeBytes: number;
  detectedAt: string;
  modifiedAt: string;
}

interface BuildPattern {
  name: string;
  watchDir: string;
  glob: string;
  type: BuildArtifact['type'];
}

const DEFAULT_PATTERNS: BuildPattern[] = [
  {
    name: 'Flutter APK',
    watchDir: 'mobile_app/build/app/outputs/flutter-apk',
    glob: '**/*.apk',
    type: 'apk',
  },
  {
    name: 'Flutter AAB',
    watchDir: 'mobile_app/build/app/outputs/bundle/release',
    glob: '*.aab',
    type: 'aab',
  },
  {
    name: 'Web Build',
    watchDir: 'mobile_app/build/web',
    glob: 'index.html',
    type: 'web',
  },
  {
    name: 'Dist Build',
    watchDir: 'dist',
    glob: '**/*',
    type: 'other',
  },
  {
    name: 'Release Build',
    watchDir: 'release',
    glob: '**/*',
    type: 'other',
  },
];

export class BuildDetectorService extends EventEmitter implements Service {
  private watchers: chokidar.FSWatcher[] = [];
  private knownBuilds = new Map<string, BuildArtifact>();
  private maxHistory = 20;
  
  public emit<K extends keyof RelayEvents>(event: K, ...args: Parameters<RelayEvents[K]>): boolean {
    return super.emit(event, ...args);
  }
  public on<K extends keyof RelayEvents>(event: K, listener: RelayEvents[K]): this {
    return super.on(event, listener);
  }

  async start(ctx: AntigravityContext): Promise<void> {
    for (const pattern of DEFAULT_PATTERNS) {
      const watchPath = path.join(ctx.workspaceDir, pattern.watchDir);
      
      try {
        await fs.mkdir(watchPath, { recursive: true });
      } catch (e) {
        // ignore
      }

      const watcher = chokidar.watch(
        watchPath,
        { 
          ignoreInitial: false, 
          awaitWriteFinish: { stabilityThreshold: 2000 },
          ignored: ['**/*.dm', '**/*.tmp', '**/baselineProfiles/**'],
        }
      );

      const filterMatch = (filePath: string): boolean => {
        const normalized = filePath.replace(/\\/g, '/');
        if (pattern.glob === '**/*') return true;
        if (pattern.glob === '*.apk' || pattern.glob === '**/*.apk') return normalized.endsWith('.apk');
        if (pattern.glob === '*.aab') return normalized.endsWith('.aab');
        if (pattern.glob === 'index.html') return normalized.endsWith('index.html');
        return normalized.endsWith(pattern.glob);
      };

      watcher.on('add', (filePath) => {
        if (filterMatch(filePath)) this.onArtifactDetected(pattern, filePath);
      });
      watcher.on('change', (filePath) => {
        if (filterMatch(filePath)) this.onArtifactDetected(pattern, filePath);
      });
      watcher.on('error', (error) => {
        console.error(`[BuildDetector] Chokidar watcher error for ${pattern.name}:`, error);
      });
      this.watchers.push(watcher);
    }
  }

  async stop(): Promise<void> {
    for (const watcher of this.watchers) {
      await watcher.close();
    }
    this.watchers = [];
  }

  onContextRefresh(ctx: AntigravityContext): void {
    this.stop().then(() => this.start(ctx));
  }

  private async onArtifactDetected(pattern: BuildPattern, filePath: string) {
    try {
      const stat = await fs.stat(filePath);
      if (!stat.isFile()) return; // skip directories
      
      const id = createHash('md5').update(filePath).digest('hex');

      const artifact: BuildArtifact = {
        id,
        name: pattern.name,
        type: pattern.type,
        fileName: path.basename(filePath),
        absolutePath: filePath,
        sizeBytes: stat.size,
        detectedAt: new Date().toISOString(),
        modifiedAt: stat.mtime.toISOString(),
      };

      if (this.knownBuilds.has(id)) {
        this.knownBuilds.delete(id); // remove to put it at the end (newest)
      }
      this.knownBuilds.set(id, artifact);

      // Enforce max 20
      if (this.knownBuilds.size > this.maxHistory) {
        const firstKey = this.knownBuilds.keys().next().value;
        if (firstKey) this.knownBuilds.delete(firstKey);
      }

      this.emit('build:detected', artifact);
    } catch (e) {
      console.error('Error detecting artifact stat', e);
    }
  }

  listBuilds(): BuildArtifact[] {
    return Array.from(this.knownBuilds.values()).reverse(); // Newest first
  }

  getBuild(id: string): BuildArtifact | undefined {
    return this.knownBuilds.get(id);
  }
}
