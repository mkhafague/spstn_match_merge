SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @run_id uniqueidentifier = NEWID();

-- Clean run-specific data
DELETE FROM stg.stg_spe_nonmatched WHERE run_id = @run_id;
DELETE FROM stg.spe_nodes WHERE run_id = @run_id;
DELETE FROM stg.spe_edges WHERE run_id = @run_id;
DELETE FROM stg.spe_components WHERE run_id = @run_id;
DELETE FROM dq.spe_match_candidates_intrarun WHERE run_id = @run_id;
DELETE FROM mdm.declaration_ref_mapping WHERE id_ligne_declaration IN (1001,1002,2001,2002,3001,3002,3003,3004,3005);

-- Dataset: deterministic cluster (1001,1002)
INSERT INTO stg.stg_spe_nonmatched (
    run_id, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
    spe_communeNaissance, employment_type, date_debut_prestation, source_system, source, rnvp_score
)
VALUES
(@run_id, 1001, 'DURAND', 'ALICE', '1980-01-01', 'LYON', 'EMP', '2024-01-01', 'CRM', 'PAJEMPLOI', 1),
(@run_id, 1002, 'DURAND', 'ALICE', '1980-01-01', 'LYON', 'EMP', '2024-01-02', 'CRM', 'PAJEMPLOI', 1),
-- Proba-only component (2001,2002)
(@run_id, 2001, 'MARTIN', 'BRUNO', '1975-02-02', 'PARIS', 'EMP', '2024-02-01', 'UCN', 'CESU', 0),
(@run_id, 2002, 'MARTIN', 'BRUNO', '1975-02-02', 'PAR1S', 'EMP', '2024-02-02', 'UCN', 'CESU', 0),
-- Component with 2 anchors + proba node (3001-3005)
(@run_id, 3001, 'ROBERT', 'CLAIRE', '1990-03-03', 'NANTES', 'EMP', '2024-03-01', 'CRM', 'PAJEMPLOI', 1),
(@run_id, 3002, 'ROBERT', 'CLAIRE', '1990-03-03', 'NANTES', 'EMP', '2024-03-02', 'CRM', 'PAJEMPLOI', 1),
(@run_id, 3003, 'ROBERT', 'CLARA', '1990-03-03', 'NANTES', 'EMP', '2024-03-03', 'CRM', 'PAJEMPLOI', 1),
(@run_id, 3004, 'ROBERT', 'CLARA', '1990-03-03', 'NANTES', 'EMP', '2024-03-04', 'CRM', 'PAJEMPLOI', 1),
(@run_id, 3005, 'ROBERT', 'CLARE', '1990-03-03', 'NANTES', 'EMP', '2024-03-05', 'CRM', 'PAJEMPLOI', 1);

EXEC silver.sp_mm_05_build_intrarun_graph @run_id = @run_id, @threshold = 0.8;
EXEC silver.sp_mm_06_compute_connected_components @run_id = @run_id, @max_iter = 1000;
EXEC silver.sp_mm_07_new_spe_dedup_deterministic @run_id = @run_id, @status_created = 'Created';
EXEC silver.sp_mm_08_new_spe_dedup_probabilistic @run_id = @run_id;

-- Assertions (manual checks)
SELECT 'components' AS check_name, component_id, COUNT(*) AS node_count
FROM stg.spe_components
WHERE run_id = @run_id
GROUP BY component_id;

SELECT 'mapping' AS check_name, id_ligne_declaration, spe_masterid, spe_match_status
FROM mdm.declaration_ref_mapping
WHERE id_ligne_declaration IN (1001,1002,2001,2002,3001,3002,3003,3004,3005)
ORDER BY id_ligne_declaration;

SELECT 'candidates' AS check_name, node_id, candidate_spe_masterid, score_total
FROM dq.spe_match_candidates_intrarun
WHERE run_id = @run_id
ORDER BY node_id, candidate_spe_masterid;
GO
