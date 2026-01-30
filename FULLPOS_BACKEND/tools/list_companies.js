const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  const companies = await prisma.company.findMany({
    select: { id: true, name: true, rnc: true, cloudCompanyId: true, isActive: true },
    orderBy: { id: 'asc' },
  });

  if (companies.length === 0) {
    console.log('No hay empresas en la base de datos.');
    return;
  }

  console.table(
    companies.map((c) => ({
      id: c.id,
      name: c.name,
      rnc: c.rnc ?? '',
      cloudCompanyId: c.cloudCompanyId ?? '',
      isActive: c.isActive,
    })),
  );
}

main()
  .catch((err) => {
    console.error('ERROR:', err?.message ?? err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
