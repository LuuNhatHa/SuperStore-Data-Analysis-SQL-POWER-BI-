-- Cleaning data in SQL queries
SELECT * FROM Superstore.dbo.Superstore
-- Standard date format
SELECT [Order Date], [Ship Date], CONVERT(Date, [Order Date]) AS Order_Date,
    CONVERT(Date, [Ship Date]) AS Ship_Date FROM Superstore.dbo.Superstore

ALTER TABLE Superstore
ADD Order_Date Date;
ALTER TABLE Superstore
ADD Ship_Date Date;

UPDATE Superstore
SET Order_Date = CONVERT(Date, [Order Date]);

UPDATE Superstore
SET Ship_Date = CONVERT(Date, [Ship Date]);

ALTER TABLE Superstore
DROP COLUMN [Order Date], [Ship Date];
-- Remove Duplicate
WITH CTE AS (
    SELECT [Order ID],
           ROW_NUMBER() OVER (
               PARTITION BY [Ship Mode], [Customer Name], [Segment], [Country], [City], [State], 
                            [Region], [Product Name], [Sales], [Quantity], [Discount], [Profit]
               ORDER BY [Order ID]
           ) AS rn
    FROM Superstore.dbo.Superstore
)
DELETE FROM Superstore.dbo.Superstore
WHERE [Order ID] IN (
    SELECT [Order ID]
    FROM CTE
    WHERE rn > 1
);
-- Sort by order date
 SELECT * 
FROM Superstore.dbo.Superstore
ORDER BY [Order_Date];
-- Delete unused columns
ALTER TABLE Superstore.dbo.Superstore
DROP COLUMN [Row ID], [Ship_Year], [Ship_Month], [Postal Code];

-- Measuring
-- Measure Shipping Duration
ALTER TABLE Superstore
ADD Shipping_Duration INT;
UPDATE Superstore
SET Shipping_Duration = DATEDIFF(DAY, Order_Date, Ship_Date);
--Average
SELECT 
    Order_Year,
    AVG(Shipping_Duration) AS Avg_Shipping_Days
FROM Superstore.dbo.Superstore
GROUP BY Order_Year
ORDER BY Order_Year;

SELECT 
    Order_Year AS Order_Year, 
    Order_Month AS Order_Month,
    AVG(Shipping_Duration) AS Avg_Shipping_Days
FROM Superstore.dbo.Superstore
GROUP BY Order_Year, Order_Month
ORDER BY Order_Year, Order_Month;
-- Cost, UnitPrice, UnitCost, MarginProfit
ALTER TABLE Superstore.dbo.Superstore
ADD Cost FLOAT, UnitPrice FLOAT, UnitCost FLOAT, ProfitMargin FLOAT;
UPDATE Superstore.dbo.Superstore
SET
Cost = Sales - Profit, 
UnitPrice = CASE WHEN Quantity = 0 THEN NULL ELSE Sales / Quantity END,
UnitCost = CASE WHEN Quantity = 0 THEN NULL ELSE (Sales - Profit) / Quantity END,
ProfitMargin = CASE WHEN Sales = 0 THEN NULL ELSE Profit / Sales END 
FROM Superstore.dbo.Superstore
-- Create DimTable
DROP TABLE IF EXISTS DimSegment, DimAddress, DimCustomer, DimOrderDate, DimCategory, DimSubCategory, DimProduct, DimShipMode;
--Adress Dim Table 
CREATE TABLE DimSegment (
    SegmentID INT IDENTITY(1,1) PRIMARY KEY,
    Segment NVARCHAR(50)
);

INSERT INTO DimSegment (Segment)
SELECT DISTINCT [Segment]
FROM Superstore.dbo.Superstore;
SELECT * FROM DimSegment

-- Adress Dim Table
CREATE TABLE DimAddress (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    Country NVARCHAR(50),
	City NVARCHAR(50),
    State NVARCHAR(50),
    Region NVARCHAR(50)
);

INSERT INTO DimAddress (Country,City,State,Region)
SELECT DISTINCT  [Country],[City],[State], [Region]
FROM Superstore.dbo.Superstore;
SELECT * FROM DimAddress
-- Customer Dim Table
CREATE TABLE DimCustomer (
    CustomerID NVARCHAR(50) PRIMARY KEY,
    CustomerName NVARCHAR(100), SegmentID INT,
    AddressID INT
);
INSERT INTO DimCustomer (CustomerID, CustomerName)
SELECT DISTINCT [Customer ID], [Customer Name]
FROM Superstore.dbo.Superstore;

UPDATE DimCustomer
SET SegmentID = seg.SegmentID
FROM DimCustomer c
JOIN Superstore.dbo.Superstore s ON c.CustomerID = s.[Customer ID]
JOIN DimSegment seg ON s.Segment = seg.Segment;

UPDATE DimCustomer
SET AddressID = addr.AddressID
FROM DimCustomer c
JOIN Superstore.dbo.Superstore s ON c.CustomerID = s.[Customer ID]
JOIN DimAddress addr 
     ON s.City = addr.City 
    AND s.State = addr.State 
    AND s.Country = addr.Country 
    AND s.Region = addr.Region;

SELECT * FROM DimCustomer
-- Date Dim Table
CREATE TABLE DimOrderDate (
   OrderDateID INT IDENTITY(1,1) PRIMARY KEY,
	OrderDate DATE,
    Month INT,
    Quarter INT,
    Year INT
);

INSERT INTO DimOrderDate (OrderDate, Month, Quarter, Year)
SELECT DISTINCT
    [Order_Date],
    [Order_Month],
    DATEPART(QUARTER, [Order_Date]),
    [Order_Year],
FROM Superstore.dbo.Superstore
WHERE [Order_Date] IS NOT NULL;
SELECT * FROM DimOrderDate
-- Product Dim Table
-- Bảng danh mục lớn: Category
CREATE TABLE DimCategory (
    CateID NVARCHAR(3) PRIMARY KEY,
    Category NVARCHAR(100)
);

INSERT INTO DimCategory (CateID, Category)
SELECT DISTINCT
    LEFT([Product ID], 3) AS CateID,
    [Category]
FROM Superstore.dbo.Superstore;
SELECT * FROM DimCategory

-- Bảng danh mục con: Sub-Category
CREATE TABLE DimSubCategory (
    SubCateID NVARCHAR(2) PRIMARY KEY,
    SubCategory NVARCHAR(100),
    CateID NVARCHAR(3) FOREIGN KEY REFERENCES DimCategory(CateID)
);

INSERT INTO DimSubCategory (SubCateID, SubCategory, CateID)
SELECT DISTINCT
    SUBSTRING([Product ID], 5, 2) AS SubCateID,
    [Sub-Category],
    LEFT([Product ID], 3) AS CateID
FROM Superstore.dbo.Superstore;
SELECT * FROM DimSubCategory
-- Bảng sản phẩm
DROP TABLE IF EXISTS DimProduct
CREATE TABLE DimProduct (
    ProductID NVARCHAR(50) PRIMARY KEY,
    ProductName NVARCHAR(300),
    SubCateID NVARCHAR(2) FOREIGN KEY REFERENCES DimSubCategory(SubCateID)
);

WITH Product_CTE AS (
    SELECT 
        RIGHT([Product ID], 8) AS ProductID,
        [Product Name],
        SUBSTRING([Product ID], 5, 2) AS SubCateID,
        ROW_NUMBER() OVER (PARTITION BY RIGHT([Product ID], 8) ORDER BY [Product Name]) AS rn
    FROM Superstore.dbo.Superstore
)
INSERT INTO DimProduct ( ProductID, ProductName, SubCateID)
SELECT ProductID, [Product Name], SubCateID
FROM Product_CTE
WHERE rn = 1;
SELECT* FROM DimProduct
-- ShipMode Dim Table
CREATE TABLE DimShipMode(
    ShipModeID INT IDENTITY(1,1) PRIMARY KEY,
    ShipMode NVARCHAR(100)
);

INSERT INTO DimShipMode(ShipMode)
SELECT DISTINCT [Ship Mode]
FROM Superstore.dbo.Superstore;
SELECT * FROM DimShipMode
-- Create fact table
DROP TABLE IF EXISTS FactTable 
CREATE TABLE FactTable 
(OrderID NVARCHAR (50),
CustomerID NVARCHAR(50),
ProductID NVARCHAR(50),
OrderDateID INT,
ShipModeID INT,
ShippingDuration INT,
Sales FLOAT,
Quantity INT,
Discount FLOAT,
Profit FLOAT,
Cost FLOAT,
UnitPrice FLOAT,
UnitCost FLOAT,
ProfitMargin FLOAT
);
INSERT INTO FactTable (
    OrderID, CustomerID, ProductID, OrderDateID, ShipModeID,ShippingDuration,
    Sales, Quantity, Discount, Profit, Cost, UnitPrice, UnitCost, ProfitMargin
)
SELECT DISTINCT s.[Order ID],
s.[Customer ID],
RIGHT(s.[Product ID], 8) AS ProductID,
d.OrderDateID,
sm.ShipModeID,
s.[Shipping_Duration],
s.[Sales],
s.[Quantity],
s.[Discount],
s.[Profit],
s.[Cost],
s.[UnitPrice],
s.[UnitCost],
s.[ProfitMargin]
FROM Superstore.dbo.Superstore s
JOIN DimOrderDate d
ON s. [Order_Date] = d.OrderDate
JOIN DimShipMode sm
ON s.[Ship Mode] = sm.ShipMode
SELECT * FROM FactTable