-- CreateTable
CREATE TABLE "CloudBackup" (
    "id" TEXT NOT NULL,
    "companyId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sizeBytes" INTEGER NOT NULL,
    "sha256" TEXT NOT NULL,
    "dbVersion" INTEGER NOT NULL,
    "appVersion" TEXT NOT NULL,
    "storagePath" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'SUCCESS',

    CONSTRAINT "CloudBackup_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CloudBackup_companyId_createdAt_idx" ON "CloudBackup"("companyId", "createdAt");

-- AddForeignKey
ALTER TABLE "CloudBackup" ADD CONSTRAINT "CloudBackup_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
