const { PrismaClient } = require('@prisma/client');

function parseCompanyId() {
  const raw = process.env.COMPANY_ID;
  if (!raw) return null;
  const id = Number(raw);
  if (!Number.isInteger(id) || id <= 0) return null;
  return id;
}

async function main() {
  const prisma = new PrismaClient();
  try {
    const companyId = parseCompanyId();

    const tables = await prisma.$queryRawUnsafe(
      "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name",
    );
    console.log('TABLES:', tables.map((t) => t.table_name).join(', '));

    const companies = await prisma.company.findMany({
      select: { id: true, name: true, rnc: true, cloudCompanyId: true },
      orderBy: { id: 'asc' },
    });
    console.log('COMPANIES:', companies);

    const whereCompany = companyId ? ` WHERE "companyId" = ${companyId}` : '';
    const [counts] = await prisma.$queryRawUnsafe(`
      SELECT
        (SELECT COUNT(*)::int FROM "Company")      AS companies,
        (SELECT COUNT(*)::int FROM "User")         AS users,
        (SELECT COUNT(*)::int FROM "Sale"${whereCompany})         AS sales,
        (SELECT COUNT(*)::int FROM "SaleItem" si
           INNER JOIN "Sale" s ON s.id = si."saleId"${companyId ? ` WHERE s."companyId" = ${companyId}` : ''}
        ) AS sale_items,
        (SELECT COUNT(*)::int FROM "CashSession"${whereCompany})  AS cash_sessions,
        (SELECT COUNT(*)::int FROM "CashMovement"${whereCompany}) AS cash_movements,
        (SELECT COUNT(*)::int FROM "Expense"${whereCompany})      AS expenses,
        (SELECT COUNT(*)::int FROM "Quote"${whereCompany})        AS quotes,
        (SELECT COUNT(*)::int FROM "Product"${whereCompany})      AS products,
        (SELECT COUNT(*)::int FROM "Terminal"${whereCompany})     AS terminals;
    `);
    console.log(companyId ? `COUNTS(companyId=${companyId}):` : 'COUNTS(all):', counts);

    const [lastSale] = await prisma.$queryRawUnsafe(`
      SELECT
        MAX("createdAt") AS last_sale_at,
        MAX("updatedAt") AS last_sale_updated_at
      FROM "Sale"${whereCompany};
    `);
    console.log(companyId ? `LAST_SALE(companyId=${companyId}):` : 'LAST_SALE(all):', lastSale);

    const kinds = await prisma.$queryRawUnsafe(`
      SELECT
        kind,
        status,
        COUNT(*)::int AS count,
        COALESCE(SUM(total), 0)::float AS total
      FROM "Sale"
      WHERE "deletedAt" IS NULL
      ${companyId ? ` AND "companyId" = ${companyId}` : ''}
      GROUP BY kind, status
      ORDER BY count DESC;
    `);
    console.log(companyId ? `SALES_BY_KIND_STATUS(companyId=${companyId}):` : 'SALES_BY_KIND_STATUS(all):', kinds);

    const sample = await prisma.$queryRawUnsafe(`
      SELECT
        id,
        "companyId",
        "localCode",
        kind,
        status,
        total::float AS total,
        "paymentMethod",
        "createdAt"
      FROM "Sale"
      WHERE "deletedAt" IS NULL
      ${companyId ? ` AND "companyId" = ${companyId}` : ''}
      ORDER BY "createdAt" DESC
      LIMIT 10;
    `);
    console.log(companyId ? `LAST_10_SALES(companyId=${companyId}):` : 'LAST_10_SALES(all):', sample);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error('DB_CHECK_ERROR:', e);
  process.exit(1);
});
