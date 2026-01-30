import { z } from 'zod';

export const listExpensesSchema = z.object({
  from: z.string().trim(),
  to: z.string().trim(),
  page: z.coerce.number().int().positive().optional(),
  pageSize: z.coerce.number().int().positive().max(200).optional(),
});

export const createExpenseSchema = z.object({
  amount: z.coerce.number().positive('El monto debe ser mayor a 0'),
  category: z.string().trim().min(1, 'La categoria es requerida'),
  note: z.string().trim().max(500).optional(),
  incurredAt: z.string().trim().optional(),
});
