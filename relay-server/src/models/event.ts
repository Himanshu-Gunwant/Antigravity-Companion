export interface RawTranscriptStep {
  step_index:  number;
  source:      'USER_EXPLICIT' | 'MODEL' | 'SYSTEM' | string;
  type:        string;              
  status:      'DONE' | 'ERROR' | 'PENDING' | string;
  created_at:  string;              
  content?:    string;              
  thinking?:   string;              
  tool_calls?: Array<{
    name: string;
    args: Record<string, any>;
  }>;
  error?:      string;              
  is_truncated?: boolean;           
}

export interface TranscriptEvent {
  conversationId: string;
  stepIndex:      number;
  source:         'user' | 'model' | 'system';
  category:       EventCategory;
  status:         'done' | 'error' | 'pending';
  timestamp:      string;
  summary:        string;          
  content?:       string;          
  toolCalls?:     ToolCallSummary[];
  error?:         string;
  hasThinking:    boolean;
}

export type EventCategory =
  | 'user_message'       
  | 'agent_response'     
  | 'tool_invocation'    
  | 'tool_result'        
  | 'system_info'        
  | 'error';             

export interface ToolCallSummary {
  name:    string;
  summary: string;     
  action:  string;     
}
