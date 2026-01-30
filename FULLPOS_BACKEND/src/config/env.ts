import { config } from 'dotenv';
import { z } from 'zod';

config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(4000),
  DATABASE_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(16),
  JWT_REFRESH_SECRET: z.string().min(16),
  JWT_ACCESS_EXPIRES_IN: z.string().default('15m'),
  JWT_REFRESH_EXPIRES_IN: z.string().default('7d'),
  CORS_ORIGINS: z.string().optional(),
  OVERRIDE_API_KEY: z.string().optional(),
  ALLOW_PUBLIC_CLOUD: z.coerce.boolean().optional(),
  // Clave maestra para derivar el secret del token virtual (TOTP) por terminal.
  // Si no está configurada, el token virtual queda deshabilitado.
  VIRTUAL_TOKEN_MASTER_KEY: z.string().min(16).optional(),
  // Uploads
  UPLOADS_DIR: z.string().optional(),
  PUBLIC_BASE_URL: z.string().url().optional(),
  MAX_PRODUCT_IMAGES_PER_COMPANY: z.coerce.number().int().min(1).optional(),
  MAX_UPLOAD_IMAGE_MB: z.coerce.number().int().min(1).optional(),
  MAX_IMAGE_WIDTH: z.coerce.number().int().min(200).optional(),
  MAX_IMAGE_HEIGHT: z.coerce.number().int().min(200).optional(),
  MAX_BACKUP_MB: z.coerce.number().int().min(10).optional(),
  BACKUPS_DIR: z.string().optional(),
  BACKUPS_TMP_DIR: z.string().optional(),
  OWNER_APP_ANDROID_URL: z.string().optional(),
  OWNER_APP_IOS_URL: z.string().optional(),
  OWNER_APP_VERSION: z.string().optional(),
  DANGER_ACTION_PIN: z.string().min(4).optional()
});

const env = envSchema.parse(process.env);

export const corsOrigins =
  env.CORS_ORIGINS?.split(',').map((origin) => origin.trim()).filter(Boolean) ?? ['*'];

export default env;
