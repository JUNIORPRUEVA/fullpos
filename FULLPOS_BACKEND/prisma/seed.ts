/* eslint-disable no-console */
import { prisma } from '../src/config/prisma';
import env from '../src/config/env';
import { hashPassword } from '../src/utils/password';

async function main() {
  const password = await hashPassword('fullpos123');

  // Semilla minimal: solo crea la empresa/usuario owner y limpia cualquier dato demo.
  const company = await prisma.company.upsert({
    where: { name: 'FULLPOS' },
    update: {
      ownerAppAndroidUrl: env.OWNER_APP_ANDROID_URL,
      ownerAppIosUrl: env.OWNER_APP_IOS_URL,
      ownerAppVersion: env.OWNER_APP_VERSION ?? '1.0.0',
    },
    create: {
      name: 'FULLPOS',
      rnc: '000000000',
      ownerAppAndroidUrl: env.OWNER_APP_ANDROID_URL,
      ownerAppIosUrl: env.OWNER_APP_IOS_URL,
      ownerAppVersion: env.OWNER_APP_VERSION ?? '1.0.0',
    },
  });

  const ownerUser = await prisma.user.upsert({
    where: { username: 'owner' },
    update: {
      password,
      role: 'owner',
      companyId: company.id,
      email: 'owner@fullpos.com',
      displayName: 'Demo Owner',
    },
    create: {
      username: 'owner',
      email: 'owner@fullpos.com',
      password,
      role: 'owner',
      companyId: company.id,
      displayName: 'Demo Owner',
    },
  });

  // Eliminar restos de datos demo si existieran.
  await prisma.product.deleteMany({ where: { companyId: company.id, isDemo: true } });
  await prisma.sale.deleteMany({ where: { companyId: company.id, localCode: { startsWith: 'POS-000' } } });
  await prisma.cashSession.deleteMany({
    where: { companyId: company.id, userName: ownerUser.username, status: 'CLOSED' },
  });

  await prisma.companyConfig.upsert({
    where: { companyId: company.id },
    update: { updatedAt: new Date() },
    create: {
      companyId: company.id,
      themeKey: 'proPos',
    },
  });

  console.log('Seed basico listo: empresa + usuario owner, sin datos demo.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
