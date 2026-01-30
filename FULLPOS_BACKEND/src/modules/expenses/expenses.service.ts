import { prisma } from '../../config/prisma';
import { ensureRangeWithinDays, parseRange } from '../../utils/date';
import { buildPagination } from '../../utils/pagination';

const MAX_RANGE_DAYS = 365;

function toNumber(value: any) {
  if (value === null || value === undefined) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Number(value);
  if (typeof (value as any).toNumber === 'function') return (value as any).toNumber();
  return Number(value);
}

export async function createExpense(
  companyId: number,
  userId: number | undefined,
  input: { amount: number; category: string; note?: string; incurredAt?: string },
) {
  const incurredAt = input.incurredAt ? new Date(input.incurredAt) : new Date();
  if (Number.isNaN(incurredAt.getTime())) {
    throw { status: 400, message: 'Fecha de gasto invalida' };
  }

  const created = await prisma.expense.create({
    data: {
      companyId,
      createdById: userId,
      amount: input.amount,
      category: input.category,
      note: input.note,
      incurredAt,
    },
    include: {
      createdBy: { select: { id: true, username: true, displayName: true } },
    },
  });

  return {
    id: created.id,
    amount: toNumber(created.amount),
    category: created.category,
    note: created.note,
    incurredAt: created.incurredAt,
    createdBy: created.createdBy,
  };
}

export async function listExpenses(
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
    incurredAt: { gte: fromDate, lte: toDate },
  };

  const [total, rows] = await Promise.all([
    prisma.expense.count({ where }),
    prisma.expense.findMany({
      where,
      orderBy: { incurredAt: 'desc' },
      skip,
      take,
      include: { createdBy: { select: { id: true, username: true, displayName: true } } },
    }),
  ]);

  return {
    data: rows.map((row) => ({
      id: row.id,
      amount: toNumber(row.amount),
      category: row.category,
      note: row.note,
      incurredAt: row.incurredAt,
      createdBy: row.createdBy,
    })),
    total,
    page: safePage,
    pageSize: take,
  };
}

export async function getExpensesSummary(companyId: number, from: string, to: string) {
  const { fromDate, toDate } = parseRange(from, to);
  ensureRangeWithinDays(fromDate, toDate, MAX_RANGE_DAYS);

  const result = await prisma.expense.aggregate({
    _sum: { amount: true },
    _count: { _all: true },
    where: {
      companyId,
      incurredAt: { gte: fromDate, lte: toDate },
    },
  });

  return {
    total: toNumber(result._sum.amount),
    count: result._count._all,
  };
}
