SET NOCOUNT ON;
GO

PRINT 'Creating indexes for blocking and performance...';
GO

-- Staging SPE declarations
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stg_new_decl_spe_blocking' AND object_id = OBJECT_ID('stg.stg_new_decl_spe'))
    CREATE INDEX IX_stg_new_decl_spe_blocking ON stg.stg_new_decl_spe(blocking_year, blocking_nom2, blocking_pre2) INCLUDE (id_ligne_declaration, created_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stg_spe_nonmatched_blocking' AND object_id = OBJECT_ID('stg.stg_spe_nonmatched'))
    CREATE INDEX IX_stg_spe_nonmatched_blocking ON stg.stg_spe_nonmatched(blocking_year, blocking_nom2, blocking_pre2) INCLUDE (id_ligne_declaration, created_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stg_spe_nodes_blocking' AND object_id = OBJECT_ID('stg.spe_nodes'))
    CREATE INDEX IX_stg_spe_nodes_blocking ON stg.spe_nodes(blocking_year, blocking_nom2, blocking_pre2) INCLUDE (node_id, created_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_silver_spe_enriched_blocking' AND object_id = OBJECT_ID('silver.Silver_spe_enriched'))
    CREATE INDEX IX_silver_spe_enriched_blocking ON silver.Silver_spe_enriched(blocking_year, blocking_nom2, blocking_pre2) INCLUDE (spe_masterid, created_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_edges_run_nodea' AND object_id = OBJECT_ID('stg.spe_edges'))
    CREATE INDEX IX_spe_edges_run_nodea ON stg.spe_edges(run_id, node_a);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_edges_run_nodeb' AND object_id = OBJECT_ID('stg.spe_edges'))
    CREATE INDEX IX_spe_edges_run_nodeb ON stg.spe_edges(run_id, node_b);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_components_run_node' AND object_id = OBJECT_ID('stg.spe_components'))
    CREATE UNIQUE INDEX IX_spe_components_run_node ON stg.spe_components(run_id, node_id);
GO
