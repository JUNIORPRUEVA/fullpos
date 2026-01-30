import { Router } from 'express';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';
import sharp from 'sharp';
import env from '../../config/env';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { prisma } from '../../config/prisma';

const router = Router();

const uploadsRoot = env.UPLOADS_DIR?.trim() || path.join(process.cwd(), 'uploads');
const productsDir = path.join(uploadsRoot, 'products');

if (!fs.existsSync(productsDir)) {
  fs.mkdirSync(productsDir, { recursive: true });
}

function resolveBaseUrl(req: any) {
  return env.PUBLIC_BASE_URL?.trim() || `${req.protocol}://${req.get('host')}`;
}

function safeDeleteUploadByUrl(url: string) {
  try {
    const parsed = new URL(url);
    const pathname = parsed.pathname || '';
    if (!pathname.startsWith('/uploads/products/')) return;
    const filename = path.basename(pathname);
    const full = path.join(productsDir, filename);
    if (!full.startsWith(productsDir)) return;
    if (fs.existsSync(full)) {
      fs.unlinkSync(full);
    }
  } catch (_) {
    // Ignore invalid URL
  }
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: (env.MAX_UPLOAD_IMAGE_MB ?? 5) * 1024 * 1024 },
  // NOTE: Some clients (Flutter/Windows/Android) may send `application/octet-stream`.
  // We accept the upload here and later validate by decoding with `sharp`.
  fileFilter: (_req, _file, cb) => cb(null, true),
});

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

router.post('/product-image', overrideKeyGuard, upload.single('file'), async (req, res, next) => {
  try {
    const file = req.file;
    if (!file) return res.status(400).json({ message: 'Archivo requerido' });

    console.info('[cloud_sync] uploads.product-image', {
      mimetype: file.mimetype,
      size: file.size,
      companyRnc: req.body?.companyRnc ?? null,
      companyCloudId: req.body?.companyCloudId ?? null,
      hasOldImageUrl: typeof req.body?.oldImageUrl === 'string' && req.body.oldImageUrl.trim().length > 0,
    });

    const companyId = await resolveCompanyId(req.body?.companyRnc, req.body?.companyCloudId);
    if (!companyId) {
      console.warn('[cloud_sync] uploads.product-image company not resolved', {
        companyRnc: req.body?.companyRnc ?? null,
        companyCloudId: req.body?.companyCloudId ?? null,
      });
      return res.status(400).json({ message: 'Empresa requerida' });
    }

    const maxImages = env.MAX_PRODUCT_IMAGES_PER_COMPANY ?? 200;
    const oldImageUrl = req.body?.oldImageUrl;
    if (typeof oldImageUrl !== 'string' || oldImageUrl.trim().length == 0) {
      const current = await prisma.product.count({
        where: { companyId, imageUrl: { not: null } },
      });
      if (current >= maxImages) {
        return res.status(400).json({ message: `Límite de ${maxImages} imágenes alcanzado` });
      }
    }

    const width = env.MAX_IMAGE_WIDTH ?? 1600;
    const height = env.MAX_IMAGE_HEIGHT ?? 1600;
    let processed: Buffer;
    try {
      processed = await sharp(file.buffer)
        .rotate()
        .resize({ width, height, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 90 })
        .toBuffer();
    } catch (_) {
      return res.status(400).json({ message: 'Solo imágenes' });
    }

    const filename = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.jpg`;
    const fullPath = path.join(productsDir, filename);
    await fs.promises.writeFile(fullPath, processed);

    if (typeof oldImageUrl === 'string' && oldImageUrl.trim().length > 0) {
      safeDeleteUploadByUrl(oldImageUrl.trim());
    }

    const baseUrl = resolveBaseUrl(req);
    const url = `${baseUrl}/uploads/products/${filename}`;
    return res.json({ ok: true, url, filename });
  } catch (err) {
    return next(err);
  }
});

router.delete('/product-image/:filename', overrideKeyGuard, (req, res) => {
  const filename = (req.params.filename || '').trim();
  if (!filename || filename.includes('/') || filename.includes('..')) {
    return res.status(400).json({ message: 'Nombre inválido' });
  }

  const full = path.join(productsDir, filename);
  if (fs.existsSync(full)) {
    fs.unlinkSync(full);
  }

  return res.json({ ok: true });
});

export default router;