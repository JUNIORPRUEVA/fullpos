/*
  Backfill de costo (purchasePriceSnapshot) en SaleItem a partir de Product.cost.

  Problema que resuelve:
  - Si el POS no manda purchasePriceSnapshot, queda 0.
  - El reporte de ganancia usa purchasePriceSnapshot * qty, por lo que el costo queda 0 y la ganancia sale igual al total.

  Seguridad:
  - Por defecto solo hace DRY RUN (no escribe).
  - Para ejecutar, requiere CONFIRM_BACKFILL=BACKFILL_SALEITEM_COST

  Opcional:
  - COMPANY_ID para limitar a una empresa.

  Uso (PowerShell):
    Set-Location "FULLPOS_BACKEND";

    # DRY RUN (recomendado)
    $env:COMPANY_ID="1";  # opcional
    node tools/backfill_saleitem_cost.js

    # EJECUTAR
    $env:COMPANY_ID="1";  # opcional
    $env:CONFIRM_BACKFILL="BACKFILL_SALEITEM_COST";
    node tools/backfill_saleitem_cost.js
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
    const confirm = process.env.CONFIRM_BACKFILL;
    const dryRun = confirm !== 'BACKFILL_SALEITEM_COST';

    console.log('Backfill SaleItem cost');
    console.log('COMPANY_ID:', companyId ?? '(all)');
    console.log('MODE:', dryRun ? 'DRY_RUN' : 'EXECUTE');

    const whereCompany = companyId ? ` AND s."companyId" = ${companyId}` : '';

    const [candidate] = await prisma.$queryRawUnsafe(`
      SELECT COUNT(*)::int AS count
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      INNER JOIN "Product" p ON p."companyId" = s."companyId" AND p."code" = si."productCodeSnapshot"
      WHERE s."deletedAt" IS NULL
        ${whereCompany}
        AND si."productCodeSnapshot" IS NOT NULL
        AND (si."productId" IS NULL)
        AND (si."purchasePriceSnapshot" = 0 OR si."purchasePriceSnapshot" IS NULL)
        AND p."cost" > 0;
    `);

    console.log('CANDIDATES:', candidate);

    if (dryRun) {
      console.log(
        'Dry run: set CONFIRM_BACKFILL=BACKFILL_SALEITEM_COST para ejecutar.',
      );
      return;
    }

    const updated = await prisma.$executeRawUnsafe(`
      UPDATE "SaleItem" si
      SET
        "productId" = p.id,
        "purchasePriceSnapshot" = p."cost"
      FROM "Sale" s
      INNER JOIN "Product" p ON p."companyId" = s."companyId" AND p."code" = si."productCodeSnapshot"
      WHERE si."saleId" = s.id
        AND s."deletedAt" IS NULL
        ${whereCompany}
        AND si."productCodeSnapshot" IS NOT NULL
        AND (si."productId" IS NULL)
        AND (si."purchasePriceSnapshot" = 0 OR si."purchasePriceSnapshot" IS NULL)
        AND p."cost" > 0;
    `);

    console.log('UPDATED_ROWS:', updated);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error('BACKFILL_ERROR:', e);
  process.exit(1);
});
