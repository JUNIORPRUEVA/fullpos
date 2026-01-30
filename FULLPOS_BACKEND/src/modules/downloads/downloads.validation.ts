import { z } from 'zod';

export const downloadQuerySchema = z.object({
  companyId: z.coerce.number().int().positive().optional(),
});
