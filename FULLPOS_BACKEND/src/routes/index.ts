import { Router } from 'express';
import authRoutes from '../modules/auth/auth.routes';
import reportRoutes from '../modules/reports/reports.routes';
import downloadRoutes from '../modules/downloads/downloads.routes';
import overrideRoutes from '../modules/override/override.routes';
import productRoutes from '../modules/products/products.routes';
import companiesRoutes from '../modules/companies/companies.routes';
import expensesRoutes from '../modules/expenses/expenses.routes';
import uploadsRoutes from '../modules/uploads/uploads.routes';
import salesRoutes from '../modules/sales/sales.routes';
import cashRoutes from '../modules/cash/cash.routes';
import quotesRoutes from '../modules/quotes/quotes.routes';
import backupsRoutes from '../modules/backups/backups.routes';

const router = Router();

router.use('/auth', authRoutes);
router.use('/reports', reportRoutes);
router.use('/downloads', downloadRoutes);
router.use('/override', overrideRoutes);
router.use('/products', productRoutes);
router.use('/sales', salesRoutes);
router.use('/cash', cashRoutes);
router.use('/quotes', quotesRoutes);
router.use('/companies', companiesRoutes);
router.use('/expenses', expensesRoutes);
router.use('/uploads', uploadsRoutes);
router.use('/backups', backupsRoutes);

export default router;
