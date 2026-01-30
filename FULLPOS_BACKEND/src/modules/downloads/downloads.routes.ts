import { Router } from 'express';
import { validate } from '../../middlewares/validate';
import { getOwnerAppConfig } from './downloads.service';
import { downloadQuerySchema } from './downloads.validation';

const router = Router();

router.get('/owner-app', validate(downloadQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { companyId } = req.query as any;
    const config = await getOwnerAppConfig(companyId ? Number(companyId) : undefined);
    res.json(config);
  } catch (err) {
    next(err);
  }
});

export default router;
