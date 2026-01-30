/*
  Purga datos transaccionales de una empresa (companyId) en el backend.
  
  Seguridad:
  - Requiere CONFIRM_PURGE=DELETE_COMPANY_DATA
  - Requiere COMPANY_ID
  - Por defecto NO borra Company/Users (solo data transaccional)

  Uso (PowerShell):
    Set-Location "FULLPOS_BACKEND";
    $env:COMPANY_ID="1";
    $env:CONFIRM_PURGE="DELETE_COMPANY_DATA";
    node tools/purge_company_data.js

  Opcionales:
    $env:PURGE_PRODUCTS="true";   # también borra productos
    $env:PURGE_TERMINALS="true";  # también borra terminales
*/

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

function parseBool(value) {
  if (!value) return false;
  return String(value).toLowerCase() === 'true' || String(value) === '1';
}

async function main() {
  const companyIdRaw = process.env.COMPANY_ID;
  const confirm = process.env.CONFIRM_PURGE;

  if (!companyIdRaw) {
    throw new Error('Falta COMPANY_ID (por ejemplo: $env:COMPANY_ID="1")');
  }

  const companyId = Number(companyIdRaw);
  if (!Number.isInteger(companyId) || companyId <= 0) {
    throw new Error(`COMPANY_ID inválido: ${companyIdRaw}`);
  }

  if (confirm !== 'DELETE_COMPANY_DATA') {
    throw new Error(
      'Confirmación requerida: set CONFIRM_PURGE=DELETE_COMPANY_DATA para ejecutar la purga.',
    );
  }

  const purgeProducts = parseBool(process.env.PURGE_PRODUCTS);
  const purgeTerminals = parseBool(process.env.PURGE_TERMINALS);

  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: { id: true, name: true, rnc: true, cloudCompanyId: true },
  });

  if (!company) {
    throw new Error(`No existe Company con id=${companyId}`);
  }

  const before = await getCounts(companyId);
  console.log('Empresa:', company);
  console.log('Antes:', before);

  // Orden de borrado para evitar problemas con FKs.
  // Nota: SaleItem y QuoteItem tienen onDelete: Cascade desde su padre.
  const result = await prisma.$transaction(async (tx) => {
    const deleted = {};

    deleted.cashMovements = await tx.cashMovement.deleteMany({
      where: { companyId },
    });

    deleted.sales = await tx.sale.deleteMany({
      where: { companyId },
    });

    deleted.cashSessions = await tx.cashSession.deleteMany({
      where: { companyId },
    });

    deleted.expenses = await tx.expense.deleteMany({
      where: { companyId },
    });

    deleted.quotes = await tx.quote.deleteMany({
      where: { companyId },
    });

    deleted.auditLogs = await tx.auditLog.deleteMany({
      where: { companyId },
    });

    // Overrides (si existen) pueden tener relación entre sí.
    deleted.overrideTokens = await tx.overrideToken.deleteMany({
      where: { companyId },
    });
    deleted.overrideRequests = await tx.overrideRequest.deleteMany({
      where: { companyId },
    });

    if (purgeTerminals) {
      deleted.terminals = await tx.terminal.deleteMany({ where: { companyId } });
    }

    if (purgeProducts) {
      // Productos no son estrictamente “reportes”, pero a veces son demo.
      // Borrar productos puede fallar si existen referencias en SaleItem/QuoteItem;
      // en nuestro esquema productId es opcional, así que normalmente no hay bloqueo.
      deleted.products = await tx.product.deleteMany({ where: { companyId } });
    }

    return deleted;
  });

  console.log('Borrados:', summarizeDeleteMany(result));

  const after = await getCounts(companyId);
  console.log('Después:', after);

  console.log(
    'OK. Ahora ejecuta sincronización desde FULLPOS para recargar ventas/caja/gastos/cotizaciones.',
  );
}

async function getCounts(companyId) {
  const [
    sales,
    saleItems,
    cashSessions,
    cashMovements,
    expenses,
    quotes,
    quoteItems,
    auditLogs,
    overrideTokens,
    overrideRequests,
    terminals,
    products,
  ] = await Promise.all([
    prisma.sale.count({ where: { companyId } }),
    prisma.saleItem.count({ where: { sale: { companyId } } }),
    prisma.cashSession.count({ where: { companyId } }),
    prisma.cashMovement.count({ where: { companyId } }),
    prisma.expense.count({ where: { companyId } }),
    prisma.quote.count({ where: { companyId } }),
    prisma.quoteItem.count({ where: { quote: { companyId } } }),
    prisma.auditLog.count({ where: { companyId } }),
    prisma.overrideToken.count({ where: { companyId } }),
    prisma.overrideRequest.count({ where: { companyId } }),
    prisma.terminal.count({ where: { companyId } }),
    prisma.product.count({ where: { companyId } }),
  ]);

  return {
    sales,
    saleItems,
    cashSessions,
    cashMovements,
    expenses,
    quotes,
    quoteItems,
    auditLogs,
    overrideTokens,
    overrideRequests,
    terminals,
    products,
  };
}

function summarizeDeleteMany(obj) {
  const out = {};
  for (const [key, val] of Object.entries(obj)) {
    if (val && typeof val === 'object' && 'count' in val) out[key] = val.count;
  }
  return out;
}

main()
  .catch((err) => {
    console.error('ERROR:', err?.message ?? err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
