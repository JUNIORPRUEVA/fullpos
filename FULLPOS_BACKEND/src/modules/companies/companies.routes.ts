import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { dangerRateLimit } from '../../middlewares/dangerRateLimit';
import { validate } from '../../middlewares/validate';
import env from '../../config/env';
import {
  dangerousCompanyAction,
  getCompanyConfig,
  updateCompanyConfig,
  updateCompanyConfigByRnc,
} from './companies.service';
import { updateCompanyConfigByRncSchema, updateCompanyConfigSchema } from './companies.validation';

const router = Router();

router.get('/config', authGuard, async (req, res, next) => {
  try {
    if (!req.user) return res.status(401).json({ message: 'Token requerido' });
    const config = await getCompanyConfig(req.user.companyId);
    res.json(config);
  } catch (err) {
    next(err);
  }
});

router.put(
  '/config',
  authGuard,
  validate(updateCompanyConfigSchema),
  async (req, res, next) => {
    try {
      if (!req.user) return res.status(401).json({ message: 'Token requerido' });
      const updated = await updateCompanyConfig(req.user.companyId, req.body);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  },
);

// Sync de configuración de empresa desde FULLPOS (por RNC)
router.put(
  '/config/by-rnc',
  overrideKeyGuard,
  validate(updateCompanyConfigByRncSchema),
  async (req, res, next) => {
    try {
      const { companyRnc, companyCloudId, ...payload } = req.body;
      console.info('[cloud_sync] companies.config.by-rnc', {
        companyRnc: companyRnc ?? null,
        companyCloudId: companyCloudId ?? null,
        companyName: payload?.companyName ?? null,
      });
      const updated = await updateCompanyConfigByRnc(companyRnc, {
        ...payload,
        companyCloudId,
      });
      res.json(updated);
    } catch (err) {
      next(err);
    }
  },
);

router.post('/actions', overrideKeyGuard, dangerRateLimit, async (req, res, next) => {
  try {
    const { action, phrase, adminPin, companyRnc, companyCloudId } = req.body ?? {};
    if (!action || !phrase || !adminPin) {
      return res.status(400).json({ message: 'action, phrase y adminPin requeridos' });
    }
    const pin = env.DANGER_ACTION_PIN?.trim();
    if (!pin || pin !== String(adminPin).trim()) {
      return res.status(403).json({ message: 'PIN invalido' });
    }
    if (action !== 'RESET' && action !== 'DELETE') {
      return res.status(400).json({ message: 'Accion invalida' });
    }
    const expectedPhrase = action === 'RESET' ? 'RESETEAR EMPRESA' : 'BORRAR TODO FULLPOS';
    if (String(phrase).trim().toUpperCase() !== expectedPhrase) {
      return res.status(400).json({ message: 'Frase de confirmacion invalida' });
    }

    const result = await dangerousCompanyAction({
      action,
      companyRnc,
      companyCloudId,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

export default router;
