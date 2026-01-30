/*
  Elimina COMPLETAMENTE una empresa (Company) y TODA su data asociada.

  Seguridad:
  - Requiere COMPANY_ID
  - Requiere CONFIRM_DELETE_COMPANY=DELETE_COMPANY

  Uso (PowerShell):
    Set-Location "FULLPOS_BACKEND";
    $env:COMPANY_ID="1";
    $env:CONFIRM_DELETE_COMPANY="DELETE_COMPANY";
    node tools/delete_company.js

  Nota:
  - Este script borra: ventas, caja, gastos, cotizaciones, productos, terminales,
    auditoría, overrides, configuración de empresa, usuarios de la empresa y sus refresh tokens.
*/

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  const companyIdRaw = process.env.COMPANY_ID;
  const confirm = process.env.CONFIRM_DELETE_COMPANY;

  if (!companyIdRaw) {
    throw new Error('Falta COMPANY_ID (por ejemplo: $env:COMPANY_ID="1")');
  }

  const companyId = Number(companyIdRaw);
  if (!Number.isInteger(companyId) || companyId <= 0) {
    throw new Error(`COMPANY_ID inválido: ${companyIdRaw}`);
  }

  if (confirm !== 'DELETE_COMPANY') {
    throw new Error(
      'Confirmación requerida: set CONFIRM_DELETE_COMPANY=DELETE_COMPANY para eliminar la empresa.',
    );
  }

  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: { id: true, name: true, rnc: true, cloudCompanyId: true },
  });

  if (!company) {
    throw new Error(`No existe Company con id=${companyId}`);
  }

  const users = await prisma.user.findMany({
    where: { companyId },
    select: { id: true, username: true, email: true, role: true },
    orderBy: { id: 'asc' },
  });

  console.log('Eliminar empresa:', company);
  console.log('Usuarios a eliminar:', users);

  const userIds = users.map((u) => u.id);

  const result = await prisma.$transaction(async (tx) => {
    const deleted = {};

    // Transaccional / reportes
    deleted.cashMovements = await tx.cashMovement.deleteMany({ where: { companyId } });
    deleted.sales = await tx.sale.deleteMany({ where: { companyId } }); // cascada a SaleItem
    deleted.cashSessions = await tx.cashSession.deleteMany({ where: { companyId } });
    deleted.expenses = await tx.expense.deleteMany({ where: { companyId } });
    deleted.quotes = await tx.quote.deleteMany({ where: { companyId } }); // cascada a QuoteItem

    // Auditoría / overrides
    deleted.auditLogs = await tx.auditLog.deleteMany({ where: { companyId } });
    deleted.overrideTokens = await tx.overrideToken.deleteMany({ where: { companyId } });
    deleted.overrideRequests = await tx.overrideRequest.deleteMany({ where: { companyId } });

    // Catálogos / dispositivos
    deleted.terminals = await tx.terminal.deleteMany({ where: { companyId } });
    deleted.products = await tx.product.deleteMany({ where: { companyId } });

    // Config
    deleted.companyConfig = await tx.companyConfig.deleteMany({ where: { companyId } });

    // Usuarios + refresh tokens
    if (userIds.length > 0) {
      deleted.refreshTokens = await tx.refreshToken.deleteMany({
        where: { userId: { in: userIds } },
      });
      deleted.users = await tx.user.deleteMany({ where: { companyId } });
    } else {
      deleted.refreshTokens = { count: 0 };
      deleted.users = { count: 0 };
    }

    // Finalmente, la empresa
    deleted.company = await tx.company.delete({ where: { id: companyId } });

    return deleted;
  });

  console.log('OK. Empresa eliminada. Resumen:');
  console.log({
    cashMovements: result.cashMovements.count,
    sales: result.sales.count,
    cashSessions: result.cashSessions.count,
    expenses: result.expenses.count,
    quotes: result.quotes.count,
    auditLogs: result.auditLogs.count,
    overrideTokens: result.overrideTokens.count,
    overrideRequests: result.overrideRequests.count,
    terminals: result.terminals.count,
    products: result.products.count,
    companyConfig: result.companyConfig.count,
    refreshTokens: result.refreshTokens.count,
    users: result.users.count,
    companyDeletedId: result.company.id,
  });
}

main()
  .catch((err) => {
    console.error('ERROR:', err?.message ?? err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
