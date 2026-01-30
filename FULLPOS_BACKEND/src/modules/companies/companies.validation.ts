import { z } from 'zod';

export const updateCompanyConfigSchema = z.object({
  companyName: z.string().min(2).optional(),
  logoUrl: z.string().url().or(z.literal('')).optional().nullable(),
  phone: z.string().optional().nullable(),
  phone2: z.string().optional().nullable(),
  email: z.string().email().optional().nullable(),
  address: z.string().optional().nullable(),
  city: z.string().optional().nullable(),
  slogan: z.string().optional().nullable(),
  website: z.string().url().or(z.literal('')).optional().nullable(),
  instagramUrl: z.string().url().or(z.literal('')).optional().nullable(),
  facebookUrl: z.string().url().or(z.literal('')).optional().nullable(),
  themeKey: z.enum(['original', 'azulBlancoNegro', 'proPos']).optional(),
});

export const updateCompanyConfigByRncSchema = updateCompanyConfigSchema
  .extend({
    companyRnc: z.string().min(3).optional(),
    companyCloudId: z.string().min(6).optional(),
  })
  .refine((data) => !!data.companyRnc || !!data.companyCloudId, {
    message: 'RNC o ID interno requerido',
    path: ['companyRnc'],
  });
