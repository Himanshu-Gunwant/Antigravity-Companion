import { execFile } from 'child_process';
import { promisify } from 'util';
import { Mutex } from 'async-mutex';
import EventEmitter from 'events';
import { Service, RelayEvents } from './types';
import { AntigravityContext } from '../bootstrap/types';
import { GitStatus, GitFileStatus, GitLogEntry } from '../models/git';
import { validatePath } from '../routes/files';

const execFileAsync = promisify(execFile);

export class GitService extends EventEmitter implements Service {
  private workspaceDir!: string;
  private writeLock = new Mutex();

  public emit<K extends keyof RelayEvents>(event: K, ...args: Parameters<RelayEvents[K]>): boolean {
    return super.emit(event, ...args);
  }
  public on<K extends keyof RelayEvents>(event: K, listener: RelayEvents[K]): this {
    return super.on(event, listener);
  }

  async start(ctx: AntigravityContext): Promise<void> {
    this.workspaceDir = ctx.workspaceDir;
  }

  async stop(): Promise<void> {
    // Nothing to stop
  }

  onContextRefresh(ctx: AntigravityContext): void {
    this.workspaceDir = ctx.workspaceDir;
  }

  // ALLOWED GIT SUBCOMMANDS — whitelist
  private static ALLOWED_READ = new Set([
    'status', 'diff', 'log', 'show', 'branch', 'remote', 'rev-parse', 'ls-files'
  ]);
  private static ALLOWED_WRITE = new Set([
    'add', 'commit', 'push', 'pull', 'checkout', 'stash', 'restore'
  ]);

  private async execGitRaw(args: string[], workspaceDir = this.workspaceDir): Promise<string> {
    const subcommand = args[0];
    if (!GitService.ALLOWED_READ.has(subcommand) &&
        !GitService.ALLOWED_WRITE.has(subcommand)) {
      throw new Error(`Git subcommand "${subcommand}" not allowed`);
    }
    
    try {
      const { stdout } = await execFileAsync('git', args, { 
        cwd: workspaceDir,
        maxBuffer: 10 * 1024 * 1024 // 10MB
      });
      return stdout;
    } catch (err: any) {
      throw new Error(err.stderr || err.message);
    }
  }

  // READ operations: no lock needed, safe to run concurrently
  async status(workspaceDir = this.workspaceDir): Promise<GitStatus> {
    const stdout = await this.execGitRaw(['status', '--porcelain=v2', '--branch'], workspaceDir);
    return this.parseStatus(stdout);
  }

  async diff(file?: string, staged?: boolean, workspaceDir = this.workspaceDir): Promise<string> {
    const args = ['diff', '--no-color'];
    if (staged) {
      args.push('--staged');
    }
    if (file) {
      await validatePath(file, workspaceDir);
      args.push('--', file);
    }
    return this.execGitRaw(args, workspaceDir);
  }

  async log(count: number = 20, workspaceDir = this.workspaceDir): Promise<GitLogEntry[]> {
    const raw = await this.execGitRaw([
      'log', `--max-count=${count}`,
      '--format=%H%n%h%n%an%n%ae%n%at%n%s%n---END---'
    ], workspaceDir);
    return this.parseLog(raw);
  }

  async show(commitHash: string, file?: string, workspaceDir = this.workspaceDir): Promise<string> {
    if (!/^[0-9a-f]{7,40}$/.test(commitHash)) {
      throw new Error('Invalid commit hash');
    }
    const args = ['show', '--no-color', commitHash];
    if (file) {
      await validatePath(file, workspaceDir);
      args.push('--', file);
    }
    return this.execGitRaw(args, workspaceDir);
  }

  // WRITE operations: serialized via lock
  async add(files: string[], workspaceDir = this.workspaceDir): Promise<void> {
    return this.writeLock.runExclusive(async () => {
      for (const f of files) {
        await validatePath(f, workspaceDir);
      }
      await this.execGitRaw(['add', '--', ...files], workspaceDir);
      await this.triggerStatusChange(workspaceDir);
    });
  }

  async commit(message: string, workspaceDir = this.workspaceDir): Promise<string> {
    return this.writeLock.runExclusive(async () => {
      const result = await this.execGitRaw(['commit', '-m', message], workspaceDir);
      await this.triggerStatusChange(workspaceDir);
      return result;
    });
  }

  async push(remote = 'origin', branch?: string, workspaceDir = this.workspaceDir): Promise<string> {
    return this.writeLock.runExclusive(async () => {
      const args = ['push', remote];
      if (branch) args.push(branch);
      const result = await this.execGitRaw(args, workspaceDir);
      await this.triggerStatusChange(workspaceDir);
      return result;
    });
  }

  async pull(remote = 'origin', branch?: string, workspaceDir = this.workspaceDir): Promise<string> {
    return this.writeLock.runExclusive(async () => {
      const args = ['pull', '--ff-only', remote];
      if (branch) args.push(branch);
      const result = await this.execGitRaw(args, workspaceDir);
      await this.triggerStatusChange(workspaceDir);
      return result;
    });
  }

  private async triggerStatusChange(workspaceDir = this.workspaceDir) {
    try {
      const currentStatus = await this.status(workspaceDir);
      this.emit('git:status-change', currentStatus);
    } catch (e) {
      // Ignore
    }
  }

  private parseStatus(stdout: string): GitStatus {
    const lines = stdout.split('\n');
    let branch = 'unknown';
    let upstream: string | null = null;
    let ahead = 0;
    let behind = 0;
    const changedFiles: GitFileStatus[] = [];
    const untrackedFiles: string[] = [];

    for (const line of lines) {
      if (!line.trim()) continue;

      if (line.startsWith('#')) {
        const parts = line.split(' ');
        if (parts[1] === 'branch.head') {
          branch = parts[2];
        } else if (parts[1] === 'branch.upstream') {
          upstream = parts[2];
        } else if (parts[1] === 'branch.ab') {
          // Git porcelain v2: "# branch.ab +3 -1" → parts[2]="+3", parts[3]="-1"
          const abString = parts.slice(2).join(' ');
          const match = abString.match(/\+([0-9]+)\s*-([0-9]+)/);
          if (match) {
            ahead = parseInt(match[1], 10);
            behind = parseInt(match[2], 10);
          }
        }
      } else if (line.startsWith('1 ')) {
        const parts = line.split(/\s+/);
        const status = parts[1]; // XY
        const filePath = parts[8];
        const staged = status[0] !== '.' && status[0] !== ' ';
        const isModified = status[1] === 'M' || status[0] === 'M';
        const isAdded = status[0] === 'A';
        const isDeleted = status[1] === 'D' || status[0] === 'D';
        
        let gitStatus: GitFileStatus['status'] = 'modified';
        if (isAdded) gitStatus = 'added';
        else if (isDeleted) gitStatus = 'deleted';

        changedFiles.push({
          path: filePath,
          status: gitStatus,
          staged,
        });
      } else if (line.startsWith('2 ')) {
        const parts = line.split(/\s+/);
        const status = parts[1];
        const filePath = parts[9];
        const staged = status[0] !== '.' && status[0] !== ' ';
        changedFiles.push({
          path: filePath,
          status: status[0] === 'R' ? 'renamed' : 'copied',
          staged,
        });
      } else if (line.startsWith('? ')) {
        const filePath = line.substring(2);
        untrackedFiles.push(filePath);
      }
    }

    return { branch, upstream, ahead, behind, changedFiles, untrackedFiles };
  }

  private parseLog(raw: string): GitLogEntry[] {
    const entries: GitLogEntry[] = [];
    const blocks = raw.split('\n---END---\n');
    for (const block of blocks) {
      const lines = block.trim().split('\n');
      if (lines.length < 6) continue;
      entries.push({
        hash: lines[0],
        shortHash: lines[1],
        author: lines[2],
        email: lines[3],
        timestamp: parseInt(lines[4], 10),
        message: lines.slice(5).join('\n'),
      });
    }
    return entries;
  }
}
