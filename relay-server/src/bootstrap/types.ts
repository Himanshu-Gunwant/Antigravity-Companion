export interface AntigravityContext {
  pid:          number;
  csrfToken:    string;
  lsPorts:      number[];
  projectId:    string;
  agentapiBat:  string;
  brainDir:     string;
  workspaceDir: string;
  cdpWsUrl:     string | null;
  ideVersion:   string;
  discoveredAt: Date;
}
