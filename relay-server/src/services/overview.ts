import fs from 'fs/promises';
import path from 'path';

export interface OverviewData {
  subagents: SubagentInfo[];
  filesChanged: FileChangeInfo[];
  artifacts: ArtifactInfo[];
  backgroundTasks: BackgroundTaskInfo[];
}

export interface SubagentInfo {
  name: string;
  id: string;
}

export interface FileChangeInfo {
  path: string;
  additions: number;
  deletions: number;
}

export interface ArtifactInfo {
  name: string;
  path: string;
  iconType: 'document' | 'media';
}

export interface BackgroundTaskInfo {
  command: string;
  status: 'running' | 'completed';
}

export class OverviewService {
  private brainDir: string;

  constructor(brainDir: string) {
    this.brainDir = brainDir;
  }

  async getConversationOverview(conversationId: string): Promise<OverviewData> {
    const convDir = path.join(this.brainDir, conversationId);
    
    const overview: OverviewData = {
      subagents: [],
      filesChanged: [],
      artifacts: [],
      backgroundTasks: []
    };

    try {
      // 1. Parse Artifacts
      const files = await fs.readdir(convDir);
      for (const file of files) {
        if (file.endsWith('.metadata.json')) continue;
        if (file.endsWith('.md') || file.endsWith('.png') || file.endsWith('.jpg')) {
          const stats = await fs.stat(path.join(convDir, file));
          const isMedia = file.endsWith('.png') || file.endsWith('.jpg');
          
          let displayName = file.replace(/\.md$/, '');
          if (isMedia && displayName.startsWith('media__')) {
            displayName = `Media (${stats.mtime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })})`;
          } else {
            // Capitalize title
            displayName = displayName.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
          }

          overview.artifacts.push({
            name: displayName,
            path: `file:///${path.join(convDir, file).replace(/\\/g, '/')}`,
            iconType: isMedia ? 'media' : 'document'
          });
        }
      }
    } catch (e) {
      console.error(`Failed to read artifacts for ${conversationId}`, e);
    }

    try {
      // 2. Parse Transcript for Tasks, Files, Subagents
      const transcriptPath = path.join(convDir, '.system_generated', 'logs', 'transcript.jsonl');
      const content = await fs.readFile(transcriptPath, 'utf-8');
      const lines = content.split('\n');

      const fileMap = new Map<string, { additions: number, deletions: number }>();
      const activeTasks = new Map<string, BackgroundTaskInfo>();
      const pendingSubagents: { name: string; type: string }[] = [];

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const step = JSON.parse(line);
          
          if (step.content && typeof step.content === 'string') {
            const startMatch = step.content.match(/Tool is running as a background task with task id: ([^\s]+)/);
            if (startMatch) {
              const taskId = startMatch[1].trim();
              const descMatch = step.content.match(/Task Description: ([^\n]+)/);
              const desc = descMatch ? descMatch[1].trim() : 'Background Task';
              activeTasks.set(taskId, { command: desc, status: 'running' });
            }
            
            const endMatch = step.content.match(/Task id "([^"]+)" finished/);
            if (endMatch) {
              activeTasks.delete(endMatch[1]);
            }
            
            const cancelMatch = step.content.match(/Task id "([^"]+)" was canceled/);
            if (cancelMatch) {
              activeTasks.delete(cancelMatch[1]);
            }
          }

          // Parse actual subagent conversation IDs from the INVOKE_SUBAGENT tool result
          if (step.type === 'INVOKE_SUBAGENT' && step.content) {
            const jsonMatches = step.content.match(/\{[\s\S]*?\}/g);
            if (jsonMatches) {
              for (const jsonStr of jsonMatches) {
                try {
                  const subagentResult = JSON.parse(jsonStr);
                  if (subagentResult && subagentResult.conversationId) {
                    const pending = pendingSubagents.shift();
                    overview.subagents.push({
                      name: pending ? pending.name : 'Subagent',
                      id: subagentResult.conversationId
                    });
                  }
                } catch (e) {}
              }
            }
          }

          if (step.tool_calls && Array.isArray(step.tool_calls)) {
            for (const call of step.tool_calls) {
              const args = call.args || {};
              
              if (call.name === 'invoke_subagent') {
                let subagentsList: any[] = [];
                if (typeof args.Subagents === 'string') {
                  try {
                    subagentsList = JSON.parse(args.Subagents);
                  } catch (e) {}
                } else if (Array.isArray(args.Subagents)) {
                  subagentsList = args.Subagents;
                }
                
                for (const agent of subagentsList) {
                  pendingSubagents.push({
                    name: agent.Role || agent.TypeName || 'Subagent',
                    type: agent.TypeName || 'Unknown'
                  });
                }
              } else if (call.name === 'write_to_file' && args.TargetFile) {
                const target = args.TargetFile;
                const linesCount = args.CodeContent ? args.CodeContent.split('\\n').length : 0;
                const current = fileMap.get(target) || { additions: 0, deletions: 0 };
                current.additions += linesCount;
                fileMap.set(target, current);
              } else if (call.name === 'replace_file_content' && args.TargetFile) {
                const target = args.TargetFile;
                const del = (args.EndLine || 0) - (args.StartLine || 0) + 1;
                const add = args.ReplacementContent ? args.ReplacementContent.split('\\n').length : 0;
                const current = fileMap.get(target) || { additions: 0, deletions: 0 };
                current.additions += add;
                current.deletions += del;
                fileMap.set(target, current);
              } else if (call.name === 'multi_replace_file_content' && args.TargetFile) {
                const target = args.TargetFile;
                let add = 0;
                let del = 0;
                if (args.ReplacementChunks && Array.isArray(args.ReplacementChunks)) {
                  for (const chunk of args.ReplacementChunks) {
                    del += (chunk.EndLine || 0) - (chunk.StartLine || 0) + 1;
                    add += chunk.ReplacementContent ? chunk.ReplacementContent.split('\\n').length : 0;
                  }
                }
                const current = fileMap.get(target) || { additions: 0, deletions: 0 };
                current.additions += add;
                current.deletions += del;
                fileMap.set(target, current);
              }
            }
          }
        } catch (e) {
          // ignore parse errors for a line
        }
      }

      fileMap.forEach((stats, path) => {
        overview.filesChanged.push({
          path,
          additions: stats.additions,
          deletions: stats.deletions
        });
      });

      overview.backgroundTasks = Array.from(activeTasks.values());

    } catch (e) {
      console.error(`Failed to parse transcript for ${conversationId}`, e);
    }

    return overview;
  }
}
