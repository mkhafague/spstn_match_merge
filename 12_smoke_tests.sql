SET NOCOUNT ON;
GO

PRINT 'Smoke test dataset setup';
GO

-- Clean tables (minimal scope for repeatability)
DELETE FROM dq.spe_match_candidates;
DELETE FROM dq.spe_match_candidates_intrarun;
DELETE FROM dq.spe_stewardship_decision;
DELETE FROM stg.spe_edges;
DELETE FROM stg.spe_components;
DELETE FROM stg.spe_nodes;
DELETE FROM stg.stg_spe_nonmatched;
DELETE FROM stg.stg_new_decl_spe;
DELETE FROM stg.stg_new_decl_pe;
DELETE FROM silver.Silver_declaration_ref_mapping;
DELETE FROM silver.Silver_spe_enriched;
DELETE FROM silver.Silver_pe_enriched;
DELETE FROM silver.Silver_decl_spe;
DELETE FROM silver.Silver_decl_pe;
DELETE FROM mdm.Silver_master_relation;
DELETE FROM mdm.Silver_master_spe;
DELETE FROM mdm.Silver_master_pe;
DELETE FROM ctl.process_metrics;
DELETE FROM ctl.process_error;
DELETE FROM ctl.process_run;
DELETE FROM ctl.merge_log;
GO

PRINT 'Insert SPE declarations (deterministic cluster, dual anchors, proba-only component)';
GO
-- Deterministic cluster A (2 rows) -> anchor M1
INSERT INTO silver.Silver_decl_spe(id_ligne_declaration, spe_nom, spe_nom_normalized, spe_prenom, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
VALUES
(101, N'DUPONT', N'DUPONT', N'ALICE', N'ALICE', '1990-01-01', N'PARIS', SYSUTCDATETIME()),
(102, N'DUPONT', N'DUPONT', N'ALICE', N'ALICE', '1990-01-01', N'PARIS', SYSUTCDATETIME());

-- Deterministic cluster B (2 rows) -> anchor M2
INSERT INTO silver.Silver_decl_spe(id_ligne_declaration, spe_nom, spe_nom_normalized, spe_prenom, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
VALUES
(103, N'DUPONX', N'DUPONX', N'ALAIN', N'ALAIN', '1990-01-01', N'PARIS', SYSUTCDATETIME()),
(104, N'DUPONX', N'DUPONX', N'ALAIN', N'ALAIN', '1990-01-01', N'PARIS', SYSUTCDATETIME());

-- Node linked to both anchors (Proba_Several expected)
INSERT INTO silver.Silver_decl_spe(id_ligne_declaration, spe_nom, spe_nom_normalized, spe_prenom, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
VALUES
(105, N'DUPONO', N'DUPONO', N'ALBERT', N'ALBERT', '1990-01-01', N'PARIS', SYSUTCDATETIME());

-- Proba-only component (no deterministic cluster)
INSERT INTO silver.Silver_decl_spe(id_ligne_declaration, spe_nom, spe_nom_normalized, spe_prenom, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
VALUES
(201, N'MARTIN', N'MARTIN', N'BOB', N'BOB', '1991-05-05', N'LYON', SYSUTCDATETIME()),
(202, N'MARTYN', N'MARTYN', N'BOB', N'BOB', '1991-05-05', N'LYON', SYSUTCDATETIME());
GO

PRINT 'Insert PE declarations';
GO
INSERT INTO silver.Silver_decl_pe(id_ligne_declaration, pseudo_siret, created_at)
VALUES
(101, 'SIRET001', SYSUTCDATETIME()),
(102, 'SIRET002', SYSUTCDATETIME()),
(103, 'SIRET003', SYSUTCDATETIME()),
(104, 'SIRET004', SYSUTCDATETIME()),
(105, 'SIRET005', SYSUTCDATETIME()),
(201, 'SIRET006', SYSUTCDATETIME()),
(202, 'SIRET007', SYSUTCDATETIME());
GO

DECLARE @run_id UNIQUEIDENTIFIER;
EXEC ctl.sp_mm_run @run_id = @run_id OUTPUT, @threshold = 0.8;
PRINT CONCAT('Run executed: ', CONVERT(VARCHAR(36), @run_id));
GO

PRINT 'Assertions / inspection';
GO
-- Deterministic cluster A -> status Created/Matched with masterid
SELECT id_ligne_declaration, spe_masterid, spe_match_status
FROM silver.Silver_declaration_ref_mapping
WHERE id_ligne_declaration IN (101,102);

-- Component with two anchors -> node 105 should be proba several
SELECT id_ligne_declaration, spe_masterid, spe_match_status, best_candidate_masterid, best_score
FROM silver.Silver_declaration_ref_mapping
WHERE id_ligne_declaration = 105;

-- Proba-only component -> pivot chosen, other node to stewardship
SELECT id_ligne_declaration, spe_masterid, spe_match_status
FROM silver.Silver_declaration_ref_mapping
WHERE id_ligne_declaration IN (201,202);

-- Connected components check
SELECT TOP 10 * FROM stg.spe_components WHERE run_id = @run_id ORDER BY component_id, node_id;

-- Intra-run candidates
SELECT * FROM dq.spe_match_candidates_intrarun WHERE run_id = @run_id ORDER BY node_id, candidate_spe_masterid;
GO
