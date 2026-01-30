import { z } from 'zod';

const dateMessage = 'Formato de fecha v\u00e1lido YYYY-MM-DD';
const dateRegex = /^\d{4}-\d{2}-\d{2}$/;

export const rangeQuerySchema = z.object({
  from: z.string().regex(dateRegex, { message: dateMessage }),
  to: z.string().regex(dateRegex, { message: dateMessage }),
});

export const salesListQuerySchema = rangeQuerySchema.extend({
  page: z.coerce.number().int().min(1).optional(),
  pageSize: z.coerce.number().int().min(1).max(100).optional(),
});

export const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});
