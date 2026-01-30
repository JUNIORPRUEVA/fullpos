import { z } from 'zod';

export const syncSalesByRncSchema = z
  .object({
    companyRnc: z.string().trim().min(3).optional(),
    companyCloudId: z.string().trim().min(6).optional(),
    sales: z
      .array(
        z.object({
          localCode: z.string().trim().min(3),
          kind: z.string().trim().min(1),
          status: z.string().trim().min(1).default('completed'),
          customerNameSnapshot: z.string().trim().max(200).optional().nullable(),
          customerPhoneSnapshot: z.string().trim().max(50).optional().nullable(),
          customerRncSnapshot: z.string().trim().max(50).optional().nullable(),
          itbisEnabled: z.coerce.boolean().default(true),
          itbisRate: z.coerce.number().nonnegative().default(0.18),
          discountTotal: z.coerce.number().nonnegative().default(0),
          subtotal: z.coerce.number().nonnegative().default(0),
          itbisAmount: z.coerce.number().nonnegative().default(0),
          total: z.coerce.number().nonnegative().default(0),
          paymentMethod: z.string().trim().max(50).optional().nullable(),
          paidAmount: z.coerce.number().nonnegative().optional().default(0),
          changeAmount: z.coerce.number().nonnegative().optional().default(0),
          fiscalEnabled: z.coerce.boolean().optional().default(false),
          ncfFull: z.string().trim().max(100).optional().nullable(),
          ncfType: z.string().trim().max(50).optional().nullable(),
          sessionLocalId: z.coerce.number().int().positive().optional().nullable(),
          createdAt: z.string().datetime(),
          updatedAt: z.string().datetime(),
          deletedAt: z.string().datetime().optional().nullable(),
          items: z
            .array(
              z.object({
                productCodeSnapshot: z.string().trim().max(100).optional().nullable(),
                productNameSnapshot: z.string().trim().min(1).max(200),
                qty: z.coerce.number(),
                unitPrice: z.coerce.number().nonnegative(),
                purchasePriceSnapshot: z.coerce.number().nonnegative().optional().default(0),
                discountLine: z.coerce.number().nonnegative().optional().default(0),
                totalLine: z.coerce.number().nonnegative(),
                createdAt: z.string().datetime().optional(),
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
