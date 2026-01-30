/*
  Diagnóstico de costos/ganancias.

  Uso:
    Set-Location "FULLPOS_BACKEND";
    $env:COMPANY_ID="1"; # opcional
    node tools/cost_diagnostics.js
*/

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
    const whereCompany = companyId ? ` WHERE "companyId" = ${companyId}` : '';

    const [products] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count,
             COALESCE(SUM(cost),0)::float AS sum_cost,
             COALESCE(SUM(price),0)::float AS sum_price
      FROM "Product"${whereCompany};
    `);

    const [productsCostGt0] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count
      FROM "Product"${companyId ? ` WHERE "companyId" = ${companyId} AND cost > 0` : ' WHERE cost > 0'};
    `);

    const [saleItemsCost0] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      WHERE s."deletedAt" IS NULL
        ${companyId ? ` AND s."companyId" = ${companyId}` : ''}
        AND si."purchasePriceSnapshot" = 0;
    `);

    const [saleItemsCost0WithCode] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      WHERE s."deletedAt" IS NULL
        ${companyId ? ` AND s."companyId" = ${companyId}` : ''}
        AND si."purchasePriceSnapshot" = 0
        AND si."productCodeSnapshot" IS NOT NULL;
    `);

    const [saleItemsCost0JoinByCodeCostGt0] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      INNER JOIN "Product" p ON p."companyId" = s."companyId" AND p."code" = si."productCodeSnapshot"
      WHERE s."deletedAt" IS NULL
        ${companyId ? ` AND s."companyId" = ${companyId}` : ''}
        AND si."purchasePriceSnapshot" = 0
        AND si."productCodeSnapshot" IS NOT NULL
        AND p."cost" > 0;
    `);

    const [totalCostFromSnapshots] = await prisma.$queryRawUnsafe(`
      SELECT COALESCE(SUM(si."purchasePriceSnapshot" * si."qty"), 0)::float AS total_cost
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      WHERE s."deletedAt" IS NULL
        ${companyId ? ` AND s."companyId" = ${companyId}` : ''};
    `);

    const sampleItems = await prisma.$queryRawUnsafe(`
      SELECT
        si.id,
        s."companyId",
        s."localCode",
        si."productCodeSnapshot",
        si."productId",
        si.qty::float AS qty,
        si."purchasePriceSnapshot"::float AS purchase_cost,
        si."unitPrice"::float AS unit_price,
        si."totalLine"::float AS total_line
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      WHERE s."deletedAt" IS NULL
        ${companyId ? ` AND s."companyId" = ${companyId}` : ''}
      ORDER BY si.id DESC
      LIMIT 20;
    `);

    console.log({
      companyId: companyId ?? '(all)',
      products,
      productsCostGt0,
      saleItemsCost0,
      saleItemsCost0WithCode,
      saleItemsCost0JoinByCodeCostGt0,
      totalCostFromSnapshots,
      sampleItems,
    });
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error('DIAGNOSTICS_ERROR:', e);
  process.exit(1);
});
