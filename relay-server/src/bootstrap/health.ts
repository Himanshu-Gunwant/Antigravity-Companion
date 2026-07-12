import { Service } from '../services/types.js';
import { AntigravityContext } from './types.js';
import { findLanguageServerPid } from '../utils/process.js';
import { discover } from './discovery.js';
import { EventEmitter } from 'events';

export class HealthMonitor extends EventEmitter implements Service {
  private ctx!: AntigravityContext;
  private intervalId: NodeJS.Timeout | null = null;
  private services: Service[];

  constructor(services: Service[]) {
    super();
    this.services = services;
  }

  async start(ctx: AntigravityContext): Promise<void> {
    this.ctx = ctx;
    this.startPolling();
  }

  async stop(): Promise<void> {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  onContextRefresh(ctx: AntigravityContext): void {
    this.ctx = ctx;
  }

  private startPolling() {
    let lastDaemonActiveState = true;

    this.intervalId = setInterval(async () => {
      try {
        const currentPid = await findLanguageServerPid();
        
        // If we were offline and now we found it, broadcast recovery
        if (!lastDaemonActiveState) {
          lastDaemonActiveState = true;
          this.emit('daemon:status', true);
        }

        if (currentPid !== this.ctx?.pid) {
          console.warn(`[HealthMonitor] Antigravity PID changed from ${this.ctx?.pid} to ${currentPid}. Initiating re-bootstrap...`);
          this.emit('health:reconnecting');
          
          const newCtx = await discover(this.ctx?.workspaceDir || process.cwd());
          
          console.log(`[HealthMonitor] Re-bootstrap successful. New PID: ${newCtx.pid}, New CSRF Token acquired.`);
          
          // Notify all registered services
          for (const service of this.services) {
            if (service.onContextRefresh) {
              service.onContextRefresh(newCtx);
            }
          }
          
          this.ctx = newCtx;
          this.emit('health:reconnected', newCtx);
        }
      } catch (err: any) {
        // Handle gracefully if daemon is dead
        const errMsg = (err.message || '').toLowerCase();
        if (errMsg.includes('not found') || errMsg.includes('cannot find a process') || errMsg.includes('objectnotfound')) {
          if (lastDaemonActiveState) {
            console.warn('[HealthMonitor] Antigravity daemon is offline/crashed. Waiting for restart...');
            lastDaemonActiveState = false;
            this.emit('daemon:status', false);
          }
        } else {
          console.error('[HealthMonitor] Error during health check/bootstrap:', err);
        }
      }
    }, 15000); // Check every 15 seconds
  }
}
