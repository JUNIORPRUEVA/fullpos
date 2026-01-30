import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { validate } from '../../middlewares/validate';
import { listQuotesSchema, syncQuotesByRncSchema } from './quotes.validation';
import { listQuotes, syncQuotesByRnc } from './quotes.service';

const router = Router();

// Sync desde POS (sin JWT)
router.post('/sync/by-rnc', overrideKeyGuard, validate(syncQuotesByRncSchema), async (req, res, next) => {
  try {
    const { companyRnc, companyCloudId, quotes } = req.body;
    console.info('[cloud_sync] quotes.sync.by-rnc', {
      companyRnc: companyRnc ?? null,
      companyCloudId: companyCloudId ?? null,
      count: Array.isArray(quotes) ? quotes.length : 0,
    });
    const result = await syncQuotesByRnc(companyRnc, companyCloudId, quotes ?? []);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Lectura en Owner (JWT)
router.use(authGuard);

router.get('/', validate(listQuotesSchema, 'query'), async (req, res, next) => {
  try {
    const { from, to, page, pageSize } = req.query as any;
    const result = await listQuotes(
      req.user!.companyId,
      from,
      to,
      page ? Number(page) : 1,
      pageSize ? Number(pageSize) : 20,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
