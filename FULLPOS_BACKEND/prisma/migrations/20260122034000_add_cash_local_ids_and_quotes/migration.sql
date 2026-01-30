-- DropForeignKey
ALTER TABLE "Expense" DROP CONSTRAINT "Expense_companyId_fkey";

-- AlterTable
ALTER TABLE "CashMovement" ADD COLUMN     "localId" INTEGER;

-- AlterTable
ALTER TABLE "CashSession" ADD COLUMN     "localId" INTEGER;

-- AlterTable
ALTER TABLE "Expense" ALTER COLUMN "updatedAt" DROP DEFAULT;

-- CreateTable
CREATE TABLE "Quote" (
    "id" SERIAL NOT NULL,
    "companyId" INTEGER NOT NULL,
    "localId" INTEGER NOT NULL,
    "clientNameSnapshot" TEXT NOT NULL,
    "clientPhoneSnapshot" TEXT,
    "clientRncSnapshot" TEXT,
    "ticketName" TEXT,
    "subtotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "itbisEnabled" BOOLEAN NOT NULL DEFAULT true,
    "itbisRate" DECIMAL(5,4) NOT NULL DEFAULT 0.18,
    "itbisAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "discountTotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Quote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuoteItem" (
    "id" SERIAL NOT NULL,
    "quoteId" INTEGER NOT NULL,
    "localId" INTEGER,
    "productId" INTEGER,
    "productCodeSnapshot" TEXT,
    "productNameSnapshot" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "qty" DECIMAL(12,3) NOT NULL,
    "unitPrice" DECIMAL(12,2) NOT NULL,
    "price" DECIMAL(12,2) NOT NULL,
    "cost" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "discountLine" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "totalLine" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "QuoteItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Quote_companyId_createdAt_idx" ON "Quote"("companyId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Quote_companyId_localId_key" ON "Quote"("companyId", "localId");

-- CreateIndex
CREATE INDEX "QuoteItem_quoteId_idx" ON "QuoteItem"("quoteId");

-- CreateIndex
CREATE UNIQUE INDEX "CashMovement_companyId_localId_key" ON "CashMovement"("companyId", "localId");

-- CreateIndex
CREATE UNIQUE INDEX "CashSession_companyId_localId_key" ON "CashSession"("companyId", "localId");

-- AddForeignKey
ALTER TABLE "Quote" ADD CONSTRAINT "Quote_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QuoteItem" ADD CONSTRAINT "QuoteItem_quoteId_fkey" FOREIGN KEY ("quoteId") REFERENCES "Quote"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QuoteItem" ADD CONSTRAINT "QuoteItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
