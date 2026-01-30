import { prisma } from '../../config/prisma';
import { Prisma } from '@prisma/client';

const DEFAULT_THEME_KEY = 'proPos';

type UpdateCompanyConfigInput = {
  companyName?: string;
  logoUrl?: string | null;
  phone?: string | null;
  phone2?: string | null;
  email?: string | null;
  address?: string | null;
  city?: string | null;
  slogan?: string | null;
  website?: string | null;
  instagramUrl?: string | null;
  facebookUrl?: string | null;
  themeKey?: string;
  companyCloudId?: string;
};

type CompanyWithConfig = Prisma.CompanyGetPayload<{ include: { config: true } }>;

function isMissingCompanyConfigTable(err: any) {
  if (err?.code !== 'P2021') return false;
  const table = String(err?.meta?.table ?? '');
  const message = String(err?.message ?? '');
  return table.includes('CompanyConfig') || message.includes('CompanyConfig');
}

function normalizeRnc(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function normalizeCloudId(value: string) {
  return value.trim();
}

function normalizeNullable(value?: string | null) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizeRequired(value?: string) {
  if (value === undefined) return undefined;
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

async function ensureCompanyConfig(companyId: number) {
  try {
    return await prisma.companyConfig.upsert({
      where: { companyId },
      update: { updatedAt: new Date() },
      create: {
        companyId,
        themeKey: DEFAULT_THEME_KEY,
      },
    });
  } catch (err) {
    if (isMissingCompanyConfigTable(err)) {
      console.warn(
        '[cloud_sync] CompanyConfig table missing (run migrations). Returning defaults.',
      );
      return null;
    }
    throw err;
  }
}

function mapConfigResponse(company: any | null) {
  if (!company) return null;
  const config = company.config ?? {
    companyId: company.id,
    themeKey: DEFAULT_THEME_KEY,
    logoUrl: null,
    phone: null,
    phone2: null,
    email: null,
    address: null,
    city: null,
    slogan: null,
    website: null,
    instagramUrl: null,
    facebookUrl: null,
    primaryColor: null,
    accentColor: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  return {
    companyId: company.id,
    companyName: company.name,
    rnc: company.rnc,
    logoUrl: config.logoUrl,
    phone: config.phone,
    phone2: config.phone2,
    email: config.email,
    address: config.address,
    city: config.city,
    slogan: config.slogan,
    website: config.website,
    instagramUrl: config.instagramUrl,
    facebookUrl: config.facebookUrl,
    themeKey: config.themeKey ?? DEFAULT_THEME_KEY,
    primaryColor: config.primaryColor,
    accentColor: config.accentColor,
    version: company.ownerAppVersion,
  };
}

export async function getCompanyConfig(companyId: number) {
  try {
    await ensureCompanyConfig(companyId);
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: { config: true },
    });

    if (!company) {
      throw { status: 404, message: 'Compa\u00f1\u00eda no encontrada' };
    }

    return mapConfigResponse(company);
  } catch (err) {
    if (isMissingCompanyConfigTable(err)) {
      const company = await prisma.company.findUnique({
        where: { id: companyId },
      });
      if (!company) {
        throw { status: 404, message: 'Compa\u00f1\u00eda no encontrada' };
      }
      return mapConfigResponse({ ...company, config: null } as CompanyWithConfig);
    }
    throw err;
  }
}

export async function updateCompanyConfig(companyId: number, payload: UpdateCompanyConfigInput) {
  const companyName = normalizeRequired(payload.companyName);
  const normalized = {
    logoUrl:
      payload.logoUrl !== undefined ? normalizeNullable(payload.logoUrl) : undefined,
    phone: payload.phone !== undefined ? normalizeNullable(payload.phone) : undefined,
    phone2:
      payload.phone2 !== undefined ? normalizeNullable(payload.phone2) : undefined,
    email: payload.email !== undefined ? normalizeNullable(payload.email) : undefined,
    address:
      payload.address !== undefined ? normalizeNullable(payload.address) : undefined,
    city: payload.city !== undefined ? normalizeNullable(payload.city) : undefined,
    slogan: payload.slogan !== undefined ? normalizeNullable(payload.slogan) : undefined,
    website: payload.website !== undefined ? normalizeNullable(payload.website) : undefined,
    instagramUrl:
      payload.instagramUrl !== undefined ? normalizeNullable(payload.instagramUrl) : undefined,
    facebookUrl:
      payload.facebookUrl !== undefined ? normalizeNullable(payload.facebookUrl) : undefined,
  };

  const themeKey = normalizeRequired(payload.themeKey);
  const configUpdate: Prisma.CompanyConfigUpdateInput = {};

  if (normalized.logoUrl !== undefined) configUpdate.logoUrl = normalized.logoUrl;
  if (normalized.phone !== undefined) configUpdate.phone = normalized.phone;
  if (normalized.phone2 !== undefined) configUpdate.phone2 = normalized.phone2;
  if (normalized.email !== undefined) configUpdate.email = normalized.email;
  if (normalized.address !== undefined) configUpdate.address = normalized.address;
  if (normalized.city !== undefined) configUpdate.city = normalized.city;
  if (normalized.slogan !== undefined) configUpdate.slogan = normalized.slogan;
  if (normalized.website !== undefined) configUpdate.website = normalized.website;
  if (normalized.instagramUrl !== undefined)
    configUpdate.instagramUrl = normalized.instagramUrl;
  if (normalized.facebookUrl !== undefined)
    configUpdate.facebookUrl = normalized.facebookUrl;
  if (themeKey !== undefined) configUpdate.themeKey = themeKey;

  if (companyName) {
    await prisma.company.update({
      where: { id: companyId },
      data: { name: companyName },
    });
  }

  const configCreate: Prisma.CompanyConfigCreateInput = {
    company: { connect: { id: companyId } },
    themeKey: themeKey ?? DEFAULT_THEME_KEY,
  };

  if (normalized.logoUrl !== undefined) configCreate.logoUrl = normalized.logoUrl;
  if (normalized.phone !== undefined) configCreate.phone = normalized.phone;
  if (normalized.phone2 !== undefined) configCreate.phone2 = normalized.phone2;
  if (normalized.email !== undefined) configCreate.email = normalized.email;
  if (normalized.address !== undefined) configCreate.address = normalized.address;
  if (normalized.city !== undefined) configCreate.city = normalized.city;
  if (normalized.slogan !== undefined) configCreate.slogan = normalized.slogan;
  if (normalized.website !== undefined) configCreate.website = normalized.website;
  if (normalized.instagramUrl !== undefined)
    configCreate.instagramUrl = normalized.instagramUrl;
  if (normalized.facebookUrl !== undefined)
    configCreate.facebookUrl = normalized.facebookUrl;

  try {
    await prisma.companyConfig.upsert({
      where: { companyId },
      update: configUpdate,
      create: configCreate,
    });

    return getCompanyConfig(companyId);
  } catch (err) {
    if (isMissingCompanyConfigTable(err)) {
      console.warn(
        '[cloud_sync] CompanyConfig table missing (run migrations). Skipping config upsert.',
      );
      const company = await prisma.company.findUnique({
        where: { id: companyId },
      });
      if (!company) {
        throw { status: 404, message: 'Compa\u00f1\u00eda no encontrada' };
      }
      return mapConfigResponse({ ...company, config: null } as CompanyWithConfig);
    }
    throw err;
  }
}

export async function updateCompanyConfigByRnc(
  companyRnc: string | undefined,
  payload: UpdateCompanyConfigInput,
) {
  const trimmedRnc = companyRnc?.trim() ?? '';
  const cloudId = payload.companyCloudId?.trim() ?? '';
  const companyName = normalizeRequired(payload.companyName);

  if (!trimmedRnc && !cloudId) {
    throw { status: 400, message: 'RNC o ID interno requerido' };
  }

  let company = null as {
    id: number;
    rnc: string | null;
    name: string;
    isActive: boolean;
  } | null;

  if (cloudId) {
    company = await prisma.company.findFirst({
      where: { cloudCompanyId: cloudId },
      select: { id: true, rnc: true, name: true, isActive: true },
    });
  }

  if (!company && trimmedRnc) {
    const normalized = normalizeRnc(trimmedRnc);
    company = await prisma.company.findFirst({
      where: { rnc: trimmedRnc },
      select: { id: true, rnc: true, name: true, isActive: true },
    });

    if (!company && normalized.length > 0) {
      const candidates = await prisma.company.findMany({
        where: { rnc: { not: null } },
        select: { id: true, rnc: true, name: true, isActive: true },
      });
      company =
        candidates.find(
          (item) => item.rnc != null && normalizeRnc(item.rnc) === normalized,
        ) ?? null;
    }
  }

  if (company && !company.isActive) {
    company = await prisma.company.update({
      where: { id: company.id },
      data: { isActive: true },
      select: { id: true, rnc: true, name: true, isActive: true },
    });
  }

  if (!company) {
    const nameSeed = trimmedRnc || cloudId;
    let resolvedName = companyName ?? `Empresa ${nameSeed}`;
    const nameClash = await prisma.company.findFirst({
      where: { name: resolvedName },
      select: { id: true },
    });
    if (nameClash) {
      resolvedName = `Empresa ${nameSeed}`;
    }
    company = await prisma.company.create({
      data: {
        name: resolvedName,
        rnc: trimmedRnc || null,
        cloudCompanyId: cloudId || null,
        isActive: true,
      },
      select: { id: true, rnc: true, name: true, isActive: true },
    });
  } else if (cloudId) {
    await prisma.company.update({
      where: { id: company.id },
      data: { cloudCompanyId: normalizeCloudId(cloudId) },
    });
  }

  return updateCompanyConfig(company.id, payload);
}

type DangerActionType = 'RESET' | 'DELETE';

async function resolveCompanyIdForDanger(companyRnc?: string, companyCloudId?: string) {
  const rnc = companyRnc?.trim() ?? '';
  const cloudId = companyCloudId?.trim() ?? '';
  if (!rnc && !cloudId) return null;

  if (cloudId) {
    const byCloud = await prisma.company.findFirst({
      where: { cloudCompanyId: cloudId },
      select: { id: true },
    });
    if (byCloud) return byCloud.id;
  }

  if (!rnc) return null;
  const byRnc = await prisma.company.findFirst({
    where: { rnc },
    select: { id: true },
  });
  if (byRnc) return byRnc.id;

  const normalized = normalizeRnc(rnc);
  if (!normalized) return null;
  const candidates = await prisma.company.findMany({
    where: { rnc: { not: null } },
    select: { id: true, rnc: true },
  });
  const match = candidates.find(
    (item) => item.rnc != null && normalizeRnc(item.rnc) === normalized,
  );
  return match?.id ?? null;
}

export async function dangerousCompanyAction({
  action,
  companyRnc,
  companyCloudId,
}: {
  action: DangerActionType;
  companyRnc?: string;
  companyCloudId?: string;
}) {
  const companyId = await resolveCompanyIdForDanger(companyRnc, companyCloudId);
  if (!companyId) {
    throw { status: 400, message: 'Empresa requerida' };
  }

  if (action === 'RESET') {
    await prisma.$transaction([
      prisma.saleItem.deleteMany({ where: { sale: { companyId } } }),
      prisma.sale.deleteMany({ where: { companyId } }),
      prisma.quoteItem.deleteMany({ where: { quote: { companyId } } }),
      prisma.quote.deleteMany({ where: { companyId } }),
      prisma.cashMovement.deleteMany({ where: { companyId } }),
      prisma.cashSession.deleteMany({ where: { companyId } }),
      prisma.expense.deleteMany({ where: { companyId } }),
      prisma.product.deleteMany({ where: { companyId } }),
      prisma.cloudBackup.deleteMany({ where: { companyId } }),
    ]);
  } else {
    await prisma.$transaction([
      prisma.saleItem.deleteMany({ where: { sale: { companyId } } }),
      prisma.sale.deleteMany({ where: { companyId } }),
      prisma.quoteItem.deleteMany({ where: { quote: { companyId } } }),
      prisma.quote.deleteMany({ where: { companyId } }),
      prisma.cashMovement.deleteMany({ where: { companyId } }),
      prisma.cashSession.deleteMany({ where: { companyId } }),
      prisma.expense.deleteMany({ where: { companyId } }),
      prisma.product.deleteMany({ where: { companyId } }),
      prisma.cloudBackup.deleteMany({ where: { companyId } }),
      prisma.companyConfig.deleteMany({ where: { companyId } }),
      prisma.terminal.deleteMany({ where: { companyId } }),
      prisma.overrideToken.deleteMany({ where: { companyId } }),
      prisma.overrideRequest.deleteMany({ where: { companyId } }),
      prisma.auditLog.deleteMany({ where: { companyId } }),
      prisma.user.deleteMany({ where: { companyId } }),
      prisma.company.delete({ where: { id: companyId } }),
    ]);
  }

  await prisma.auditLog.create({
    data: {
      companyId,
      actionCode: action === 'RESET' ? 'DANGER_RESET' : 'DANGER_DELETE',
      result: 'SUCCESS',
      method: 'API',
      createdAt: new Date(),
      meta: {
        companyRnc: companyRnc ?? null,
        companyCloudId: companyCloudId ?? null,
      },
    },
  });

  return { ok: true };
}
