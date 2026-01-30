import { Prisma } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { buildPagination } from '../../utils/pagination';
import { createProductSchema } from './products.validation';

function toNumber(value: Prisma.Decimal | number | null) {
  if (value === null || value === undefined) return 0;
  if (typeof value === 'number') return value;
  return value.toNumber();
}

export type CreateProductInput = Omit<
  ReturnType<typeof createProductSchema.parse>,
  'isDemo'
> & { isDemo?: boolean };

export type SyncProductInput = {
  code: string;
  name: string;
  description?: string;
  price: number;
  cost?: number;
  stock?: number;
  imageUrl?: string | null;
};

function normalizeRnc(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export async function listProducts(
  companyId: number,
  page = 1,
  pageSize = 20,
  search?: string,
) {
  const { skip, take, page: safePage } = buildPagination(page, pageSize);

  // Mantener solo datos reales: limpiamos productos demo y filtramos por isDemo = false
  await prisma.product.deleteMany({ where: { companyId, isDemo: true } });

  const where = {
    companyId,
    isDemo: false,
    ...(search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' as const } },
            { code: { contains: search, mode: 'insensitive' as const } },
          ],
        }
      : {}),
  };

  const [total, items] = await Promise.all([
    prisma.product.count({ where }),
    prisma.product.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }],
      skip,
      take,
    }),
  ]);

  return {
    data: items.map((p) => ({
      id: p.id,
      code: p.code,
      name: p.name,
      description: p.description,
      price: toNumber(p.price),
      cost: toNumber(p.cost),
      stock: toNumber(p.stock),
      imageUrl: p.imageUrl,
      isDemo: p.isDemo,
      createdAt: p.createdAt,
    })),
    total,
    page: safePage,
    pageSize: take,
  };
}

export async function createProduct(companyId: number, input: CreateProductInput) {
  const data = {
    companyId,
    code: input.code,
    name: input.name,
    description: input.description,
    price: input.price,
    cost: input.cost ?? 0,
    stock: input.stock ?? 0,
    imageUrl: input.imageUrl,
    isDemo: input.isDemo ?? false,
  };

  try {
    const created = await prisma.$transaction(async (tx) => {
      if (!data.isDemo) {
        const demoCount = await tx.product.count({ where: { companyId, isDemo: true } });
        if (demoCount > 0) {
          await tx.product.deleteMany({ where: { companyId, isDemo: true } });
        }
      }

      return tx.product.create({ data });
    });

    return {
      id: created.id,
      code: created.code,
      name: created.name,
      description: created.description,
      price: toNumber(created.price),
      cost: toNumber(created.cost),
      stock: toNumber(created.stock),
      imageUrl: created.imageUrl,
      isDemo: created.isDemo,
      createdAt: created.createdAt,
    };
  } catch (err: any) {
    if (err.code === 'P2002') {
      throw { status: 409, message: 'Ya existe un producto con ese codigo' };
    }
    throw err;
  }
}

export async function syncProductsByRnc(
  companyRnc: string | undefined,
  products: SyncProductInput[],
  companyCloudId?: string,
) {
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

  if (!products || products.length == 0) {
    return { ok: true, upserted: 0, companyId: company.id };
  }

  const ops = products.map((item) => {
    const code = item.code.trim();
    const name = item.name.trim();
    const description = item.description?.trim();
    const imageUrl = item.imageUrl === undefined ? undefined : (item.imageUrl?.trim() || null);
    const stock = item.stock ?? 0;
    const cost = item.cost ?? 0;

    const updateData: any = {
      name,
      description: description?.length ? description : null,
      price: item.price,
      cost,
      stock,
      isDemo: false,
    };
    if (imageUrl !== undefined) {
      updateData.imageUrl = imageUrl;
    }

    return prisma.product.upsert({
      where: { companyId_code: { companyId: company.id, code } },
      update: {
        ...updateData,
      },
      create: {
        companyId: company.id,
        code,
        name,
        description: description?.length ? description : null,
        price: item.price,
        cost,
        stock,
        imageUrl: imageUrl ?? null,
        isDemo: false,
      },
    });
  });

  await prisma.$transaction(ops);

  return { ok: true, upserted: products.length, companyId: company.id };
}
