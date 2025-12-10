--NotinoDB

-- 0) Create DB if missing
IF DB_ID('NotinoDB') IS NULL
BEGIN
    CREATE DATABASE NotinoDB;
END
GO

USE NotinoDB;
GO

-- 1) Ensure core tables exist in safe order.
-- If a table exists but lacks a needed column, we'll ALTER it below.

-- Users
IF OBJECT_ID('dbo.Users','U') IS NULL
BEGIN
    CREATE TABLE dbo.Users (
        id INT IDENTITY(1,1) PRIMARY KEY,
        username VARCHAR(100) NOT NULL UNIQUE,
        email VARCHAR(255) NOT NULL UNIQUE,
        wallet_balance DECIMAL(18,4) DEFAULT 0.00,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Users_created_at ON dbo.Users(created_at);
END
GO

-- Suppliers
IF OBJECT_ID('dbo.Suppliers','U') IS NULL
BEGIN
    CREATE TABLE dbo.Suppliers (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        contact_email VARCHAR(255) NULL,
        phone VARCHAR(50) NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Brands
IF OBJECT_ID('dbo.Brands','U') IS NULL
BEGIN
    CREATE TABLE dbo.Brands (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE,
        website VARCHAR(1000) NULL,
        description NVARCHAR(MAX) NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

-- ProductCategories
IF OBJECT_ID('dbo.ProductCategories','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductCategories (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(200) NOT NULL UNIQUE,
        description NVARCHAR(MAX) NULL,
        parent_id INT NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
-- add parent FK only if column exists and FK absent
IF COL_LENGTH('dbo.ProductCategories','parent_id') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ProductCategories_parent' AND parent_object_id = OBJECT_ID('dbo.ProductCategories'))
BEGIN
    ALTER TABLE dbo.ProductCategories
      ADD CONSTRAINT FK_ProductCategories_parent FOREIGN KEY (parent_id) REFERENCES dbo.ProductCategories(id);
END
GO

-- Products: create if missing. If it already exists without supplier_id, we'll add that column later.
IF OBJECT_ID('dbo.Products','U') IS NULL
BEGIN
    CREATE TABLE dbo.Products (
        id INT IDENTITY(1,1) PRIMARY KEY,
        brand_id INT NOT NULL,
        supplier_id INT NULL,
        title NVARCHAR(300) NOT NULL,
        description NVARCHAR(MAX) NULL,
        category_id INT NULL,
        default_image_url VARCHAR(1000) NULL,
        product_type VARCHAR(50) DEFAULT 'other',
        created_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

-- If Products exists but supplier_id column is missing, add it now.
IF OBJECT_ID('dbo.Products','U') IS NOT NULL AND COL_LENGTH('dbo.Products','supplier_id') IS NULL
BEGIN
    PRINT 'Altering dbo.Products: adding supplier_id column...';
    ALTER TABLE dbo.Products ADD supplier_id INT NULL;
END
ELSE
    PRINT 'dbo.Products supplier_id exists or Products missing and will be created above.';
GO

-- Add FK constraints linking Products -> Brands/Suppliers/Categories only if columns exist and FK absent.
IF OBJECT_ID('dbo.Products','U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.Products','brand_id') IS NOT NULL
       AND OBJECT_ID('dbo.Brands','U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Products_Brands' AND parent_object_id = OBJECT_ID('dbo.Products'))
    BEGIN
        ALTER TABLE dbo.Products ADD CONSTRAINT FK_Products_Brands FOREIGN KEY (brand_id) REFERENCES dbo.Brands(id);
    END

    IF COL_LENGTH('dbo.Products','supplier_id') IS NOT NULL
       AND OBJECT_ID('dbo.Suppliers','U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Products_Suppliers' AND parent_object_id = OBJECT_ID('dbo.Products'))
    BEGIN
        
        BEGIN TRY
            ALTER TABLE dbo.Products ADD CONSTRAINT FK_Products_Suppliers FOREIGN KEY (supplier_id) REFERENCES dbo.Suppliers(id);
        END TRY
        BEGIN CATCH
            PRINT 'Warning: could not create FK_Products_Suppliers. Existing data may prevent FK. Error:';
            PRINT ERROR_MESSAGE();
           
        END CATCH
    END

    IF COL_LENGTH('dbo.Products','category_id') IS NOT NULL
       AND OBJECT_ID('dbo.ProductCategories','U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Products_Category' AND parent_object_id = OBJECT_ID('dbo.Products'))
    BEGIN
        ALTER TABLE dbo.Products ADD CONSTRAINT FK_Products_Category FOREIGN KEY (category_id) REFERENCES dbo.ProductCategories(id);
    END
END
GO

-- ProductSKUs (depends on Products)
IF OBJECT_ID('dbo.ProductSKUs','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductSKUs (
        id INT IDENTITY(1,1) PRIMARY KEY,
        product_id INT NOT NULL,
        sku VARCHAR(100) NOT NULL UNIQUE,
        barcode VARCHAR(100) NULL,
        size VARCHAR(100) NULL,
        color VARCHAR(100) NULL,
        price DECIMAL(18,4) NOT NULL,
        msrp DECIMAL(18,4) NULL,
        weight_grams DECIMAL(10,2) NULL,
        available BIT DEFAULT 1,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_ProductSKUs_product_id ON dbo.ProductSKUs(product_id);
    ALTER TABLE dbo.ProductSKUs ADD CONSTRAINT FK_ProductSKUs_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(id);
END
GO

-- Warehouses
IF OBJECT_ID('dbo.Warehouses','U') IS NULL
BEGIN
    CREATE TABLE dbo.Warehouses (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        location NVARCHAR(500) NULL,
        phone VARCHAR(50) NULL,
        manager VARCHAR(255) NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Inventory (depends on ProductSKUs & Warehouses)
IF OBJECT_ID('dbo.Inventory','U') IS NULL
BEGIN
    CREATE TABLE dbo.Inventory (
        id INT IDENTITY(1,1) PRIMARY KEY,
        sku_id INT NOT NULL,
        warehouse_id INT NOT NULL,
        quantity INT NOT NULL DEFAULT 0,
        min_level INT DEFAULT 0,
        updated_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE UNIQUE INDEX UX_Inventory_sku_warehouse ON dbo.Inventory(sku_id, warehouse_id);
    CREATE INDEX IX_Inventory_sku_id ON dbo.Inventory(sku_id);
    CREATE INDEX IX_Inventory_warehouse_id ON dbo.Inventory(warehouse_id);
    ALTER TABLE dbo.Inventory ADD CONSTRAINT FK_Inventory_SKU FOREIGN KEY (sku_id) REFERENCES dbo.ProductSKUs(id);
    ALTER TABLE dbo.Inventory ADD CONSTRAINT FK_Inventory_Warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.Warehouses(id);
END
GO

-- Orders
IF OBJECT_ID('dbo.Orders','U') IS NULL
BEGIN
    CREATE TABLE dbo.Orders (
        id INT IDENTITY(1,1) PRIMARY KEY,
        user_id INT NOT NULL,
        order_number VARCHAR(100) NOT NULL UNIQUE,
        status VARCHAR(50) DEFAULT 'pending',
        subtotal DECIMAL(18,4) NOT NULL,
        shipping DECIMAL(18,4) DEFAULT 0.00,
        tax DECIMAL(18,4) DEFAULT 0.00,
        total DECIMAL(18,4) NOT NULL,
        placed_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        shipping_address NVARCHAR(1000) NULL,
        billing_address NVARCHAR(1000) NULL
    );
    CREATE INDEX IX_Orders_user_id ON dbo.Orders(user_id);
    CREATE INDEX IX_Orders_status ON dbo.Orders(status);
    ALTER TABLE dbo.Orders ADD CONSTRAINT FK_Orders_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id);
END
GO

-- OrderItems
IF OBJECT_ID('dbo.OrderItems','U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderItems (
        id INT IDENTITY(1,1) PRIMARY KEY,
        order_id INT NOT NULL,
        sku_id INT NOT NULL,
        quantity INT NOT NULL,
        unit_price DECIMAL(18,4) NOT NULL,
        total_price DECIMAL(18,4) NOT NULL
    );
    CREATE INDEX IX_OrderItems_order_id ON dbo.OrderItems(order_id);
    CREATE INDEX IX_OrderItems_sku_id ON dbo.OrderItems(sku_id);
    ALTER TABLE dbo.OrderItems ADD CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(id);
    ALTER TABLE dbo.OrderItems ADD CONSTRAINT FK_OrderItems_SKU FOREIGN KEY (sku_id) REFERENCES dbo.ProductSKUs(id);
END
GO

-- Shipments
IF OBJECT_ID('dbo.Shipments','U') IS NULL
BEGIN
    CREATE TABLE dbo.Shipments (
        id INT IDENTITY(1,1) PRIMARY KEY,
        order_id INT NOT NULL,
        carrier VARCHAR(255) NULL,
        tracking_number VARCHAR(255) NULL,
        shipped_at DATETIME2 NULL,
        estimated_delivery DATETIME2 NULL,
        delivered_at DATETIME2 NULL,
        status VARCHAR(50) DEFAULT 'label_created'
    );
    CREATE INDEX IX_Shipments_order_id ON dbo.Shipments(order_id);
    ALTER TABLE dbo.Shipments ADD CONSTRAINT FK_Shipments_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(id);
END
GO

-- Payments
IF OBJECT_ID('dbo.Payments','U') IS NULL
BEGIN
    CREATE TABLE dbo.Payments (
        id INT IDENTITY(1,1) PRIMARY KEY,
        order_id INT NOT NULL,
        user_id INT NOT NULL,
        amount DECIMAL(18,4) NOT NULL,
        method VARCHAR(50) DEFAULT 'card',
        transaction_ref VARCHAR(255) NULL,
        status VARCHAR(50) DEFAULT 'pending',
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Payments_order_id ON dbo.Payments(order_id);
    CREATE INDEX IX_Payments_user_id ON dbo.Payments(user_id);
    ALTER TABLE dbo.Payments ADD CONSTRAINT FK_Payments_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(id);
    ALTER TABLE dbo.Payments ADD CONSTRAINT FK_Payments_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id);
END
GO

-- Returns
IF OBJECT_ID('dbo.Returns','U') IS NULL
BEGIN
    CREATE TABLE dbo.Returns (
        id INT IDENTITY(1,1) PRIMARY KEY,
        order_item_id INT NOT NULL,
        reason NVARCHAR(MAX) NULL,
        requested_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        status VARCHAR(50) DEFAULT 'requested',
        handled_by VARCHAR(150) NULL,
        processed_at DATETIME2 NULL
    );
    CREATE INDEX IX_Returns_order_item_id ON dbo.Returns(order_item_id);
    ALTER TABLE dbo.Returns ADD CONSTRAINT FK_Returns_OrderItems FOREIGN KEY (order_item_id) REFERENCES dbo.OrderItems(id);
END
GO

-- Ingredients
IF OBJECT_ID('dbo.Ingredients','U') IS NULL
BEGIN
    CREATE TABLE dbo.Ingredients (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE
    );
END
GO

-- ProductIngredients (many-to-many) using pct
IF OBJECT_ID('dbo.ProductIngredients','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductIngredients (
        product_id INT NOT NULL,
        ingredient_id INT NOT NULL,
        pct DECIMAL(6,3) NULL,
        PRIMARY KEY (product_id, ingredient_id)
    );
    ALTER TABLE dbo.ProductIngredients ADD CONSTRAINT FK_ProductIngredients_Product FOREIGN KEY (product_id) REFERENCES dbo.Products(id);
    ALTER TABLE dbo.ProductIngredients ADD CONSTRAINT FK_ProductIngredients_Ingredient FOREIGN KEY (ingredient_id) REFERENCES dbo.Ingredients(id);
END
GO

-- Certifications
IF OBJECT_ID('dbo.Certifications','U') IS NULL
BEGIN
    CREATE TABLE dbo.Certifications (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        issuer VARCHAR(255) NULL,
        description NVARCHAR(MAX) NULL
    );
END
GO

-- ProductCertifications
IF OBJECT_ID('dbo.ProductCertifications','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductCertifications (
        product_id INT NOT NULL,
        certification_id INT NOT NULL,
        certified_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (product_id, certification_id)
    );
    ALTER TABLE dbo.ProductCertifications ADD CONSTRAINT FK_ProductCertifications_Product FOREIGN KEY (product_id) REFERENCES dbo.Products(id);
    ALTER TABLE dbo.ProductCertifications ADD CONSTRAINT FK_ProductCertifications_Certification FOREIGN KEY (certification_id) REFERENCES dbo.Certifications(id);
END
GO

-- ProductAttributes
IF OBJECT_ID('dbo.ProductAttributes','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductAttributes (
        id INT IDENTITY(1,1) PRIMARY KEY,
        product_id INT NOT NULL,
        attr_key VARCHAR(150) NOT NULL,
        attr_value VARCHAR(1000) NULL
    );
    CREATE INDEX IX_ProductAttributes_product_id ON dbo.ProductAttributes(product_id);
    ALTER TABLE dbo.ProductAttributes ADD CONSTRAINT FK_ProductAttributes_Product FOREIGN KEY (product_id) REFERENCES dbo.Products(id);
END
GO

-- ProductReviews
IF OBJECT_ID('dbo.ProductReviews','U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductReviews (
        id INT IDENTITY(1,1) PRIMARY KEY,
        product_id INT NOT NULL,
        user_id INT NOT NULL,
        rating TINYINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
        title VARCHAR(250) NULL,
        body NVARCHAR(MAX) NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        useful_count INT DEFAULT 0,
        verified_purchase BIT DEFAULT 0
    );
    CREATE INDEX IX_ProductReviews_product_id ON dbo.ProductReviews(product_id);
    CREATE INDEX IX_ProductReviews_user_id ON dbo.ProductReviews(user_id);
    ALTER TABLE dbo.ProductReviews ADD CONSTRAINT FK_ProductReviews_Product FOREIGN KEY (product_id) REFERENCES dbo.Products(id);
    ALTER TABLE dbo.ProductReviews ADD CONSTRAINT FK_ProductReviews_User FOREIGN KEY (user_id) REFERENCES dbo.Users(id);
END
GO

-- Promotions
IF OBJECT_ID('dbo.Promotions','U') IS NULL
BEGIN
    CREATE TABLE dbo.Promotions (
        id INT IDENTITY(1,1) PRIMARY KEY,
        code VARCHAR(100) UNIQUE,
        description VARCHAR(500) NULL,
        discount_type VARCHAR(20) NOT NULL DEFAULT ('pct'),
        discount_value DECIMAL(18,4) NULL,
        starts_at DATETIME2 NULL,
        ends_at DATETIME2 NULL,
        active BIT DEFAULT (1),
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Bundles & BundleItems
IF OBJECT_ID('dbo.Bundles','U') IS NULL
BEGIN
    CREATE TABLE dbo.Bundles (
        id INT IDENTITY(1,1) PRIMARY KEY,
        title NVARCHAR(300) NOT NULL,
        description NVARCHAR(MAX) NULL,
        bundle_price DECIMAL(18,4) NOT NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
END
GO

IF OBJECT_ID('dbo.BundleItems','U') IS NULL
BEGIN
    CREATE TABLE dbo.BundleItems (
        bundle_id INT NOT NULL,
        sku_id INT NOT NULL,
        quantity INT NOT NULL DEFAULT 1,
        PRIMARY KEY (bundle_id, sku_id)
    );
    ALTER TABLE dbo.BundleItems ADD CONSTRAINT FK_BundleItems_Bundles FOREIGN KEY (bundle_id) REFERENCES dbo.Bundles(id);
    ALTER TABLE dbo.BundleItems ADD CONSTRAINT FK_BundleItems_SKU FOREIGN KEY (sku_id) REFERENCES dbo.ProductSKUs(id);
END
GO

-- Samples
IF OBJECT_ID('dbo.Samples','U') IS NULL
BEGIN
    CREATE TABLE dbo.Samples (
        id INT IDENTITY(1,1) PRIMARY KEY,
        sku_id INT NOT NULL,
        sample_qty INT DEFAULT 1,
        included_with_order BIT DEFAULT 0
    );
    ALTER TABLE dbo.Samples ADD CONSTRAINT FK_Samples_SKU FOREIGN KEY (sku_id) REFERENCES dbo.ProductSKUs(id);
END
GO

-- LoyaltyAccounts
IF OBJECT_ID('dbo.LoyaltyAccounts','U') IS NULL
BEGIN
    CREATE TABLE dbo.LoyaltyAccounts (
        id INT IDENTITY(1,1) PRIMARY KEY,
        user_id INT NOT NULL,
        points INT DEFAULT 0,
        tier VARCHAR(50) DEFAULT 'bronze',
        updated_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Loyalty_user_id ON dbo.LoyaltyAccounts(user_id);
    ALTER TABLE dbo.LoyaltyAccounts ADD CONSTRAINT FK_Loyalty_User FOREIGN KEY (user_id) REFERENCES dbo.Users(id);
END
GO

-- BillingRecords
IF OBJECT_ID('dbo.BillingRecords','U') IS NULL
BEGIN
    CREATE TABLE dbo.BillingRecords (
        id INT IDENTITY(1,1) PRIMARY KEY,
        user_id INT NOT NULL,
        order_id INT NULL,
        amount DECIMAL(18,4) NOT NULL,
        currency CHAR(3) DEFAULT 'USD',
        created_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        description NVARCHAR(500) NULL
    );
    CREATE INDEX IX_BillingRecords_user_id ON dbo.BillingRecords(user_id);
    ALTER TABLE dbo.BillingRecords ADD CONSTRAINT FK_BillingRecords_User FOREIGN KEY (user_id) REFERENCES dbo.Users(id);
    -- add FK to Orders if exists
    IF OBJECT_ID('dbo.Orders','U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_BillingRecords_Order' AND parent_object_id = OBJECT_ID('dbo.BillingRecords'))
    BEGIN
        ALTER TABLE dbo.BillingRecords ADD CONSTRAINT FK_BillingRecords_Order FOREIGN KEY (order_id) REFERENCES dbo.Orders(id);
    END
END
GO

-- ChangeLogs
IF OBJECT_ID('dbo.ChangeLogs','U') IS NULL
BEGIN
    CREATE TABLE dbo.ChangeLogs (
        id INT IDENTITY(1,1) PRIMARY KEY,
        table_name VARCHAR(100) NOT NULL,
        record_id INT NULL,
        changed_by VARCHAR(150) NULL,
        change_type VARCHAR(20) NOT NULL,
        old_value NVARCHAR(MAX) NULL,
        new_value NVARCHAR(MAX) NULL,
        change_date DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_ChangeLogs_table_name ON dbo.ChangeLogs(table_name);
    CREATE INDEX IX_ChangeLogs_record_id ON dbo.ChangeLogs(record_id);
END
GO

-- 2) Insert sample data only if missing (defensive single-statements)

-- Users
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE email = 'alice@example.com')
    INSERT INTO dbo.Users (username, email, wallet_balance) VALUES ('alice','alice@example.com', 100.00);
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE email = 'bob@example.com')
    INSERT INTO dbo.Users (username, email, wallet_balance) VALUES ('bob','bob@example.com', 25.00);
GO

-- Suppliers (single + idempotent multi-row insert)
IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE name = 'Notino Supplier A')
    INSERT INTO dbo.Suppliers (name, contact_email, phone) VALUES ('Notino Supplier A','supplyA@example.com','+37012345678');
GO

-- Idempotent multi-row insert (adds two suppliers only if they don't already exist)
INSERT INTO dbo.Suppliers (name, contact_email, phone)
SELECT v.name, v.contact_email, v.phone
FROM (VALUES
  ('Notino Supplier B','supplyB@example.com','+37011111111'),
  ('Notino Supplier C','supplyC@example.com','+37022222222')
) AS v(name, contact_email, phone)
WHERE NOT EXISTS (
  SELECT 1 FROM dbo.Suppliers s WHERE s.name = v.name
);
GO

-- Brands
IF NOT EXISTS (SELECT 1 FROM dbo.Brands WHERE name = 'Lumiere Cosmetics')
    INSERT INTO dbo.Brands (name, website, description) VALUES ('Lumiere Cosmetics','https://lumiere.example.com','Premium skincare and fragrance');
IF NOT EXISTS (SELECT 1 FROM dbo.Brands WHERE name = 'Bloom Beauty')
    INSERT INTO dbo.Brands (name, website, description) VALUES ('Bloom Beauty','https://bloom.example.com','Makeup and color cosmetics');
GO

-- Categories
IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategories WHERE name = 'Fragrance')
    INSERT INTO dbo.ProductCategories (name, description) VALUES ('Fragrance','Perfumes and colognes');
IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategories WHERE name = 'Skincare')
    INSERT INTO dbo.ProductCategories (name, description) VALUES ('Skincare','Cleansers, moisturizers, serums');
IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategories WHERE name = 'Makeup')
    INSERT INTO dbo.ProductCategories (name, description) VALUES ('Makeup','Color cosmetics');
GO

-- Products (use sub-selects to set brand_id/supplier_id)
IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum')
BEGIN
    INSERT INTO dbo.Products (brand_id, supplier_id, title, description, category_id, default_image_url, product_type)
    VALUES (
        (SELECT TOP 1 id FROM dbo.Brands WHERE name='Lumiere Cosmetics'),
        (SELECT TOP 1 id FROM dbo.Suppliers WHERE name='Notino Supplier A'),
        N'Lumiere Rose Eau de Parfum',
        N'Floral woody perfume 50ml',
        (SELECT TOP 1 id FROM dbo.ProductCategories WHERE name='Fragrance'),
        'https://cdn.example.com/lumiere-rose.png',
        'perfume'
    );
END

IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick')
BEGIN
    INSERT INTO dbo.Products (brand_id, supplier_id, title, description, category_id, default_image_url, product_type)
    VALUES (
        (SELECT TOP 1 id FROM dbo.Brands WHERE name='Bloom Beauty'),
        (SELECT TOP 1 id FROM dbo.Suppliers WHERE name='Notino Supplier A'),
        N'Bloom Velvet Matte Lipstick',
        N'Long-wear matte lipstick 4g',
        (SELECT TOP 1 id FROM dbo.ProductCategories WHERE name='Makeup'),
        'https://cdn.example.com/bloom-lipstick.png',
        'makeup'
    );
END
GO

-- SKUs
IF NOT EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50')
    INSERT INTO dbo.ProductSKUs (product_id, sku, barcode, size, price, msrp, available)
    VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum'), 'LUM-ROSE-50', '1234567890123', '50ml', 45.00, 60.00, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED')
    INSERT INTO dbo.ProductSKUs (product_id, sku, barcode, size, price, msrp, available)
    VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick'), 'BLM-LIP-RED', '9876543210987', '4g', 12.00, 15.00, 1);
GO

-- Warehouses
IF NOT EXISTS (SELECT 1 FROM dbo.Warehouses WHERE name = 'Vilnius Central Warehouse')
    INSERT INTO dbo.Warehouses (name, location) VALUES ('Vilnius Central Warehouse','Vilnius, LT');
IF NOT EXISTS (SELECT 1 FROM dbo.Warehouses WHERE name = 'Riga Regional Warehouse')
    INSERT INTO dbo.Warehouses (name, location) VALUES ('Riga Regional Warehouse','Riga, LV');
GO

-- Inventory (only if SKUs & warehouses exist)
IF EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50') AND EXISTS (SELECT 1 FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE sku_id = (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50') AND warehouse_id = (SELECT TOP 1 id FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse'))
        INSERT INTO dbo.Inventory (sku_id, warehouse_id, quantity, min_level)
        VALUES ((SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50'), (SELECT TOP 1 id FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse'), 100, 10);
END

IF EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50') AND EXISTS (SELECT 1 FROM dbo.Warehouses WHERE name='Riga Regional Warehouse')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE sku_id = (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50') AND warehouse_id = (SELECT TOP 1 id FROM dbo.Warehouses WHERE name = 'Riga Regional Warehouse'))
        INSERT INTO dbo.Inventory (sku_id, warehouse_id, quantity, min_level)
        VALUES ((SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='LUM-ROSE-50'), (SELECT TOP 1 id FROM dbo.Warehouses WHERE name='Riga Regional Warehouse'), 50, 5);
END

IF EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED') AND EXISTS (SELECT 1 FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE sku_id = (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED') AND warehouse_id = (SELECT TOP 1 id FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse'))
        INSERT INTO dbo.Inventory (sku_id, warehouse_id, quantity, min_level)
        VALUES ((SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'), (SELECT TOP 1 id FROM dbo.Warehouses WHERE name='Vilnius Central Warehouse'), 200, 20);
END
GO

-- Promotions (single insert + idempotent MERGE multi-row seed)
IF NOT EXISTS (SELECT 1 FROM dbo.Promotions WHERE code = 'WELCOME10')
    INSERT INTO dbo.Promotions (code, description, discount_type, discount_value, starts_at, ends_at, active)
    VALUES ('WELCOME10','10% off first order','pct', 10.00, DATEADD(day,-30, SYSUTCDATETIME()), DATEADD(day,30,SYSUTCDATETIME()), 1);
GO

-- Idempotent multi-row insert using MERGE (good for seeding multiple rows safely)
MERGE INTO dbo.Promotions AS target
USING (VALUES
  ('SUMMER20','20% summer sale','pct',20.0),
  ('FREESHIP','Free shipping over $50','fixed',0.0)
) AS source(code,description,discount_type,discount_value)
ON target.code = source.code
WHEN NOT MATCHED THEN
  INSERT (code, description, discount_type, discount_value, starts_at, ends_at, active)
  VALUES (source.code, source.description, source.discount_type, source.discount_value, SYSUTCDATETIME(), DATEADD(DAY,30,SYSUTCDATETIME()), 1);
GO

-- Bundles & BundleItems
IF NOT EXISTS (SELECT 1 FROM dbo.Bundles WHERE title = N'Skincare Starter Pack')
    INSERT INTO dbo.Bundles (title, description, bundle_price) VALUES (N'Skincare Starter Pack', N'Cleanser + Serum sample pack', 29.99);
IF EXISTS (SELECT 1 FROM dbo.Bundles WHERE title = N'Skincare Starter Pack' AND EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.BundleItems WHERE bundle_id = (SELECT TOP 1 id FROM dbo.Bundles WHERE title = N'Skincare Starter Pack') AND sku_id = (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'))
        INSERT INTO dbo.BundleItems (bundle_id, sku_id, quantity)
        VALUES ((SELECT TOP 1 id FROM dbo.Bundles WHERE title = N'Skincare Starter Pack'), (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'), 1);
END
GO

-- Samples
IF EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Samples WHERE sku_id = (SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'))
        INSERT INTO dbo.Samples (sku_id, sample_qty, included_with_order)
        VALUES ((SELECT TOP 1 id FROM dbo.ProductSKUs WHERE sku='BLM-LIP-RED'), 1, 1);
END
GO

-- Ingredients & ProductIngredients
IF NOT EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name = 'Aqua') INSERT INTO dbo.Ingredients (name) VALUES ('Aqua');
IF NOT EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name = 'Glycerin') INSERT INTO dbo.Ingredients (name) VALUES ('Glycerin');
IF NOT EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name = 'Fragrance') INSERT INTO dbo.Ingredients (name) VALUES ('Fragrance');
GO

IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name='Aqua')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductIngredients WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND ingredient_id = (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Aqua'))
        INSERT INTO dbo.ProductIngredients (product_id, ingredient_id, pct)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum'), (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Aqua'), 60.0);
END
IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name='Fragrance')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductIngredients WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND ingredient_id = (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Fragrance'))
        INSERT INTO dbo.ProductIngredients (product_id, ingredient_id, pct)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum'), (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Fragrance'), 1.0);
END
IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick') AND EXISTS (SELECT 1 FROM dbo.Ingredients WHERE name='Glycerin')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductIngredients WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick') AND ingredient_id = (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Glycerin'))
        INSERT INTO dbo.ProductIngredients (product_id, ingredient_id, pct)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick'), (SELECT TOP 1 id FROM dbo.Ingredients WHERE name = 'Glycerin'), 5.0);
END
GO

-- Certifications & ProductCertifications
IF NOT EXISTS (SELECT 1 FROM dbo.Certifications WHERE name = 'Cruelty-Free') INSERT INTO dbo.Certifications (name, issuer, description) VALUES ('Cruelty-Free','PETA','Not tested on animals');
IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND EXISTS (SELECT 1 FROM dbo.Certifications WHERE name='Cruelty-Free')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductCertifications WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND certification_id = (SELECT TOP 1 id FROM dbo.Certifications WHERE name = 'Cruelty-Free'))
        INSERT INTO dbo.ProductCertifications (product_id, certification_id)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum'), (SELECT TOP 1 id FROM dbo.Certifications WHERE name = 'Cruelty-Free'));
END
GO

-- Reviews
IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND EXISTS (SELECT 1 FROM dbo.Users WHERE email='alice@example.com')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductReviews WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum') AND user_id = (SELECT TOP 1 id FROM dbo.Users WHERE email='alice@example.com'))
        INSERT INTO dbo.ProductReviews (product_id, user_id, rating, title, body, verified_purchase)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Lumiere Rose Eau de Parfum'), (SELECT TOP 1 id FROM dbo.Users WHERE email='alice@example.com'), 5, 'Lovely scent', 'Long-lasting and elegant.', 1);
END

IF EXISTS (SELECT 1 FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick') AND EXISTS (SELECT 1 FROM dbo.Users WHERE email='bob@example.com')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductReviews WHERE product_id = (SELECT TOP 1 id FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick') AND user_id = (SELECT TOP 1 id FROM dbo.Users WHERE email='bob@example.com'))
        INSERT INTO dbo.ProductReviews (product_id, user_id, rating, title, body, verified_purchase)
        VALUES ((SELECT TOP 1 id FROM dbo.Products WHERE title = N'Bloom Velvet Matte Lipstick'), (SELECT TOP 1 id FROM dbo.Users WHERE email='bob@example.com'), 4, 'Nice color', 'Matte finish, good wear.', 1);
END
GO

-- 3) CREATE OR ALTER procedures / function / triggers / view (after DDL stable)

CREATE OR ALTER PROCEDURE dbo.CreateProduct
    @brand_id INT,
    @supplier_id INT = NULL,
    @title NVARCHAR(300),
    @description NVARCHAR(MAX),
    @product_type VARCHAR(50),
    @default_image_url VARCHAR(1000),
    @category_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO dbo.Products (brand_id, supplier_id, title, description, product_type, default_image_url, category_id)
            VALUES (@brand_id, @supplier_id, @title, @description, @product_type, @default_image_url, @category_id);
            DECLARE @new_id INT = SCOPE_IDENTITY();
            INSERT INTO dbo.ChangeLogs (table_name, record_id, changed_by, change_type, old_value, new_value)
            VALUES ('Products', @new_id, CONCAT('brand:', @brand_id), 'INSERT', NULL, CONCAT('title=', @title));
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.AdjustInventory
    @p_sku_id INT,
    @p_warehouse_id INT,
    @p_delta INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
            IF NOT EXISTS (SELECT 1 FROM dbo.Inventory WHERE sku_id = @p_sku_id AND warehouse_id = @p_warehouse_id)
            BEGIN
                INSERT INTO dbo.Inventory (sku_id, warehouse_id, quantity, min_level)
                VALUES (@p_sku_id, @p_warehouse_id, CASE WHEN @p_delta < 0 THEN 0 ELSE @p_delta END, 0);
            END
            ELSE
            BEGIN
                UPDATE dbo.Inventory
                SET quantity = CASE WHEN quantity + @p_delta < 0 THEN 0 ELSE quantity + @p_delta END,
                    updated_at = SYSUTCDATETIME()
                WHERE sku_id = @p_sku_id AND warehouse_id = @p_warehouse_id;
            END
            INSERT INTO dbo.ChangeLogs (table_name, record_id, changed_by, change_type, old_value, new_value)
            VALUES ('Inventory', @p_sku_id, 'system', 'UPDATE', NULL, CONCAT('warehouse=', @p_warehouse_id, '; delta=', @p_delta));
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.PlaceOrder
    @p_user_id INT,
    @p_order_number VARCHAR(100),
    @p_subtotal DECIMAL(18,4),
    @p_shipping DECIMAL(18,4),
    @p_tax DECIMAL(18,4),
    @p_total DECIMAL(18,4)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO dbo.Orders (user_id, order_number, subtotal, shipping, tax, total, status)
            VALUES (@p_user_id, @p_order_number, @p_subtotal, @p_shipping, @p_tax, @p_total, 'pending');
            DECLARE @v_order_id INT = SCOPE_IDENTITY();
            INSERT INTO dbo.BillingRecords (user_id, order_id, amount, currency, description)
            VALUES (@p_user_id, @v_order_id, @p_total, 'USD', CONCAT('Order ', @p_order_number));
            INSERT INTO dbo.ChangeLogs (table_name, record_id, changed_by, change_type, old_value, new_value)
            VALUES ('Orders', @v_order_id, CONCAT('user:', @p_user_id), 'INSERT', NULL, CONCAT('order_number=', @p_order_number, '; total=', @p_total));
        COMMIT TRAN;
        SELECT @v_order_id AS order_id;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcSkuInventoryValue(@sku_id INT)
RETURNS DECIMAL(18,4)
AS
BEGIN
    DECLARE @value DECIMAL(18,4);
    SELECT @value = ISNULL(SUM(i.quantity * ps.price),0)
    FROM dbo.Inventory i
    JOIN dbo.ProductSKUs ps ON ps.id = i.sku_id
    WHERE i.sku_id = @sku_id;
    RETURN @value;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_payments_after_update
ON dbo.Payments
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON i.id = d.id WHERE i.status = 'completed' AND ISNULL(d.status,'') <> 'completed')
    BEGIN
        UPDATE o
        SET o.status = 'paid', o.updated_at = SYSUTCDATETIME()
        FROM dbo.Orders o
        JOIN inserted i ON i.order_id = o.id
        JOIN deleted d ON d.id = i.id
        WHERE i.status = 'completed' AND ISNULL(d.status,'') <> 'completed';
        INSERT INTO dbo.ChangeLogs (table_name, record_id, changed_by, change_type, old_value, new_value)
        SELECT 'Orders', o.id, 'system', 'UPDATE', d.status, i.status
        FROM dbo.Orders o
        JOIN inserted i ON i.order_id = o.id
        JOIN deleted d ON d.id = i.id
        WHERE i.status = 'completed' AND ISNULL(d.status,'') <> 'completed';
    END
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_orderitems_after_insert
ON dbo.OrderItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.ChangeLogs (table_name, record_id, changed_by, change_type, old_value, new_value)
    SELECT 'OrderItems', i.id, 'system', 'INSERT', NULL, CONCAT('sku=', i.sku_id, '; qty=', i.quantity)
    FROM inserted i;
END;
GO

CREATE OR ALTER VIEW dbo.ProductsInventorySummary AS
SELECT
    p.id AS product_id,
    p.title,
    ps.id AS sku_id,
    ps.sku,
    ps.price,
    ISNULL(SUM(i.quantity),0) AS total_stock,
    p.product_type
FROM dbo.Products p
JOIN dbo.ProductSKUs ps ON ps.product_id = p.id
LEFT JOIN dbo.Inventory i ON i.sku_id = ps.id
GROUP BY p.id, p.title, ps.id, ps.sku, ps.price, p.product_type;
GO

-- 4) Optional safe DML examples & required SELECTS (you can execute interactively)

-- Safe single update example
IF EXISTS (SELECT 1 FROM dbo.ProductSKUs WHERE sku = 'BLM-LIP-RED')
    UPDATE dbo.ProductSKUs SET price = ROUND(price * 0.95, 2) WHERE sku = 'BLM-LIP-RED';
GO

-- Delete expired promotions safely
DELETE FROM dbo.Promotions WHERE ends_at IS NOT NULL AND ends_at < SYSUTCDATETIME();
GO

-- Aggregates / pagination examples
-- Revenue per Brand
SELECT
    b.id AS brand_id,
    b.name AS brand_name,
    COUNT(DISTINCT o.id) AS orders_count,
    SUM(oi.total_price) AS total_revenue,
    ROUND(AVG(oi.unit_price),2) AS avg_unit_price
FROM dbo.OrderItems oi
JOIN dbo.Orders o ON o.id = oi.order_id
JOIN dbo.ProductSKUs ps ON ps.id = oi.sku_id
JOIN dbo.Products p ON p.id = ps.product_id
JOIN dbo.Brands b ON b.id = p.brand_id
WHERE o.status IN ('paid','processing','shipped','delivered')
GROUP BY b.id, b.name
ORDER BY total_revenue DESC;
GO

-- Paginated top-rated products (example)
DECLARE @page INT = 1, @pageSize INT = 10;
WITH ProductRatings AS (
    SELECT p.id AS product_id, p.title, AVG(CONVERT(DECIMAL(10,2), pr.rating)) AS avg_rating, COUNT(pr.id) AS reviews_count
    FROM dbo.ProductReviews pr JOIN dbo.Products p ON p.id = pr.product_id
    GROUP BY p.id, p.title
)
SELECT product_id, title, ROUND(avg_rating,2) AS avg_rating, reviews_count
FROM ProductRatings
ORDER BY avg_rating DESC, reviews_count DESC
OFFSET (@page - 1) * @pageSize ROWS FETCH NEXT @pageSize ROWS ONLY;
GO

-- Inventory value per warehouse
SELECT w.id AS warehouse_id, w.name AS warehouse_name, SUM(i.quantity * ps.price) AS inventory_value, SUM(i.quantity) AS total_units
FROM dbo.Inventory i JOIN dbo.Warehouses w ON w.id = i.warehouse_id JOIN dbo.ProductSKUs ps ON ps.id = i.sku_id
GROUP BY w.id, w.name
ORDER BY inventory_value DESC;
GO

-- RIGHT JOIN demonstration: show all SKUs and inventory quantity (if any)
SELECT
  ps.sku,
  ps.size,
  ISNULL(i.quantity, 0) AS quantity,
  w.name AS warehouse_name
FROM dbo.Inventory i
RIGHT JOIN dbo.ProductSKUs ps ON ps.id = i.sku_id
LEFT JOIN dbo.Warehouses w ON w.id = i.warehouse_id
WHERE ps.sku LIKE 'LUM-%'
ORDER BY ps.sku;
GO

IF OBJECT_ID('dbo.ChangeLogs_Temp','U') IS NOT NULL
    DROP TABLE dbo.ChangeLogs_Temp;
GO

CREATE TABLE dbo.ChangeLogs_Temp (
    id INT IDENTITY(1,1) PRIMARY KEY,
    table_name VARCHAR(100),
    record_id INT,
    change_date DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

INSERT INTO dbo.ChangeLogs_Temp (table_name, record_id) VALUES ('Orders', 1), ('Products', 2);
GO

-- Now safe to truncate this temp/demo table
TRUNCATE TABLE dbo.ChangeLogs_Temp;
GO

GO

-- 5) Manual transaction example (TRY/CATCH)
BEGIN TRY
    BEGIN TRAN;

        -- create order
        INSERT INTO dbo.Orders (user_id, order_number, subtotal, shipping, tax, total, status)
        VALUES ((SELECT TOP 1 id FROM dbo.Users), 'ORD-EX-0001', 45.00, 5.00, 2.75, 52.75, 'pending');

        DECLARE @order_id INT;
        SET @order_id = SCOPE_IDENTITY();

        -- add order item
        INSERT INTO dbo.OrderItems (order_id, sku_id, quantity, unit_price, total_price)
        VALUES (@order_id, (SELECT TOP 1 id FROM dbo.ProductSKUs), 1, 45.00, 45.00);

        -- fetch the first sku and warehouse into variables
        DECLARE @first_sku_id INT;
        DECLARE @first_warehouse_id INT;

        SELECT TOP 1 @first_sku_id = id FROM dbo.ProductSKUs;
        SELECT TOP 1 @first_warehouse_id = id FROM dbo.Warehouses;

        -- Call proc using variables (no inline SELECT inside parameter list)
        IF @first_sku_id IS NOT NULL AND @first_warehouse_id IS NOT NULL
        BEGIN
            EXEC dbo.AdjustInventory @p_sku_id = @first_sku_id, @p_warehouse_id = @first_warehouse_id, @p_delta = -1;
        END
        ELSE
        BEGIN
            PRINT 'Warning: missing sku or warehouse; skipped AdjustInventory.';
        END

        -- creating payment and we mark it completed
        INSERT INTO dbo.Payments (order_id, user_id, amount, method, status)
        VALUES (@order_id, (SELECT TOP 1 id FROM dbo.Users), 52.75, 'card', 'completed');

    COMMIT TRAN;
END TRY
BEGIN CATCH
    ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg, ERROR_LINE() AS ErrLine;
END CATCH;
GO

-- 6) Small smoke tests (quick demo checks)
PRINT '=== SMOKE TESTS ===';

-- 1) Select top SKUs
SELECT TOP 10 * FROM dbo.ProductSKUs;

-- 2) Call function to compute inventory value for first SKU
DECLARE @first_sku INT = (SELECT TOP 1 id FROM dbo.ProductSKUs);
IF @first_sku IS NOT NULL
    SELECT dbo.fn_CalcSkuInventoryValue(@first_sku) AS inventory_value_for_first_sku;

-- 3) Run the ProductsInventorySummary view
SELECT TOP 20 * FROM dbo.ProductsInventorySummary ORDER BY total_stock DESC;

-- 4) Run paginated top-rated products (page 1)
DECLARE @demoPage INT = 1, @demoPageSize INT = 5;
WITH DemoPR AS (
    SELECT p.id AS product_id, p.title, AVG(CONVERT(DECIMAL(10,2), pr.rating)) AS avg_rating, COUNT(pr.id) AS reviews_count
    FROM dbo.ProductReviews pr JOIN dbo.Products p ON p.id = pr.product_id
    GROUP BY p.id, p.title
)
SELECT product_id, title, ROUND(avg_rating,2) AS avg_rating, reviews_count
FROM DemoPR
ORDER BY avg_rating DESC, reviews_count DESC
OFFSET (@demoPage - 1) * @demoPageSize ROWS FETCH NEXT @demoPageSize ROWS ONLY;
GO


