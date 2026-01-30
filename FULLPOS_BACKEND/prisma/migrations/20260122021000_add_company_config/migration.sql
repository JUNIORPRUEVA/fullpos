-- Add CompanyConfig table (missing in early init migration)
CREATE TABLE "CompanyConfig" (
    "companyId" INTEGER NOT NULL,
    "logoUrl" TEXT,
    "phone" TEXT,
    "phone2" TEXT,
    "email" TEXT,
    "address" TEXT,
    "city" TEXT,
    "slogan" TEXT,
    "website" TEXT,
    "instagramUrl" TEXT,
    "facebookUrl" TEXT,
    "themeKey" TEXT NOT NULL DEFAULT 'proPos',
    "primaryColor" TEXT,
    "accentColor" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CompanyConfig_pkey" PRIMARY KEY ("companyId")
);

ALTER TABLE "CompanyConfig"
ADD CONSTRAINT "CompanyConfig_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
