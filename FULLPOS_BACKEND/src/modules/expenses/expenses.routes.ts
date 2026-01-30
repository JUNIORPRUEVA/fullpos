import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { validate } from '../../middlewares/validate';
import { createExpense, getExpensesSummary, listExpenses } from './expenses.service';
import { createExpenseSchema, listExpensesSchema } from './expenses.validation';

const router = Router();

router.use(authGuard);

router.get('/', validate(listExpensesSchema, 'query'), async (req, res, next) => {
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
});

router.get('/summary', validate(listExpensesSchema, 'query'), async (req, res, next) => {
  try {
    const { from, to } = req.query as any;
    const summary = await getExpensesSummary(req.user!.companyId, from, to);
    res.json(summary);
  } catch (err) {
    next(err);
  }
});

router.post('/', validate(createExpenseSchema), async (req, res, next) => {
  try {
    const expense = await createExpense(req.user!.companyId, req.user?.id, req.body);
    res.status(201).json(expense);
  } catch (err) {
    next(err);
  }
});

export default router;
