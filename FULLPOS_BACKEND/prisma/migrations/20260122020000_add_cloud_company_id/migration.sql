-- Add cloudCompanyId to Company (used when RNC is not available)
ALTER TABLE "Company" ADD COLUMN "cloudCompanyId" TEXT;

-- Unique constraint for cloudCompanyId (allows multiple NULLs in PostgreSQL)
CREATE UNIQUE INDEX "Company_cloudCompanyId_key" ON "Company"("cloudCompanyId");
