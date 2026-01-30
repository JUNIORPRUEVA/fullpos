import { Router } from 'express';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { validate } from '../../middlewares/validate';
import { syncSalesByRncSchema } from './sales.validation';
import { syncSalesByRnc } from './sales.service';

const router = Router();

// Sync de ventas desde FULLPOS (por RNC o ID interno).
// No requiere JWT (POS no tiene login), solo overrideKeyGuard.
router.post('/sync/by-rnc', overrideKeyGuard, validate(syncSalesByRncSchema), async (req, res, next) => {
  try {
    const { companyRnc, companyCloudId, sales } = req.body;
    console.info('[cloud_sync] sales.sync.by-rnc', {
      companyRnc: companyRnc ?? null,
      companyCloudId: companyCloudId ?? null,
      count: Array.isArray(sales) ? sales.length : 0,
    });
    const result = await syncSalesByRnc(companyRnc, companyCloudId, sales ?? []);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
