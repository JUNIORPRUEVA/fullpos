import { z } from 'zod';

export const requestSchema = z.object({
  companyId: z.number().int().positive(),
  actionCode: z.string().min(3),
  resourceType: z.string().optional(),
  resourceId: z.string().optional(),
  requestedById: z.number().int().positive(),
  terminalId: z.string().optional(),
  meta: z.record(z.any()).optional(),
});

export const approveSchema = z.object({
  requestId: z.number().int().positive(),
  expiresInSeconds: z.number().int().min(30).max(600).optional(),
});

export const verifySchema = z.object({
  companyId: z.number().int().positive(),
  token: z.string().min(4),
  actionCode: z.string().min(3),
  resourceType: z.string().optional(),
  resourceId: z.string().optional(),
  usedById: z.number().int().positive(),
  terminalId: z.string().optional(),
});

export const virtualProvisionSchema = z.object({
  terminalId: z.string().min(3),
  uid: z.string().min(6).optional(),
});

export const auditQuerySchema = z.object({
  companyId: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});

export const requestsQuerySchema = z.object({
  companyId: z.coerce.number().int().positive().optional(),
  status: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});
