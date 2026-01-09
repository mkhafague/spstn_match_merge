PRINT 'Creating schemas...';
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ctl')
    EXEC('CREATE SCHEMA ctl');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
    EXEC('CREATE SCHEMA stg');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dq')
    EXEC('CREATE SCHEMA dq');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mdm')
    EXEC('CREATE SCHEMA mdm');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO
