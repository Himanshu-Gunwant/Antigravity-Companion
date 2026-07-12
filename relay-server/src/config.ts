import dotenv from 'dotenv';
import path from 'path';
import { z } from 'zod';

dotenv.config();

const configSchema = z.object({
  PORT: z.coerce.number().default(3579),
  WORKSPACE_DIR: z.string().default('d:\\Antigravity Companion'),
  API_KEY_HASH: z.string().default(''),
  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().default('credentials/firebase-service-account.json'),
});

const parsed = configSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('Configuration validation error:', parsed.error.format());
  process.exit(1);
}

export const config = {
  port: parsed.data.PORT,
  workspaceDir: path.resolve(parsed.data.WORKSPACE_DIR),
  apiKeyHash: parsed.data.API_KEY_HASH,
  firebaseServiceAccountPath: parsed.data.FIREBASE_SERVICE_ACCOUNT_PATH,
};
