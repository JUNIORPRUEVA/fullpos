-- Add Product.cost (purchase price)
ALTER TABLE "Product" ADD COLUMN "cost" DECIMAL(12, 2) NOT NULL DEFAULT 0;
