import crypto from 'crypto';
import jwt, { JwtPayload, Secret, SignOptions } from 'jsonwebtoken';
import { Prisma } from '@prisma/client';
import { prisma } from '../../config/prisma';
import env from '../../config/env';
import { verifyPassword, hashPassword } from '../../utils/password';
import { JwtUser, TokenPair } from './auth.types';

function parseDurationToMs(duration: string): number {
  const fallback = 15 * 60 * 1000;
  const match = duration.trim().match(/^(\d+)\s*([smhd])?$/i);
  if (!match) return fallback;

  const value = Number(match[1]);
  const unit = match[2]?.toLowerCase() ?? 's';

  const ms =
    unit === 'd'
      ? value * 24 * 60 * 60 * 1000
      : unit === 'h'
        ? value * 60 * 60 * 1000
        : unit === 'm'
          ? value * 60 * 1000
          : value * 1000;

  return ms > 0 ? ms : fallback;
}

function buildJwtPayload(user: {
  id: number;
  companyId: number;
  username: string;
  role: string;
  email: string | null;
}): JwtUser {
  return {
    id: user.id,
    companyId: user.companyId,
    username: user.username,
    role: user.role,
    email: user.email ?? undefined,
  };
}

async function createRefreshToken(userId: number) {
  const rawToken = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const expiresAt = new Date(Date.now() + parseDurationToMs(env.JWT_REFRESH_EXPIRES_IN));

  try {
    await prisma.refreshToken.create({
      data: {
        tokenHash,
        userId,
        expiresAt,
      },
    });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2021') {
      throw {
        status: 503,
        message:
          'Base de datos sin migraciones (RefreshToken). Ejecuta "prisma migrate deploy" en el backend.',
      };
    }
    throw err;
  }

  return { token: rawToken, expiresAt };
}

async function deleteRefreshToken(tokenHash: string) {
  await prisma.refreshToken.deleteMany({
    where: { tokenHash },
  });
}

async function generateTokenPair(user: JwtUser): Promise<TokenPair> {
  const accessToken = jwt.sign(
    user as JwtPayload,
    env.JWT_ACCESS_SECRET as Secret,
    { expiresIn: env.JWT_ACCESS_EXPIRES_IN } as SignOptions,
  );

  const refresh = await createRefreshToken(user.id);
  const expiresInSeconds = Math.floor(parseDurationToMs(env.JWT_ACCESS_EXPIRES_IN) / 1000);

  return {
    accessToken,
    refreshToken: refresh.token,
    expiresIn: expiresInSeconds,
  };
}

export async function login(identifier: string, password: string) {
  const user = await prisma.user.findFirst({
    where: {
      isActive: true,
      OR: [{ username: identifier }, { email: identifier }],
    },
    include: { company: true },
  });

  if (!user || !user.company || !user.company.isActive) {
    throw { status: 401, message: 'Credenciales inv\u00e1lidas' };
  }

  let passwordMatches = false;
  try {
    passwordMatches = await verifyPassword(password, user.password);
  } catch {
    // Legacy DB: password stored in plain text (or invalid hash). If it matches,
    // allow login and upgrade to bcrypt.
    if (user.password === password) {
      passwordMatches = true;
      const hashed = await hashPassword(password);
      await prisma.user.update({
        where: { id: user.id },
        data: { password: hashed },
      });
    } else {
      passwordMatches = false;
    }
  }
  if (!passwordMatches) {
    throw { status: 401, message: 'Credenciales inv\u00e1lidas' };
  }

  const payload = buildJwtPayload(user);
  const tokens = await generateTokenPair(payload);

  return {
    user: {
      id: user.id,
      username: user.username,
      email: user.email,
      role: user.role,
      companyId: user.companyId,
      displayName: user.displayName,
    },
    company: {
      id: user.company.id,
      name: user.company.name,
      rnc: user.company.rnc,
      androidUrl: user.company.ownerAppAndroidUrl,
      iosUrl: user.company.ownerAppIosUrl,
      version: user.company.ownerAppVersion,
    },
    tokens,
  };
}

export async function refresh(refreshToken: string) {
  const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
  const stored = await prisma.refreshToken.findUnique({
    where: { tokenHash },
    include: {
      user: { include: { company: true } },
    },
  });

  if (
    !stored ||
    !stored.user ||
    !stored.user.company ||
    stored.expiresAt.getTime() < Date.now() ||
    stored.user.isActive === false
  ) {
    throw { status: 401, message: 'Token de refresh inv\u00e1lido' };
  }

  // Rotate token
  await deleteRefreshToken(tokenHash);

  const payload = buildJwtPayload(stored.user);
  const tokens = await generateTokenPair(payload);

  return {
    user: {
      id: stored.user.id,
      username: stored.user.username,
      email: stored.user.email,
      role: stored.user.role,
      companyId: stored.user.companyId,
      displayName: stored.user.displayName,
    },
    company: {
      id: stored.user.company.id,
      name: stored.user.company.name,
      rnc: stored.user.company.rnc,
      androidUrl: stored.user.company.ownerAppAndroidUrl,
      iosUrl: stored.user.company.ownerAppIosUrl,
      version: stored.user.company.ownerAppVersion,
    },
    tokens,
  };
}

export async function getProfile(userId: number) {
  const user = await prisma.user.findFirst({
    where: { id: userId, isActive: true },
    include: { company: true },
  });

  if (!user || !user.company || !user.company.isActive) {
    throw { status: 401, message: 'Usuario no encontrado o inactivo' };
  }

  return {
    id: user.id,
    username: user.username,
    email: user.email,
    role: user.role,
    displayName: user.displayName,
    company: {
      id: user.company.id,
      name: user.company.name,
      rnc: user.company.rnc,
      androidUrl: user.company.ownerAppAndroidUrl,
      iosUrl: user.company.ownerAppIosUrl,
      version: user.company.ownerAppVersion,
    },
  };
}

// Utilidad para el seeding
export async function ensureUserPassword(userId: number, password: string) {
  const hashed = await hashPassword(password);
  await prisma.user.update({
    where: { id: userId },
    data: { password: hashed },
  });
}

function normalizeRnc(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function normalizeCloudId(value: string) {
  return value.trim();
}

async function resolveCompanyForProvision(params: {
  companyRnc?: string;
  companyCloudId?: string;
  companyName?: string;
}) {
  const rnc = params.companyRnc?.trim() ?? '';
  const cloudId = params.companyCloudId?.trim() ?? '';
  const cname = params.companyName?.trim();

  if (!rnc && !cloudId) {
    throw { status: 400, message: 'RNC o ID interno requerido' };
  }

  let company = null as { id: number; name: string; rnc: string | null; isActive: boolean } | null;

  if (cloudId) {
    company = await prisma.company.findFirst({
      where: { cloudCompanyId: cloudId },
      select: { id: true, name: true, rnc: true, isActive: true },
    });
  }

  if (!company && rnc) {
    const normalized = normalizeRnc(rnc);
    company = await prisma.company.findFirst({
      where: { rnc: rnc },
      select: { id: true, name: true, rnc: true, isActive: true },
    });

    if (!company && normalized.length > 0) {
      const candidates = await prisma.company.findMany({
        where: { rnc: { not: null } },
        select: { id: true, name: true, rnc: true, isActive: true },
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
      select: { id: true, name: true, rnc: true, isActive: true },
    });
  }

  if (!company) {
    const nameSeed = rnc || cloudId;
    let resolvedName = cname && cname.length > 1 ? cname : `Empresa ${nameSeed}`;
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
        rnc: rnc || null,
        cloudCompanyId: cloudId || null,
        isActive: true,
      },
      select: { id: true, name: true, rnc: true, isActive: true },
    });
  } else if (cloudId) {
    await prisma.company.update({
      where: { id: company.id },
      data: { cloudCompanyId: normalizeCloudId(cloudId) },
    });
  }

  return company;
}

export async function provisionOwnerByRnc(
  companyRnc: string | undefined,
  username: string,
  password: string,
  companyName?: string,
  companyCloudId?: string,
) {
  const rnc = companyRnc?.trim() ?? '';
  const cloudId = companyCloudId?.trim() ?? '';
  const uname = username.trim();
  const cname = companyName?.trim();
  if ((!rnc && !cloudId) || !uname) {
    throw { status: 400, message: 'Datos incompletos' };
  }
  const company = await resolveCompanyForProvision({
    companyRnc: rnc,
    companyCloudId: cloudId,
    companyName: cname,
  });

  const hashed = await hashPassword(password);

  // 1) Si ya existe un owner para la empresa, actualízalo.
  const existingOwner = await prisma.user.findFirst({
    where: { companyId: company.id, role: 'owner' },
  });

  if (existingOwner) {
    // Validar que el username no esté tomado por otro usuario.
    const clash = await prisma.user.findFirst({
      where: { username: uname, NOT: { id: existingOwner.id } },
    });
    if (clash) {
      throw { status: 409, message: 'Ese usuario ya existe. Usa otro.' };
    }

    const updated = await prisma.user.update({
      where: { id: existingOwner.id },
      data: {
        username: uname,
        password: hashed,
        isActive: true,
      },
    });

    return {
      company: { id: company.id, name: company.name, rnc: company.rnc },
      user: { id: updated.id, username: updated.username, role: updated.role },
    };
  }

  // 2) Si no existe, crear owner.
  const created = await prisma.user.create({
    data: {
      companyId: company.id,
      username: uname,
      password: hashed,
      role: 'owner',
      isActive: true,
    },
  });

  return {
    company: { id: company.id, name: company.name, rnc: company.rnc },
    user: { id: created.id, username: created.username, role: created.role },
  };
}

export async function provisionAdminUser(params: {
  companyRnc?: string;
  companyCloudId?: string;
  companyName?: string;
  username: string;
  password: string;
}) {
  const uname = params.username.trim();
  if (!uname) throw { status: 400, message: 'Usuario requerido' };

  const company = await resolveCompanyForProvision({
    companyRnc: params.companyRnc,
    companyCloudId: params.companyCloudId,
    companyName: params.companyName,
  });

  const hashed = await hashPassword(params.password);

  const existing = await prisma.user.findFirst({
    where: { username: uname },
    select: { id: true, companyId: true },
  });

  if (existing && existing.companyId !== company.id) {
    throw { status: 409, message: 'Ese usuario ya existe. Usa otro.' };
  }

  if (existing) {
    const updated = await prisma.user.update({
      where: { id: existing.id },
      data: {
        companyId: company.id,
        password: hashed,
        role: 'admin',
        isActive: true,
      },
    });
    return {
      company: { id: company.id, name: company.name, rnc: company.rnc },
      user: { id: updated.id, username: updated.username, role: updated.role },
    };
  }

  const created = await prisma.user.create({
    data: {
      companyId: company.id,
      username: uname,
      password: hashed,
      role: 'admin',
      isActive: true,
    },
  });

  return {
    company: { id: company.id, name: company.name, rnc: company.rnc },
    user: { id: created.id, username: created.username, role: created.role },
  };
}
