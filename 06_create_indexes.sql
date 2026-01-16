SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stg_new_decl_spe_blocking' AND object_id = OBJECT_ID('stg.stg_new_decl_spe'))
    CREATE INDEX IX_stg_new_decl_spe_blocking ON stg.stg_new_decl_spe(blocking_year, blocking_nom2, blocking_pre2)
    INCLUDE (id_ligne_declaration, created_at, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stg_spe_nonmatched_blocking' AND object_id = OBJECT_ID('stg.stg_spe_nonmatched'))
    CREATE INDEX IX_stg_spe_nonmatched_blocking ON stg.stg_spe_nonmatched(blocking_year, blocking_nom2, blocking_pre2)
    INCLUDE (id_ligne_declaration, created_at, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_mdm_spe_enriched_blocking' AND object_id = OBJECT_ID('mdm.spe_enriched_format'))
    CREATE INDEX IX_mdm_spe_enriched_blocking ON mdm.spe_enriched_format(blocking_year, blocking_nom2, blocking_pre2)
    INCLUDE (spe_masterid, created_at, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_edges_node_a' AND object_id = OBJECT_ID('stg.spe_edges'))
    CREATE INDEX IX_spe_edges_node_a ON stg.spe_edges(run_id, node_a);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_edges_node_b' AND object_id = OBJECT_ID('stg.spe_edges'))
    CREATE INDEX IX_spe_edges_node_b ON stg.spe_edges(run_id, node_b);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spe_components_run_node' AND object_id = OBJECT_ID('stg.spe_components'))
    CREATE UNIQUE INDEX IX_spe_components_run_node ON stg.spe_components(run_id, node_id);
GO
