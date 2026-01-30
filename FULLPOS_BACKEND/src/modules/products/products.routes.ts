import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { validate } from '../../middlewares/validate';
import {
  createProductSchema,
  listProductsSchema,
  syncProductsByRncSchema,
} from './products.validation';
import { createProduct, listProducts, syncProductsByRnc } from './products.service';

const router = Router();

// Sync de productos desde FULLPOS (por RNC o ID interno).
// No requiere JWT (POS no tiene login), solo overrideKeyGuard.
router.post(
  '/sync/by-rnc',
  overrideKeyGuard,
  validate(syncProductsByRncSchema),
  async (req, res, next) => {
    try {
      const { companyRnc, companyCloudId, products } = req.body;
      console.info('[cloud_sync] products.sync.by-rnc', {
        companyRnc: companyRnc ?? null,
        companyCloudId: companyCloudId ?? null,
        count: Array.isArray(products) ? products.length : 0,
      });
      const result = await syncProductsByRnc(
        companyRnc,
        products ?? [],
        companyCloudId,
      );
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

// Endpoints de administración (Owner) sí requieren JWT.
router.use(authGuard);

router.get('/', validate(listProductsSchema, 'query'), async (req, res, next) => {
  try {
    const { page, pageSize, search } = req.query as any;
    const result = await listProducts(req.user!.companyId, page, pageSize, search);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/', validate(createProductSchema), async (req, res, next) => {
  try {
    const product = await createProduct(req.user!.companyId, req.body);
    res.status(201).json(product);
  } catch (err) {
    next(err);
  }
});

export default router;
