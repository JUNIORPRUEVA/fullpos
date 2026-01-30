import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import env from '../../config/env';
import { prisma } from '../../config/prisma';

const backupsRoot = env.BACKUPS_DIR?.trim() || path.join(process.cwd(), 'uploads', 'backups');

function normalizeRnc(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

async function resolveCompanyId(companyRnc?: string, companyCloudId?: string) {
  const rnc = companyRnc?.trim() ?? '';
  const cloudId = companyCloudId?.trim() ?? '';
  if (!rnc && !cloudId) return null;

  if (cloudId) {
    const byCloud = await prisma.company.findFirst({
      where: { cloudCompanyId: cloudId },
      select: { id: true },
    });
    if (byCloud) return byCloud.id;
  }

  if (!rnc) return null;
  const byRnc = await prisma.company.findFirst({
    where: { rnc },
    select: { id: true },
  });
  if (byRnc) return byRnc.id;

  const normalized = normalizeRnc(rnc);
  if (!normalized) return null;
  const candidates = await prisma.company.findMany({
    where: { rnc: { not: null } },
    select: { id: true, rnc: true },
  });
  const match = candidates.find(
    (item) => item.rnc != null && normalizeRnc(item.rnc) === normalized,
  );
  return match?.id ?? null;
}

async function computeSha256(filePath: string) {
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(filePath);
  await new Promise<void>((resolve, reject) => {
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve());
  });
  return hash.digest('hex');
}

export async function createBackup({
  tempFilePath,
  sizeBytes,
  checksumSha256,
  dbVersion,
  appVersion,
  companyRnc,
  companyCloudId,
  deviceId,
  userId,
}: {
  tempFilePath: string;
  sizeBytes: number;
  checksumSha256: string;
  dbVersion: number;
  appVersion: string;
  companyRnc?: string;
  companyCloudId?: string;
  deviceId?: string;
  userId?: number;
}) {
  const companyId = await resolveCompanyId(companyRnc, companyCloudId);
  if (!companyId) {
    return { ok: false, message: 'Empresa requerida' };
  }

  const computed = await computeSha256(tempFilePath);
  if (checksumSha256 && checksumSha256 !== computed) {
    return { ok: false, message: 'Checksum no coincide' };
  }

  const id = crypto.randomUUID();
  const companyDir = path.join(backupsRoot, String(companyId));
  if (!fs.existsSync(companyDir)) {
    fs.mkdirSync(companyDir, { recursive: true });
  }
  const filename = `backup_${id}.zip`;
  const storagePath = path.join(companyDir, filename);
  await fs.promises.rename(tempFilePath, storagePath);

  await prisma.cloudBackup.create({
    data: {
      id,
      companyId,
      sizeBytes,
      sha256: checksumSha256 || computed,
      dbVersion,
      appVersion,
      storagePath,
      status: 'SUCCESS',
    },
  });

  await prisma.auditLog.create({
    data: {
      companyId,
      actionCode: 'BACKUP_CREATE',
      result: 'SUCCESS',
      method: 'CLOUD',
      terminalId: deviceId,
      requestedById: userId ?? null,
      meta: {
        sizeBytes,
        checksumSha256: checksumSha256 || computed,
        dbVersion,
        appVersion,
      },
    },
  });

  return { ok: true, cloud_backup_id: id };
}

export async function listBackups({
  companyRnc,
  companyCloudId,
}: {
  companyRnc?: string;
  companyCloudId?: string;
}) {
  const companyId = await resolveCompanyId(companyRnc, companyCloudId);
  if (!companyId) return [];

  const backups = await prisma.cloudBackup.findMany({
    where: { companyId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });

  return backups.map((b) => ({
    id: b.id,
    created_at: b.createdAt.toISOString(),
    size_bytes: b.sizeBytes,
    sha256: b.sha256,
    db_version: b.dbVersion,
    app_version: b.appVersion,
    status: b.status,
  }));
}

export async function getBackupFile(cloudBackupId: string) {
  return prisma.cloudBackup.findUnique({
    where: { id: cloudBackupId },
  });
}

export async function validateBackup(cloudBackupId: string) {
  const backup = await prisma.cloudBackup.findUnique({
    where: { id: cloudBackupId },
  });
  if (!backup) return false;
  if (!fs.existsSync(backup.storagePath)) return false;
  const computed = await computeSha256(backup.storagePath);
  return computed === backup.sha256;
}
