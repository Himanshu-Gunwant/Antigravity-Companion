export interface GitStatus {
  branch:           string;
  upstream:         string | null;
  ahead:            number;
  behind:           number;
  changedFiles:     GitFileStatus[];
  untrackedFiles:   string[];
}

export interface GitFileStatus {
  path:             string;
  status:           'modified' | 'added' | 'deleted' | 'renamed' | 'copied';
  staged:           boolean;
}

export interface GitLogEntry {
  hash:             string;      // full SHA
  shortHash:        string;      // 7-char
  author:           string;
  email:            string;
  timestamp:        number;      // Unix epoch
  message:          string;
}
