import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { validate } from '../../middlewares/validate';
import { getCashClosingDetail, getCashClosings, getReportsStatus, getSalesByDay, getSalesList, getSalesSummary } from './reports.service';
import { idParamSchema, rangeQuerySchema, salesListQuerySchema } from './reports.validation';
import { listExpensesSchema } from '../expenses/expenses.validation';
import { listExpenses, getExpensesSummary } from '../expenses/expenses.service';

const router = Router();

router.get('/sales/summary', authGuard, validate(rangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { from, to } = req.query as any;
    const result = await getSalesSummary(req.user!.companyId, from, to);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.get('/status', authGuard, validate(rangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { from, to } = req.query as any;
    const result = await getReportsStatus(req.user!.companyId, from, to);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.get('/sales/by-day', authGuard, validate(rangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { from, to } = req.query as any;
    const result = await getSalesByDay(req.user!.companyId, from, to);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.get('/sales/list', authGuard, validate(salesListQuerySchema, 'query'), async (req, res, next) => {
  try {
    const { from, to, page, pageSize } = req.query as any;
    const result = await getSalesList(
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

router.get(
  '/cash/closings',
  authGuard,
  validate(rangeQuerySchema, 'query'),
  async (req, res, next) => {
    try {
      const { from, to } = req.query as any;
      const result = await getCashClosings(req.user!.companyId, from, to);
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

router.get(
  '/cash/closing/:id',
  authGuard,
  validate(idParamSchema, 'params'),
  async (req, res, next) => {
    try {
      const { id } = req.params as any;
      const result = await getCashClosingDetail(req.user!.companyId, Number(id));
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

router.get(
  '/expenses/summary',
  authGuard,
  validate(rangeQuerySchema, 'query'),
  async (req, res, next) => {
    try {
      const { from, to } = req.query as any;
      const result = await getExpensesSummary(req.user!.companyId, from, to);
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

router.get(
  '/expenses/list',
  authGuard,
  validate(listExpensesSchema, 'query'),
  async (req, res, next) => {
    try {
      const { from, to, page, pageSize } = req.query as any;
      const result = await listExpenses(
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
  },
);

export default router;
