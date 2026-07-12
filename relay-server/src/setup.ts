import fs from 'fs/promises';
import path from 'path';
import crypto from 'crypto';
import bcrypt from 'bcrypt';

async function setup() {
  const envPath = path.resolve('.env');
  const apiKey = crypto.randomBytes(24).toString('hex'); // 48 chars
  const hash = await bcrypt.hash(apiKey, 10);

  let envContent = '';
  try {
    envContent = await fs.readFile(envPath, 'utf-8');
  } catch (err) {
    // File doesn't exist, we will create it
  }

  const workspacePath = 'd:\\Antigravity Companion';
  
  // Parse existing content
  const lines = envContent.split(/\r?\n/);
  const newLines: string[] = [];
  let foundApiKeyHash = false;
  let foundWorkspaceDir = false;

  for (const line of lines) {
    if (line.startsWith('API_KEY_HASH=')) {
      newLines.push(`API_KEY_HASH=${hash}`);
      foundApiKeyHash = true;
    } else if (line.startsWith('WORKSPACE_DIR=')) {
      newLines.push(`WORKSPACE_DIR=${workspacePath}`);
      foundWorkspaceDir = true;
    } else {
      if (line.trim() || line !== '') {
        newLines.push(line);
      }
    }
  }

  if (!foundApiKeyHash) {
    newLines.push(`API_KEY_HASH=${hash}`);
  }
  if (!foundWorkspaceDir) {
    newLines.push(`WORKSPACE_DIR=${workspacePath}`);
  }

  await fs.writeFile(envPath, newLines.join('\n') + '\n', 'utf-8');

  console.log('==================================================');
  console.log('         Antigravity Relay Server Setup          ');
  console.log('==================================================');
  console.log('API key generated successfully and saved to .env.\n');
  console.log('Please copy this key and configure your Flutter app:');
  console.log('\x1b[32m%s\x1b[0m', apiKey);
  console.log('\nKeep this key secure. Re-run setup to rotate keys.');
  console.log('==================================================');
}

setup().catch(console.error);
