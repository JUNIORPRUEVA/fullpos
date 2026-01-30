import { z } from 'zod';

export const listQuotesSchema = z.object({
  from: z.string().datetime(),
  to: z.string().datetime(),
  page: z.coerce.number().int().positive().optional(),
  pageSize: z.coerce.number().int().positive().max(100).optional(),
});

export const syncQuotesByRncSchema = z
  .object({
    companyRnc: z.string().trim().min(3).optional(),
    companyCloudId: z.string().trim().min(6).optional(),
    quotes: z
      .array(
        z.object({
          localId: z.coerce.number().int().positive(),
          clientNameSnapshot: z.string().trim().min(1).max(200),
          clientPhoneSnapshot: z.string().trim().max(50).optional().nullable(),
          clientRncSnapshot: z.string().trim().max(50).optional().nullable(),
          ticketName: z.string().trim().max(200).optional().nullable(),
          subtotal: z.coerce.number().nonnegative().default(0),
          itbisEnabled: z.coerce.boolean().default(true),
          itbisRate: z.coerce.number().nonnegative().default(0.18),
          itbisAmount: z.coerce.number().nonnegative().default(0),
          discountTotal: z.coerce.number().nonnegative().default(0),
          total: z.coerce.number().nonnegative().default(0),
          status: z.string().trim().min(1).default('OPEN'),
          notes: z.string().trim().max(1000).optional().nullable(),
          createdAt: z.string().datetime(),
          updatedAt: z.string().datetime(),
          items: z
            .array(
              z.object({
                localId: z.coerce.number().int().positive().optional().nullable(),
                productCodeSnapshot: z.string().trim().max(100).optional().nullable(),
                productNameSnapshot: z.string().trim().min(1).max(200),
                description: z.string().trim().max(500).default(''),
                qty: z.coerce.number(),
                unitPrice: z.coerce.number().nonnegative().default(0),
                price: z.coerce.number().nonnegative().default(0),
                cost: z.coerce.number().nonnegative().optional().default(0),
                discountLine: z.coerce.number().nonnegative().optional().default(0),
                totalLine: z.coerce.number().nonnegative().default(0),
              }),
            )
            .max(500)
            .default([]),
        }),
      )
      .max(2000)
      .default([]),
  })
  .refine((data) => !!data.companyRnc || !!data.companyCloudId, {
    message: 'RNC o ID interno requerido',
    path: ['companyRnc'],
  });
