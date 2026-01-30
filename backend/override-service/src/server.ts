import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';
import { z } from 'zod';

const prisma = new PrismaClient();
const app = express();

app.use(express.json());
app.use(helmet());
app.use(morgan('combined'));

const requestSchema = z.object({
  companyId: z.number().int().positive(),
  actionCode: z.string().min(3),
  resourceType: z.string().optional(),
  resourceId: z.string().optional(),
  requestedById: z.number().int().positive(),
  terminalId: z.string().optional(),
  meta: z.record(z.any()).optional(),
});

const approveSchema = z.object({
  companyId: z.number().int().positive(),
  requestId: z.number().int().positive(),
  approvedById: z.number().int().positive(),
  expiresInSeconds: z.number().int().min(30).max(600).optional(),
});

const verifySchema = z.object({
  companyId: z.number().int().positive(),
  token: z.string().min(4),
  actionCode: z.string().min(3),
  resourceType: z.string().optional(),
  resourceId: z.string().optional(),
  usedById: z.number().int().positive(),
  terminalId: z.string().optional(),
});

const auditQuerySchema = z.object({
  companyId: z.coerce.number().int().positive(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});

const DEFAULT_TTL_SECONDS = 180;

function normalizeOverrideToken(token: string) {
  return token.trim().replace(/[\s-]+/g, '').toUpperCase();
}

function hashToken(token: string) {
  return crypto.createHash('sha256').update(normalizeOverrideToken(token)).digest('hex');
}

function randomToken(length: number) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({ length }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join(
    '',
  );
}

app.post('/api/override/request', async (req, res) => {
  const parsed = requestSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json(parsed.error.format());
  const body = parsed.data;

  const created = await prisma.overrideRequest.create({
    data: {
      companyId: body.companyId,
      actionCode: body.actionCode,
      resourceType: body.resourceType,
      resourceId: body.resourceId,
      requestedById: body.requestedById,
      terminalId: body.terminalId,
      meta: body.meta,
    },
  });

  await prisma.auditLog.create({
    data: {
      companyId: body.companyId,
      actionCode: body.actionCode,
      resourceType: body.resourceType,
      resourceId: body.resourceId,
      requestedById: body.requestedById,
      approvedById: null,
      method: 'remote',
      result: 'requested',
      terminalId: body.terminalId,
      meta: body.meta,
    },
  });

  res.json({ requestId: created.id, status: created.status });
});

app.post('/api/override/approve', async (req, res) => {
  const parsed = approveSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json(parsed.error.format());
  const body = parsed.data;

  const ttl = body.expiresInSeconds ?? DEFAULT_TTL_SECONDS;
  const token = randomToken(10);
  const tokenHash = hashToken(token);
  const expiresAt = new Date(Date.now() + ttl * 1000);

  try {
    const [request, tokenRecord] = await prisma.$transaction(async (trx) => {
      const request = await trx.overrideRequest.update({
        where: { id: body.requestId },
        data: {
          status: 'approved',
          approvedById: body.approvedById,
          tokenHash,
          expiresAt,
          resolvedAt: new Date(),
        },
      });

      const tokenRecord = await trx.overrideToken.create({
        data: {
          companyId: body.companyId,
          actionCode: request.actionCode,
          resourceType: request.resourceType,
          resourceId: request.resourceId,
          tokenHash,
          method: 'remote',
          nonce: randomToken(8),
          requestedById: request.requestedById,
          approvedById: body.approvedById,
          expiresAt,
          terminalId: request.terminalId,
          requestId: request.id,
        },
      });

      await trx.auditLog.create({
        data: {
          companyId: body.companyId,
          actionCode: request.actionCode,
          resourceType: request.resourceType,
          resourceId: request.resourceId,
          requestedById: request.requestedById,
          approvedById: body.approvedById,
          method: 'remote',
          result: 'approved',
          terminalId: request.terminalId,
        },
      });

      return [request, tokenRecord];
    });

    res.json({
      requestId: request.id,
      token,
      expiresAt,
      tokenId: tokenRecord.id,
    });
  } catch (e: any) {
    res.status(400).json({ message: e.message ?? 'No se pudo aprobar la solicitud' });
  }
});

app.post('/api/override/verify', async (req, res) => {
  const parsed = verifySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json(parsed.error.format());
  const body = parsed.data;

  const tokenHash = hashToken(body.token);
  try {
    const result = await prisma.$transaction(async (trx) => {
      const token = await trx.overrideToken.findFirst({
        where: {
          companyId: body.companyId,
          actionCode: body.actionCode,
          tokenHash,
        },
      });

      if (!token) throw new Error('Token inválido');
      if (token.usedAt) throw new Error('Token ya usado');
      if (token.expiresAt.getTime() < Date.now()) throw new Error('Token vencido');
      if (token.resourceType && body.resourceType && token.resourceType !== body.resourceType)
        throw new Error('Token no coincide con el recurso');
      if (token.resourceId && body.resourceId && token.resourceId !== body.resourceId)
        throw new Error('Token no coincide con el recurso');

      await trx.overrideToken.update({
        where: { id: token.id },
        data: { usedAt: new Date(), usedById: body.usedById, result: 'approved' },
      });

      await trx.auditLog.create({
        data: {
          companyId: body.companyId,
          actionCode: token.actionCode,
          resourceType: token.resourceType,
          resourceId: token.resourceId,
          requestedById: token.requestedById,
          approvedById: body.usedById,
          method: token.method,
          result: 'approved',
          terminalId: body.terminalId,
        },
      });

      return token;
    });

    res.json({ ok: true, tokenId: result.id });
  } catch (e: any) {
    await prisma.auditLog.create({
      data: {
        companyId: body.companyId,
        actionCode: body.actionCode,
        resourceType: body.resourceType,
        resourceId: body.resourceId,
        requestedById: body.usedById,
        approvedById: null,
        method: 'remote',
        result: 'rejected',
        terminalId: body.terminalId,
        meta: { error: e.message },
      },
    });
    res.status(400).json({ ok: false, message: e.message ?? 'No autorizado' });
  }
});

app.get('/api/audit', async (req, res) => {
  const parsed = auditQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json(parsed.error.format());
  const { companyId, limit = 100 } = parsed.data;

  const audits = await prisma.auditLog.findMany({
    where: { companyId },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });

  res.json(audits);
});

const port = process.env.PORT ?? 4000;
app.listen(port, () => {
  console.log(`Override service running on port ${port}`);
});
