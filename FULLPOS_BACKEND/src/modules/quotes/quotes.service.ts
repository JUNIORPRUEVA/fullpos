import { Prisma } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { parseRange, ensureRangeWithinDays } from '../../utils/date';
import { buildPagination } from '../../utils/pagination';

const MAX_RANGE_DAYS = 365;

function toNumber(value: any) {
  if (value === null || value === undefined) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Number(value);
  if (typeof (value as any).toNumber === 'function') return (value as any).toNumber();
  return Number(value);
}

function normalizeRnc(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

async function resolveCompanyId(companyRnc?: string, companyCloudId?: string) {
  const rnc = companyRnc?.trim() ?? '';
  const cloudId = companyCloudId?.trim() ?? '';
  if (!rnc && !cloudId) {
    throw { status: 400, message: 'RNC o ID interno requerido' };
  }

  let company = null as { id: number; rnc: string | null } | null;

  if (cloudId) {
    company = await prisma.company.findFirst({
      where: { cloudCompanyId: cloudId },
      select: { id: true, rnc: true },
    });
  }

  if (!company && rnc) {
    company = await prisma.company.findFirst({
      where: { rnc },
      select: { id: true, rnc: true },
    });

    if (!company) {
      const normalized = normalizeRnc(rnc);
      if (normalized.length > 0) {
        const candidates = await prisma.company.findMany({
          where: { rnc: { not: null } },
          select: { id: true, rnc: true },
        });
        company =
          candidates.find(
            (item) => item.rnc != null && normalizeRnc(item.rnc) === normalized,
          ) ?? null;
      }
    }
  }

  if (!company) {
    throw { status: 404, message: 'Empresa no encontrada' };
  }

  return company.id;
}

export async function listQuotes(
  companyId: number,
  from: string,
  to: string,
  page = 1,
  pageSize = 20,
) {
  const { fromDate, toDate } = parseRange(from, to);
  ensureRangeWithinDays(fromDate, toDate, MAX_RANGE_DAYS);
  const { skip, take, page: safePage } = buildPagination(page, pageSize);

  const where = {
    companyId,
    createdAt: { gte: fromDate, lte: toDate },
  } as const;

  const [total, rows] = await Promise.all([
    prisma.quote.count({ where }),
    prisma.quote.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      include: { items: true },
    }),
  ]);

  return {
    data: rows.map((q) => ({
      id: q.id,
      localId: q.localId,
      clientNameSnapshot: q.clientNameSnapshot,
      clientPhoneSnapshot: q.clientPhoneSnapshot,
      clientRncSnapshot: q.clientRncSnapshot,
      ticketName: q.ticketName,
      subtotal: toNumber(q.subtotal),
      itbisEnabled: q.itbisEnabled,
      itbisRate: toNumber(q.itbisRate),
      itbisAmount: toNumber(q.itbisAmount),
      discountTotal: toNumber(q.discountTotal),
      total: toNumber(q.total),
      status: q.status,
      notes: q.notes,
      createdAt: q.createdAt,
      updatedAt: q.updatedAt,
      items: q.items.map((i) => ({
        id: i.id,
        localId: i.localId,
        productCodeSnapshot: i.productCodeSnapshot,
        productNameSnapshot: i.productNameSnapshot,
        description: i.description,
        qty: toNumber(i.qty),
        unitPrice: toNumber(i.unitPrice),
        price: toNumber(i.price),
        cost: toNumber(i.cost),
        discountLine: toNumber(i.discountLine),
        totalLine: toNumber(i.totalLine),
      })),
    })),
    total,
    page: safePage,
    pageSize: take,
  };
}

export type SyncQuoteInput = {
  localId: number;
  clientNameSnapshot: string;
  clientPhoneSnapshot?: string | null;
  clientRncSnapshot?: string | null;
  ticketName?: string | null;
  subtotal: number;
  itbisEnabled: boolean;
  itbisRate: number;
  itbisAmount: number;
  discountTotal: number;
  total: number;
  status: string;
  notes?: string | null;
  createdAt: string;
  updatedAt: string;
  items: Array<{
    localId?: number | null;
    productCodeSnapshot?: string | null;
    productNameSnapshot: string;
    description: string;
    qty: number;
    unitPrice: number;
    price: number;
    cost?: number;
    discountLine?: number;
    totalLine: number;
  }>;
};

export async function syncQuotesByRnc(
  companyRnc: string | undefined,
  companyCloudId: string | undefined,
  quotes: SyncQuoteInput[],
) {
  const companyId = await resolveCompanyId(companyRnc, companyCloudId);
  if (!quotes || quotes.length === 0) {
    return { ok: true, upserted: 0, companyId };
  }

  await prisma.$transaction(async (tx) => {
    for (const q of quotes) {
      const createdAt = new Date(q.createdAt);
      const updatedAt = new Date(q.updatedAt);

      const upserted = await tx.quote.upsert({
        where: { companyId_localId: { companyId, localId: q.localId } },
        update: {
          clientNameSnapshot: q.clientNameSnapshot,
          clientPhoneSnapshot: q.clientPhoneSnapshot ?? null,
          clientRncSnapshot: q.clientRncSnapshot ?? null,
          ticketName: q.ticketName ?? null,
          subtotal: q.subtotal,
          itbisEnabled: q.itbisEnabled,
          itbisRate: q.itbisRate,
          itbisAmount: q.itbisAmount,
          discountTotal: q.discountTotal,
          total: q.total,
          status: q.status,
          notes: q.notes ?? null,
          updatedAt,
        },
        create: {
          companyId,
          localId: q.localId,
          clientNameSnapshot: q.clientNameSnapshot,
          clientPhoneSnapshot: q.clientPhoneSnapshot ?? null,
          clientRncSnapshot: q.clientRncSnapshot ?? null,
          ticketName: q.ticketName ?? null,
          subtotal: q.subtotal,
          itbisEnabled: q.itbisEnabled,
          itbisRate: q.itbisRate,
          itbisAmount: q.itbisAmount,
          discountTotal: q.discountTotal,
          total: q.total,
          status: q.status,
          notes: q.notes ?? null,
          createdAt,
          updatedAt,
        },
        select: { id: true },
      });

      await tx.quoteItem.deleteMany({ where: { quoteId: upserted.id } });
      if (q.items && q.items.length > 0) {
        await tx.quoteItem.createMany({
          data: q.items.map((i) => ({
            quoteId: upserted.id,
            localId: i.localId ?? null,
            productCodeSnapshot: i.productCodeSnapshot ?? null,
            productNameSnapshot: i.productNameSnapshot,
            description: i.description,
            qty: i.qty,
            unitPrice: i.unitPrice,
            price: i.price,
            cost: i.cost ?? 0,
            discountLine: i.discountLine ?? 0,
            totalLine: i.totalLine,
          })),
        });
      }
    }
  });

  return { ok: true, upserted: quotes.length, companyId };
}
