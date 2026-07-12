import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import fs from 'fs/promises';

const execAsync = promisify(exec);

export async function findLanguageServerPid(): Promise<number> {
  const { stdout } = await execAsync('powershell -NoProfile -Command "(Get-Process -Name language_server -ErrorAction Stop).Id"');
  const pid = parseInt(stdout.trim(), 10);
  if (isNaN(pid)) {
    throw new Error('language_server process not found or returned invalid PID');
  }
  return pid;
}

export async function getProcessCommandLine(pid: number): Promise<string> {
  const { stdout } = await execAsync(`powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \\"ProcessId = ${pid}\\").CommandLine"`);
  return stdout.trim();
}

export function parseCsrfToken(cmdLine: string): string {
  const match = cmdLine.match(/--csrf_token\s+([0-9a-fA-F\-]{36})/);
  if (!match) {
    throw new Error('Could not find --csrf_token in command line');
  }
  return match[1];
}

export function parseIdeVersion(cmdLine: string): string {
  const match = cmdLine.match(/--override_ide_version\s+(\S+)/);
  if (!match) {
    return 'unknown';
  }
  return match[1];
}

export async function findListeningPort(pid: number): Promise<number[]> {
  const { stdout } = await execAsync(`netstat -aon | findstr LISTENING | findstr ${pid}`);
  const lines = stdout.split('\n').filter(l => l.trim().length > 0);
  const ports: number[] = [];
  
  for (const line of lines) {
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 2) {
      const localAddress = parts[1];
      const portStr = localAddress.split(':').pop();
      if (portStr) {
        ports.push(parseInt(portStr, 10));
      }
    }
  }
  
  if (ports.length === 0) {
    throw new Error(`Could not find listening port for PID ${pid}`);
  }
  
  return ports;
}

export async function readProjectId(): Promise<string> {
  const appData = process.env.APPDATA || path.join(process.env.USERPROFILE || '', 'AppData', 'Roaming');
  const storagePath = path.join(appData, 'Antigravity', 'app_storage.json');
  
  try {
    const content = await fs.readFile(storagePath, 'utf-8');
    const data = JSON.parse(content);
    if (data.lastCreatedProjectId) {
      return data.lastCreatedProjectId;
    }
    throw new Error('lastCreatedProjectId not found in app_storage.json');
  } catch (error: any) {
    throw new Error(`Failed to read project ID: ${error.message}`);
  }
}

export async function readCdpEndpoint(): Promise<string | null> {
  const appData = process.env.APPDATA || path.join(process.env.USERPROFILE || '', 'AppData', 'Roaming');
  const portPath = path.join(appData, 'Antigravity', 'DevToolsActivePort');
  
  try {
    const content = await fs.readFile(portPath, 'utf-8');
    const lines = content.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length >= 2) {
      const port = lines[0];
      const p = lines[1];
      return `ws://127.0.0.1:${port}${p}`;
    }
    return null;
  } catch (error) {
    return null; 
  }
}
