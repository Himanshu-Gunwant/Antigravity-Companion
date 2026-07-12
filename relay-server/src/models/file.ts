export interface FileNode {
  name:             string;
  path:             string;      // relative to workspace
  type:             'file' | 'directory';
  sizeBytes?:       number;      // files only
  childCount?:      number;      // directories only
  modifiedAt?:      string;
}

export interface FileChangeEvent {
  type:             'add' | 'change' | 'unlink' | 'addDir' | 'unlinkDir';
  path:             string;      // relative to workspace
  timestamp:        string;
}
