-- Create expenses table scoped by company
CREATE TABLE "Expense" (
    "id" SERIAL PRIMARY KEY,
    "companyId" INTEGER NOT NULL,
    "createdById" INTEGER,
    "amount" DECIMAL(12, 2) NOT NULL,
    "category" TEXT NOT NULL,
    "note" TEXT,
    "incurredAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE "Expense"
    ADD CONSTRAINT "Expense_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Expense"
    ADD CONSTRAINT "Expense_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "Expense_companyId_incurredAt_idx" ON "Expense"("companyId", "incurredAt");
