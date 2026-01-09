SET NOCOUNT ON;
GO

PRINT 'Creating stewardship procedure...';
GO

IF OBJECT_ID('dq.sp_apply_stewardship_decisions') IS NOT NULL DROP PROCEDURE dq.sp_apply_stewardship_decisions;
GO
CREATE PROCEDURE dq.sp_apply_stewardship_decisions
    @run_id UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        ;WITH deci AS (
            SELECT * FROM dq.spe_stewardship_decision
            WHERE decision_status IN ('APPROVED','REJECTED')
              AND (@run_id IS NULL OR run_id = @run_id)
        )
        SELECT * INTO #decisions FROM deci;

        -- Approved: assign masterid and mark matched
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_masterid = d.chosen_spe_masterid,
            m.spe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN #decisions d ON d.id_ligne_declaration = m.id_ligne_declaration
        WHERE d.decision_status = 'APPROVED';

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_masterid, spe_match_status, created_at, updated_at)
        SELECT d.id_ligne_declaration, d.chosen_spe_masterid, 'Matched', SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #decisions d
        WHERE d.decision_status = 'APPROVED'
          AND NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = d.id_ligne_declaration);

        -- Insert enriched format for approved rows (pivoting on staging nodes)
        INSERT INTO silver.Silver_spe_enriched(spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok, created_at)
        SELECT DISTINCT d.chosen_spe_masterid, n.spe_nom_normalized, n.spe_prenom_normalized, n.spe_dateNaissance, n.spe_communeNaissance, NULL, SYSUTCDATETIME()
        FROM #decisions d
        JOIN stg.spe_nodes n ON n.id_ligne_declaration = d.id_ligne_declaration
        WHERE d.decision_status = 'APPROVED'
          AND NOT EXISTS (
              SELECT 1 FROM silver.Silver_spe_enriched e
              WHERE e.spe_masterid = d.chosen_spe_masterid
                AND e.spe_nom_normalized = n.spe_nom_normalized
                AND e.spe_prenom_normalized = n.spe_prenom_normalized
                AND e.spe_dateNaissance = n.spe_dateNaissance
                AND e.spe_communeNaissance = n.spe_communeNaissance
          );

        -- Rejected: mark status accordingly
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_match_status = 'Rejected',
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN #decisions d ON d.id_ligne_declaration = m.id_ligne_declaration
        WHERE d.decision_status = 'REJECTED';

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_match_status, created_at, updated_at)
        SELECT d.id_ligne_declaration, 'Rejected', SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #decisions d
        WHERE d.decision_status = 'REJECTED'
          AND NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = d.id_ligne_declaration);

        EXEC ctl.sp_log_metric @run_id, 'apply_stewardship_decisions', (SELECT COUNT(*) FROM #decisions), DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_apply_stewardship_decisions', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO
