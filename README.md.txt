This project is a small e-commerce database built in SQL Server. The main goal was to design a complete and clean schema that covers products, brands, suppliers, users, orders, payments, inventory, reviews, and other supporting tables. The script is written in a way that allows it to be executed multiple times without breaking anything, thanks to the use of checks like IF NOT EXISTS before inserts and table creation.

To run the project, the user only needs to open SQL Server Management Studio, load the NotinoDB.sql file, and execute it. The script automatically creates the database, sets up all tables with their foreign keys, and loads sample data. Once the script completes successfully, the database is ready to explore.

For the demo, I can start by showing the ER diagram generated from the erd.dbml file on dbdiagram.io. It clearly shows the relationships between the main entities like Products, Users, Orders, and Inventory. Then, I can show some of the database features:

The ProductsInventorySummary view, which summarizes stock levels.

The CreateProduct stored procedure, which inserts a new product and logs the change.

The trigger that automatically updates an order to “paid” when its payment becomes “completed.”

Example queries at the end of the script, such as revenue per brand, pagination, and inventory value.

The project folder includes the main SQL script, the ERD source file, the ERD image, and the README. The script is defensive and safe to re-run, and all sample data is inserted only when missing. If any query returns empty results, quick checks using SELECT TOP 20 on key tables can be used to verify the data.

Overall, the project demonstrates database design, relationships, indexing, stored procedures, triggers, and basic reporting queries in a simple and organized way.