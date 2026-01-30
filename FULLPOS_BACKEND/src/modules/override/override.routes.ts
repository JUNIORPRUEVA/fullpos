import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { validate } from '../../middlewares/validate';
import {
  approveSchema,
  auditQuerySchema,
  requestSchema,
  requestsQuerySchema,
  verifySchema,
  virtualProvisionSchema,
} from './override.validation';
import {
  approveOverride,
  createOverrideRequest,
  getOverrideRequests,
  getAudit,
  provisionVirtualToken,
  verifyOverride,
} from './override.service';

const router = Router();

router.post('/request', overrideKeyGuard, validate(requestSchema), async (req, res, next) => {
  try {
    const result = await createOverrideRequest(req.body);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/approve', authGuard, validate(approveSchema), async (req, res, next) => {
  try {
    const result = await approveOverride({
      ...req.body,
      companyId: req.user!.companyId,
      approvedById: req.user!.id,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/verify', overrideKeyGuard, validate(verifySchema), async (req, res, next) => {
  try {
    const result = await verifyOverride(req.body);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Token virtual (TOTP): el dueño "activa" (provisiona) el secret para un terminal.
router.post(
  '/virtual/provision',
  authGuard,
  validate(virtualProvisionSchema),
  async (req, res, next) => {
    try {
      const result = await provisionVirtualToken({
        companyId: req.user!.companyId,
        userId: req.user!.id,
        terminalId: req.body.terminalId,
        uid: req.body.uid,
      });
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

router.get('/audit', authGuard, validate(auditQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { companyId, limit } = req.query as any;
    const resolvedCompanyId = companyId ? Number(companyId) : req.user!.companyId;
    const audits = await getAudit(resolvedCompanyId, limit ? Number(limit) : 100);
    res.json(audits);
  } catch (err) {
    next(err);
  }
});

router.get(
  '/requests',
  authGuard,
  validate(requestsQuerySchema, 'query'),
  async (req, res, next) => {
    try {
      const { companyId, status, limit } = req.query as any;
      const resolvedCompanyId = companyId ? Number(companyId) : req.user!.companyId;
      const requests = await getOverrideRequests({
        companyId: resolvedCompanyId,
        status,
        limit: limit ? Number(limit) : 50,
      });
      res.json(requests);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
