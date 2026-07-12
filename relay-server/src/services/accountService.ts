import fs from 'fs/promises';
import path from 'path';
import { findLanguageServerPid } from '../utils/process.js';
import { exec, spawn } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

const PROFILES_DIR = path.join(process.cwd(), 'credentials', 'profiles');
const CREDENTIAL_TARGET = 'gemini:antigravity';

// PowerShell script to READ the credential from Windows Credential Manager
const READ_CRED_PS = `
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CredReader {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CredReadW(string target, int type, int flags, out IntPtr credential);
    [DllImport("advapi32.dll")]
    public static extern void CredFree(IntPtr credential);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags; public int Type; public string TargetName; public string Comment;
        public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
        public int Persist; public int AttributeCount; public IntPtr Attributes;
        public string TargetAlias; public string UserName;
    }
    public static string Read(string target) {
        IntPtr ptr;
        if (CredReadW(target, 1, 0, out ptr)) {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(ptr);
            var bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, cred.CredentialBlobSize);
            CredFree(ptr);
            return System.Text.Encoding.UTF8.GetString(bytes);
        }
        return "";
    }
}
"@
[CredReader]::Read("${CREDENTIAL_TARGET}")
`;

// PowerShell script template to WRITE a credential to Windows Credential Manager
function makeWriteCredPS(jsonData: string): string {
  // Escape double quotes for embedding in PowerShell
  const escaped = jsonData.replace(/"/g, '`"');
  return `
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CredWriter {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CredWriteW(ref CREDENTIAL credential, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags; public int Type; public string TargetName; public string Comment;
        public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
        public int Persist; public int AttributeCount; public IntPtr Attributes;
        public string TargetAlias; public string UserName;
    }
    public static bool Write(string target, string data, string userName) {
        var bytes = Encoding.UTF8.GetBytes(data);
        var cred = new CREDENTIAL();
        cred.Type = 1;
        cred.TargetName = target;
        cred.UserName = userName;
        cred.CredentialBlobSize = bytes.Length;
        cred.CredentialBlob = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, cred.CredentialBlob, bytes.Length);
        cred.Persist = 2;
        var result = CredWriteW(ref cred, 0);
        Marshal.FreeHGlobal(cred.CredentialBlob);
        return result;
    }
}
"@
[CredWriter]::Write("${CREDENTIAL_TARGET}", "${escaped}", "antigravity")
`;
}

async function ensureProfilesDir() {
  await fs.mkdir(PROFILES_DIR, { recursive: true }).catch(() => {});
}

async function stopAntigravity() {
  console.log(`[AccountService] Stopping Antigravity...`);
  try {
    const pid = await findLanguageServerPid().catch(() => null);
    if (pid) {
      console.log(`[AccountService] Found daemon at PID ${pid}. Killing it...`);
      await execAsync(`taskkill /F /PID ${pid}`).catch(() => {});
    }
    await execAsync(`taskkill /F /IM antigravity.exe`).catch(() => {});
    await new Promise(resolve => setTimeout(resolve, 3000));
  } catch (e) {
    console.log(`[AccountService] Failed to kill daemon:`, e);
  }
}

function startAntigravity(execPath: string) {
  console.log(`[AccountService] Starting Antigravity from: ${execPath}`);
  try {
    const p = spawn(execPath, [], { detached: true, shell: true, stdio: 'ignore' });
    p.unref();
  } catch (err) {
    console.error('[AccountService] Failed to start daemon:', err);
  }
}

async function readCredential(): Promise<string> {
  const tmpScript = path.join(PROFILES_DIR, '_read_cred_tmp.ps1');
  await fs.writeFile(tmpScript, READ_CRED_PS, 'utf-8');
  try {
    const { stdout } = await execAsync(
      `powershell -ExecutionPolicy Bypass -File "${tmpScript}"`,
      { maxBuffer: 10 * 1024 * 1024 }
    );
    return stdout.trim();
  } finally {
    await fs.unlink(tmpScript).catch(() => {});
  }
}

async function writeCredential(jsonData: string): Promise<boolean> {
  // Write the PS script to a temp file to avoid escaping hell
  const tmpScript = path.join(PROFILES_DIR, '_write_cred_tmp.ps1');
  await fs.writeFile(tmpScript, makeWriteCredPS(jsonData), 'utf-8');
  try {
    const { stdout } = await execAsync(
      `powershell -ExecutionPolicy Bypass -File "${tmpScript}"`,
      { maxBuffer: 10 * 1024 * 1024 }
    );
    console.log(`[AccountService] Credential write result: ${stdout.trim()}`);
    return stdout.trim() === 'True';
  } finally {
    await fs.unlink(tmpScript).catch(() => {});
  }
}

export async function extractAccount(profileName: string, executablePath: string) {
  await ensureProfilesDir();
  const profileFile = path.join(PROFILES_DIR, `${profileName}.json`);

  if (await fs.stat(profileFile).catch(() => false)) {
    throw new Error(`Profile "${profileName}" already exists`);
  }

  console.log(`[AccountService] Reading credential from Windows Credential Manager...`);
  const credJson = await readCredential();
  if (!credJson) {
    throw new Error('Could not read credential from Windows Credential Manager');
  }

  // Validate it's valid JSON
  JSON.parse(credJson);

  await fs.writeFile(profileFile, credJson, 'utf-8');
  console.log(`[AccountService] Profile "${profileName}" saved successfully.`);
  return { success: true, profile: profileName };
}

export async function listAccounts() {
  await ensureProfilesDir();
  try {
    const files = await fs.readdir(PROFILES_DIR);
    const profiles = files
      .filter(f => f.endsWith('.json') && !f.startsWith('_'))
      .map(f => f.replace('.json', ''));
    return { success: true, profiles };
  } catch (e) {
    return { success: true, profiles: [] };
  }
}

export async function swapAccount(profileName: string, executablePath: string) {
  const profileFile = path.join(PROFILES_DIR, `${profileName}.json`);
  if (!(await fs.stat(profileFile).catch(() => false))) {
    throw new Error(`Profile "${profileName}" does not exist`);
  }

  const credJson = await fs.readFile(profileFile, 'utf-8');
  // Validate
  JSON.parse(credJson);

  await stopAntigravity();

  console.log(`[AccountService] Writing credential for profile "${profileName}"...`);
  const success = await writeCredential(credJson);
  if (!success) {
    throw new Error('Failed to write credential to Windows Credential Manager');
  }

  startAntigravity(executablePath);
  return { success: true, profile: profileName };
}
