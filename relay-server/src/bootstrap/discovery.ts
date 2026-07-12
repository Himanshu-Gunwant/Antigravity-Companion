import path from 'path';
import { AntigravityContext } from './types';
import {
  findLanguageServerPid,
  getProcessCommandLine,
  parseCsrfToken,
  parseIdeVersion,
  findListeningPort,
  readProjectId,
  readCdpEndpoint
} from '../utils/process';

export async function discover(workspaceDir: string): Promise<AntigravityContext> {
  const pid = await findLanguageServerPid();
  const cmdLine = await getProcessCommandLine(pid);
  
  const csrfToken = parseCsrfToken(cmdLine);
  const ideVersion = parseIdeVersion(cmdLine);
  
  const lsPorts = await findListeningPort(pid);
  
  const projectId = await readProjectId();
  const cdpWsUrl = await readCdpEndpoint();
  
  const userProfile = process.env.USERPROFILE || '';
  const agentapiBat = path.join(userProfile, '.gemini', 'antigravity', 'bin', 'agentapi.bat');
  const brainDir = path.join(userProfile, '.gemini', 'antigravity', 'brain');
  
  return {
    pid,
    csrfToken,
    lsPorts,
    projectId,
    agentapiBat,
    brainDir,
    workspaceDir,
    cdpWsUrl,
    ideVersion,
    discoveredAt: new Date()
  };
}
