import EventEmitter from 'events';
import fs from 'fs';
import path from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';
import { Service, RelayEvents } from './types';
import { AntigravityContext } from '../bootstrap/types';
import { BuildArtifact } from './build-detector';
import { config } from '../config.js';

export interface NotificationPayload {
  category: 'response_ready' | 'error' | 'build_complete' | 'apk_ready';
  title: string;
  body: string;
  conversationId?: string;
  data?: Record<string, string>;
  priority?: 'high' | 'normal';
  deduplicationKey: string;
}

export abstract class NotificationProvider {
  abstract sendNotification(payload: NotificationPayload, tokens: string[], onStaleToken?: (token: string) => void): Promise<void>;
}

export class FcmNotificationProvider extends NotificationProvider {
  private initialized = false;

  constructor(serviceAccountPath: string) {
    super();
    try {
      const resolvedPath = path.resolve(serviceAccountPath);
      if (fs.existsSync(resolvedPath)) {
        initializeApp({
          credential: cert(resolvedPath)
        });
        this.initialized = true;
        console.log(`[FCM] Notification provider initialized using key at: ${resolvedPath}`);
      } else {
        console.warn(`[FCM] Firebase service account key not found at: ${resolvedPath}. Push notifications will not be delivered.`);
      }
    } catch (e) {
      console.error('[FCM] Failed to initialize Firebase Admin SDK:', e);
    }
  }

  async sendNotification(payload: NotificationPayload, tokens: string[], onStaleToken?: (token: string) => void) {
    if (!this.initialized || tokens.length === 0) return;

    const dataStringMap: Record<string, string> = {
      category: payload.category,
      conversationId: payload.conversationId || '',
      deduplicationKey: payload.deduplicationKey
    };
    if (payload.data) {
      for (const [key, val] of Object.entries(payload.data)) {
        dataStringMap[key] = String(val);
      }
    }

    const message: MulticastMessage = {
      tokens,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: dataStringMap,
      android: {
        priority: payload.priority === 'high' ? 'high' : 'normal',
        notification: {
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          sound: 'default',
          icon: 'ic_notification',
        }
      }
    };

    try {
      const response = await getMessaging().sendEachForMulticast(message);
      response.responses.forEach((resp: any, idx: number) => {
        if (!resp.success && resp.error) {
          const errorCode = resp.error.code;
          if (
            errorCode === 'messaging/invalid-registration-token' ||
            errorCode === 'messaging/registration-token-not-registered'
          ) {
            console.log(`[FCM] Marking token as stale: ${tokens[idx]}`);
            if (onStaleToken) {
              onStaleToken(tokens[idx]);
            }
          }
        }
      });
    } catch (e) {
      console.error('[FCM] Error sending multicast message:', e);
    }
  }
}

export interface DeviceToken {
  deviceId: string;
  fcmToken: string;
  platform: 'android' | 'ios';
  updatedAt: string;
  status: 'active' | 'stale';
}

export class TokenStore {
  private filePath: string;
  private tokens: DeviceToken[] = [];

  constructor(workspaceDir: string) {
    this.filePath = path.join(workspaceDir, '.antigravity-tokens.json');
    this.loadTokens();
  }

  private loadTokens() {
    try {
      if (fs.existsSync(this.filePath)) {
        const content = fs.readFileSync(this.filePath, 'utf8');
        this.tokens = JSON.parse(content);
      }
    } catch (e) {
      console.error('[TokenStore] Error loading tokens:', e);
      this.tokens = [];
    }
  }

  private saveTokens() {
    try {
      fs.writeFileSync(this.filePath, JSON.stringify(this.tokens, null, 2), 'utf8');
    } catch (e) {
      console.error('[TokenStore] Error saving tokens:', e);
    }
  }

  public registerToken(deviceId: string, fcmToken: string, platform: 'android' | 'ios') {
    this.tokens = this.tokens.filter(t => t.deviceId !== deviceId && t.fcmToken !== fcmToken);
    this.tokens.push({
      deviceId,
      fcmToken,
      platform,
      updatedAt: new Date().toISOString(),
      status: 'active'
    });
    this.saveTokens();
  }

  public getActiveTokens(): string[] {
    return this.tokens
      .filter(t => t.status === 'active')
      .map(t => t.fcmToken);
  }

  public markAsStale(fcmToken: string) {
    const token = this.tokens.find(t => t.fcmToken === fcmToken);
    if (token) {
      token.status = 'stale';
      token.updatedAt = new Date().toISOString();
      this.saveTokens();
    }
  }
}

export class NotificationService extends EventEmitter implements Service {
  private provider!: FcmNotificationProvider;
  private tokenStore!: TokenStore;
  private recentlySent = new Set<string>();

  constructor() {
    super();
  }

  public emit<K extends keyof RelayEvents>(event: K, ...args: Parameters<RelayEvents[K]>): boolean {
    return super.emit(event, ...args);
  }
  public on<K extends keyof RelayEvents>(event: K, listener: RelayEvents[K]): this {
    return super.on(event, listener);
  }

  async start(ctx: AntigravityContext): Promise<void> {
    this.tokenStore = new TokenStore(ctx.workspaceDir);
    this.provider = new FcmNotificationProvider(config.firebaseServiceAccountPath);
  }

  async stop(): Promise<void> {}
  onContextRefresh(ctx: AntigravityContext): void {}

  public registerDevice(deviceId: string, fcmToken: string, platform: 'android' | 'ios') {
    if (!this.tokenStore) return;
    this.tokenStore.registerToken(deviceId, fcmToken, platform);
  }

  public onTranscriptEvent(conversationId: string, event: any) {
    const payload = this.shouldNotify(conversationId, event);
    if (payload) {
      this.dispatch(payload);
    }
  }

  public onBuildDetected(build: BuildArtifact) {
    this.dispatch({
      category: 'apk_ready',
      title: `${build.name} ready`,
      body: `${build.fileName} (${(build.sizeBytes / 1_048_576).toFixed(1)} MB)`,
      data: { buildId: build.id },
      priority: 'high',
      deduplicationKey: `build_ready_${build.id}`,
    });
  }

  public dispatch(payload: NotificationPayload) {
    if (this.recentlySent.has(payload.deduplicationKey)) return;
    this.recentlySent.add(payload.deduplicationKey);
    setTimeout(() => this.recentlySent.delete(payload.deduplicationKey), 30_000);

    if (!this.tokenStore || !this.provider) return;

    const tokens = this.tokenStore.getActiveTokens();
    this.provider.sendNotification(payload, tokens, (staleToken) => {
      this.tokenStore.markAsStale(staleToken);
    });
  }

  private shouldNotify(conversationId: string, event: any): NotificationPayload | null {
    const category = event.category;
    const status = event.status;
    
    // 1. Notify when Antigravity completes a turn and replies with a final message
    if (category === 'agent_response' && status === 'done' && event.content && event.content.length > 10) {
      return {
        category: 'response_ready',
        title: 'Antigravity responded',
        body: event.content.substring(0, 100),
        conversationId,
        deduplicationKey: `response_${conversationId}_${event.stepIndex ?? Date.now()}`,
      };
    }

    // 2. Notify ONLY on critical system/model errors, ignore normal tool execution errors
    if (category === 'error') {
      return {
        category: 'error',
        title: 'System Error in conversation',
        body: (event.content || event.summary || 'An error occurred').substring(0, 100),
        conversationId,
        priority: 'high',
        deduplicationKey: `error_${conversationId}_${event.stepIndex ?? Date.now()}`,
      };
    }

    return null;
  }
}
