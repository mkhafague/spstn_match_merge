SET NOCOUNT ON;
GO

PRINT 'Creating sequences...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_spe_masterid' AND SCHEMA_NAME(schema_id) = 'mdm')
    CREATE SEQUENCE mdm.seq_spe_masterid AS BIGINT START WITH 1 INCREMENT BY 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_pe_masterid' AND SCHEMA_NAME(schema_id) = 'mdm')
    CREATE SEQUENCE mdm.seq_pe_masterid AS BIGINT START WITH 1 INCREMENT BY 1;
GO
