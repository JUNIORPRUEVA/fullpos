import crypto from 'crypto';
import { prisma } from '../../config/prisma';
import env from '../../config/env';

const DEFAULT_TTL_SECONDS = 180;
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function hashToken(token: string) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buf: Buffer) {
  let bits = 0;
  let value = 0;
  let output = '';

  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }

  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }

  return output;
}

function randomToken(length: number) {
  return Array.from({ length }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join(
    '',
  );
}

const VIRTUAL_PERIOD_SECONDS = 30;
const VIRTUAL_DIGITS = 6;

function virtualTokenEnabled() {
  return Boolean(env.VIRTUAL_TOKEN_MASTER_KEY?.trim());
}

function virtualSecretFor(companyId: number, terminalId: string) {
  const masterKey = env.VIRTUAL_TOKEN_MASTER_KEY?.trim();
  if (!masterKey) {
    throw { status: 400, message: 'Token virtual no está habilitado en el servidor.' };
  }

  const h = crypto
    .createHmac('sha256', masterKey)
    .update(`${companyId}|${terminalId}`)
    .digest();

  // 160-bit secret, típico para TOTP (SHA1).
  return h.subarray(0, 20);
}

function totpAt({
  secret,
  timeMs,
  periodSeconds = VIRTUAL_PERIOD_SECONDS,
  digits = VIRTUAL_DIGITS,
}: {
  secret: Buffer;
  timeMs: number;
  periodSeconds?: number;
  digits?: number;
}) {
  const counter = Math.floor(timeMs / 1000 / periodSeconds);
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));

  const hmac = crypto.createHmac('sha1', secret).update(msg).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binary = (hmac.readUInt32BE(offset) & 0x7fffffff) >>> 0;
  const mod = 10 ** digits;
  const code = String(binary % mod).padStart(digits, '0');

  return { code, counter };
}

function verifyTotp({
  secret,
  token,
  timeMs,
  window = 1,
}: {
  secret: Buffer;
  token: string;
  timeMs: number;
  window?: number;
}) {
  const normalized = token.trim();
  if (!normalized) return null;

  for (let drift = -window; drift <= window; drift++) {
    const t = timeMs + drift * VIRTUAL_PERIOD_SECONDS * 1000;
    const { code, counter } = totpAt({ secret, timeMs: t });
    if (code === normalized) return { counter };
  }

  return null;
}

export async function createOverrideRequest(body: {
  companyId: number;
  actionCode: string;
  resourceType?: string;
  resourceId?: string;
  requestedById: number;
  terminalId?: string;
  meta?: Record<string, unknown>;
}) {
  const created = await prisma.overrideRequest.create({
    data: {
      companyId: body.companyId,
      actionCode: body.actionCode,
      resourceType: body.resourceType,
      resourceId: body.resourceId,
      requestedById: body.requestedById,
      terminalId: body.terminalId,
      meta: body.meta as any,
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
      meta: body.meta as any,
    },
  });

  return { requestId: created.id, status: created.status };
}

export async function approveOverride(body: {
  companyId: number;
  requestId: number;
  approvedById: number;
  expiresInSeconds?: number;
}) {
  const ttl = body.expiresInSeconds ?? DEFAULT_TTL_SECONDS;
  const token = randomToken(10);
  const tokenHash = hashToken(token);
  const expiresAt = new Date(Date.now() + ttl * 1000);

  try {
    const [request, tokenRecord] = await prisma.$transaction(async (trx) => {
      const request = await trx.overrideRequest.findFirst({
        where: { id: body.requestId, companyId: body.companyId },
      });
      if (!request) throw new Error('Solicitud no encontrada');
      if (request.status !== 'pending') throw new Error('Solicitud ya resuelta');

      const updated = await trx.overrideRequest.update({
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
          actionCode: updated.actionCode,
          resourceType: updated.resourceType,
          resourceId: updated.resourceId,
          tokenHash,
          method: 'remote',
          nonce: randomToken(8),
          requestedById: updated.requestedById,
          approvedById: body.approvedById,
          expiresAt,
          terminalId: updated.terminalId,
          requestId: updated.id,
        },
      });

      await trx.auditLog.create({
        data: {
          companyId: body.companyId,
          actionCode: updated.actionCode,
          resourceType: updated.resourceType,
          resourceId: updated.resourceId,
          requestedById: updated.requestedById,
          approvedById: body.approvedById,
          method: 'remote',
          result: 'approved',
          terminalId: updated.terminalId,
        },
      });

      return [updated, tokenRecord] as const;
    });

    return {
      requestId: request.id,
      token,
      expiresAt,
      tokenId: tokenRecord.id,
    };
  } catch (e: any) {
    throw { status: 400, message: e.message ?? 'No se pudo aprobar la solicitud' };
  }
}

export async function verifyOverride(body: {
  companyId: number;
  token: string;
  actionCode: string;
  resourceType?: string;
  resourceId?: string;
  usedById: number;
  terminalId?: string;
}) {
  try {
    const result = await prisma.$transaction(async (trx) => {
      const tokenHash = hashToken(body.token);
      const token = await trx.overrideToken.findFirst({
        where: {
          companyId: body.companyId,
          actionCode: body.actionCode,
          tokenHash,
        },
      });

      // Fallback: token virtual (TOTP) por terminal si el token no existe.
      if (!token) {
        if (!virtualTokenEnabled()) {
          throw new Error('Token inv\u00e1lido');
        }
        const terminalId = body.terminalId?.trim();
        if (!terminalId) {
          throw new Error('Token inv\u00e1lido');
        }

        const secret = virtualSecretFor(body.companyId, terminalId);
        const now = Date.now();
        const match = verifyTotp({ secret, token: body.token, timeMs: now, window: 1 });
        if (!match) {
          throw new Error('Token inv\u00e1lido');
        }

        const usedWindowHash = crypto
          .createHash('sha256')
          .update(`virtual|${body.companyId}|${terminalId}|${match.counter}`)
          .digest('hex');

        const existing = await trx.overrideToken.findFirst({
          where: {
            companyId: body.companyId,
            tokenHash: usedWindowHash,
            method: 'virtual',
          },
        });
        if (existing) {
          throw new Error('Token ya usado');
        }

        const expiresAt = new Date((match.counter + 1) * VIRTUAL_PERIOD_SECONDS * 1000);

        const created = await trx.overrideToken.create({
          data: {
            companyId: body.companyId,
            actionCode: body.actionCode,
            resourceType: body.resourceType,
            resourceId: body.resourceId,
            tokenHash: usedWindowHash,
            method: 'virtual',
            nonce: randomToken(8),
            requestedById: body.usedById,
            approvedById: null,
            expiresAt,
            usedAt: new Date(),
            usedById: body.usedById,
            terminalId,
            result: 'approved',
            meta: { counter: match.counter, periodSeconds: VIRTUAL_PERIOD_SECONDS },
          },
        });

        await trx.auditLog.create({
          data: {
            companyId: body.companyId,
            actionCode: body.actionCode,
            resourceType: body.resourceType,
            resourceId: body.resourceId,
            requestedById: body.usedById,
            approvedById: null,
            method: 'virtual',
            result: 'approved',
            terminalId: terminalId,
            meta: { counter: match.counter, periodSeconds: VIRTUAL_PERIOD_SECONDS },
          },
        });

        return created;
      }

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

    return { ok: true, tokenId: result.id };
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
    throw { status: 400, message: e.message ?? 'No autorizado' };
  }
}

export async function provisionVirtualToken(body: {
  companyId: number;
  userId: number;
  terminalId: string;
  uid?: string;
}) {
  const terminalId = body.terminalId.trim();
  if (!terminalId) throw { status: 400, message: 'terminalId requerido' };

  const secretBytes = virtualSecretFor(body.companyId, terminalId);
  const secret = base32Encode(secretBytes);

  const issuer = 'FULLPOS';
  const label = encodeURIComponent(`${issuer}:${body.companyId}-${terminalId}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    period: String(VIRTUAL_PERIOD_SECONDS),
    digits: String(VIRTUAL_DIGITS),
  });
  const otpauthUri = `otpauth://totp/${label}?${params.toString()}`;

  await prisma.auditLog.create({
    data: {
      companyId: body.companyId,
      actionCode: 'VIRTUAL_TOKEN',
      requestedById: body.userId,
      approvedById: body.userId,
      method: 'virtual',
      result: 'provisioned',
      terminalId,
      meta: {
        digits: VIRTUAL_DIGITS,
        periodSeconds: VIRTUAL_PERIOD_SECONDS,
        uid: body.uid ?? null,
      },
    },
  });

  return {
    terminalId,
    secret,
    digits: VIRTUAL_DIGITS,
    periodSeconds: VIRTUAL_PERIOD_SECONDS,
    otpauthUri,
  };
}

export async function getAudit(companyId: number, limit = 100) {
  const audits = await prisma.auditLog.findMany({
    where: { companyId },
    orderBy: { createdAt: 'desc' },
    take: limit,
    include: {
      requestedBy: { select: { id: true, username: true, displayName: true } },
      approvedBy: { select: { id: true, username: true, displayName: true } },
    },
  });

  return audits.map((audit) => {
    const requestedByName =
      audit.requestedBy?.displayName ?? audit.requestedBy?.username ?? null;
    const approvedByName =
      audit.approvedBy?.displayName ?? audit.approvedBy?.username ?? null;

    return {
      id: audit.id,
      actionCode: audit.actionCode,
      resourceType: audit.resourceType,
      resourceId: audit.resourceId,
      requestedById: audit.requestedById,
      approvedById: audit.approvedById,
      requestedByName,
      approvedByName,
      method: audit.method,
      result: audit.result,
      terminalId: audit.terminalId,
      meta: audit.meta,
      createdAt: audit.createdAt,
    };
  });
}

export async function getOverrideRequests(params: {
  companyId: number;
  status?: string;
  limit?: number;
}) {
  const requests = await prisma.overrideRequest.findMany({
    where: {
      companyId: params.companyId,
      status: params.status,
    },
    orderBy: { createdAt: 'desc' },
    take: params.limit ?? 50,
    include: {
      requestedBy: { select: { id: true, username: true, displayName: true } },
      approvedBy: { select: { id: true, username: true, displayName: true } },
    },
  });

  return requests;
}
