SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_spe_masterid' AND SCHEMA_NAME(schema_id) = 'mdm')
BEGIN
    CREATE SEQUENCE mdm.seq_spe_masterid AS BIGINT START WITH 1 INCREMENT BY 1;
END;

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_pe_masterid' AND SCHEMA_NAME(schema_id) = 'mdm')
BEGIN
    CREATE SEQUENCE mdm.seq_pe_masterid AS BIGINT START WITH 1 INCREMENT BY 1;
END;
GO
