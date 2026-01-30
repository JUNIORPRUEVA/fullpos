import { Router } from 'express';
import fs from 'fs';
import path from 'path';
import multer from 'multer';
import env from '../../config/env';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { createBackup, getBackupFile, listBackups, validateBackup } from './backups.service';

const router = Router();

const tempDir = env.BACKUPS_TMP_DIR?.trim() || path.join(process.cwd(), 'uploads', 'tmp_backups');
if (!fs.existsSync(tempDir)) {
  fs.mkdirSync(tempDir, { recursive: true });
}

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, tempDir),
    filename: (_req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
  }),
  limits: { fileSize: (env.MAX_BACKUP_MB ?? 500) * 1024 * 1024 },
});

router.post('/create', overrideKeyGuard, upload.single('file'), async (req, res, next) => {
  try {
    const file = req.file;
    if (!file) return res.status(400).json({ ok: false, message: 'Archivo requerido' });

    const {
      companyRnc,
      companyCloudId,
      deviceId,
      userId,
      checksumSha256,
      sizeBytes,
      dbVersion,
      appVersion,
    } = req.body ?? {};

    const result = await createBackup({
      tempFilePath: file.path,
      sizeBytes: Number(sizeBytes ?? file.size ?? 0),
      checksumSha256: String(checksumSha256 ?? ''),
      dbVersion: Number(dbVersion ?? 0),
      appVersion: String(appVersion ?? 'unknown'),
      companyRnc,
      companyCloudId,
      deviceId: deviceId ? String(deviceId) : undefined,
      userId: userId ? Number(userId) : undefined,
    });

    if (!result.ok) {
      try {
        if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
      } catch (_) {}
      return res.status(400).json(result);
    }

    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

router.get('/list', overrideKeyGuard, async (req, res, next) => {
  try {
    const { companyRnc, companyCloudId } = req.query as any;
    const result = await listBackups({ companyRnc, companyCloudId });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

router.get('/download/:cloud_backup_id', overrideKeyGuard, async (req, res, next) => {
  try {
    const id = (req.params.cloud_backup_id || '').trim();
    if (!id) return res.status(400).json({ message: 'ID requerido' });
    const backup = await getBackupFile(id);
    if (!backup || !fs.existsSync(backup.storagePath)) {
      return res.status(404).json({ message: 'Backup no encontrado' });
    }
    return res.download(backup.storagePath, `backup_${id}.zip`);
  } catch (err) {
    return next(err);
  }
});

router.post('/restore/validate', overrideKeyGuard, async (req, res, next) => {
  try {
    const cloudBackupId = String(req.body?.cloudBackupId ?? '');
    if (!cloudBackupId) {
      return res.status(400).json({ ok: false, message: 'cloudBackupId requerido' });
    }
    const ok = await validateBackup(cloudBackupId);
    return res.json({ ok });
  } catch (err) {
    return next(err);
  }
});

export default router;
