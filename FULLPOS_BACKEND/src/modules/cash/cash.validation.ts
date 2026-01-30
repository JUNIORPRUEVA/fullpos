import { z } from 'zod';

export const syncCashByRncSchema = z
  .object({
    companyRnc: z.string().trim().min(3).optional(),
    companyCloudId: z.string().trim().min(6).optional(),
    sessions: z
      .array(
        z.object({
          localId: z.coerce.number().int().positive(),
          openedByUserName: z.string().trim().min(1).max(100),
          openedAt: z.string().datetime(),
          closedAt: z.string().datetime().optional().nullable(),
          initialAmount: z.coerce.number().nonnegative().default(0),
          closingAmount: z.coerce.number().nonnegative().optional().nullable(),
          expectedCash: z.coerce.number().optional().nullable(),
          difference: z.coerce.number().optional().nullable(),
          status: z.string().trim().min(1).default('OPEN'),
          note: z.string().trim().max(500).optional().nullable(),
        }),
      )
      .max(2000)
      .default([]),
    movements: z
      .array(
        z.object({
          localId: z.coerce.number().int().positive(),
          sessionLocalId: z.coerce.number().int().positive(),
          type: z.string().trim().min(1).max(10),
          amount: z.coerce.number(),
          note: z.string().trim().max(500).optional().nullable(),
          createdAt: z.string().datetime(),
        }),
      )
      .max(5000)
      .default([]),
  })
  .refine((data) => !!data.companyRnc || !!data.companyCloudId, {
    message: 'RNC o ID interno requerido',
    path: ['companyRnc'],
  });
