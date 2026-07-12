import { AntigravityContext } from '../bootstrap/types';
import { FileChangeEvent } from '../models/file';
import { GitStatus } from '../models/git';
import { BuildArtifact } from './build-detector';
import { NotificationPayload } from './notification';

export interface Service {
  start(ctx: AntigravityContext): Promise<void>;
  stop(): Promise<void>;
  onContextRefresh(ctx: AntigravityContext): void;
}

export interface RelayEvents {
  'transcript:step': (conversationId: string, step: any) => void;
  'file:change': (event: FileChangeEvent) => void;
  'git:status-change': (status: GitStatus) => void;
  'build:detected': (artifact: BuildArtifact) => void;
  'notification:send': (payload: NotificationPayload) => void;
}

