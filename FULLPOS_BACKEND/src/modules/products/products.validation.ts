import { z } from 'zod';

export const listProductsSchema = z.object({
  page: z.coerce.number().int().positive().optional(),
  pageSize: z.coerce.number().int().positive().max(100).optional(),
  search: z.string().trim().max(100).optional(),
});

export const createProductSchema = z.object({
  code: z.string().trim().min(1, 'El codigo es requerido'),
  name: z.string().trim().min(1, 'El nombre es requerido'),
  description: z.string().trim().max(500).optional(),
  price: z.coerce.number().nonnegative(),
  cost: z.coerce.number().nonnegative().optional().default(0),
  stock: z.coerce.number().nonnegative().default(0),
  imageUrl: z.string().url().optional(),
  isDemo: z.boolean().optional(),
});

export const syncProductsByRncSchema = z
  .object({
    companyRnc: z.string().trim().min(3).optional(),
    companyCloudId: z.string().trim().min(6).optional(),
    products: z
      .array(
        z.object({
          code: z.string().trim().min(1, 'El codigo es requerido'),
          name: z.string().trim().min(1, 'El nombre es requerido'),
          description: z.string().trim().max(500).optional(),
          price: z.coerce.number().nonnegative(),
          cost: z.coerce.number().nonnegative().optional(),
          stock: z.coerce.number().nonnegative().optional(),
          imageUrl: z.string().url().optional().nullable(),
        }),
      )
      .max(2000)
      .default([]),
  })
  .refine((data) => !!data.companyRnc || !!data.companyCloudId, {
    message: 'RNC o ID interno requerido',
    path: ['companyRnc'],
  });
