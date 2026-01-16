SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dq.sp_apply_stewardship_decisions
    @run_id uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ;WITH decisions AS (
            SELECT d.*
            FROM dq.spe_stewardship_decision d
            WHERE (@run_id IS NULL OR d.run_id = @run_id)
        )
        UPDATE m
        SET m.spe_masterid = d.chosen_spe_masterid,
            m.spe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME()
        FROM mdm.declaration_ref_mapping m
        INNER JOIN decisions d
            ON d.id_ligne_declaration = m.id_ligne_declaration
        WHERE d.decision_status = 'APPROVED'
          AND d.chosen_spe_masterid IS NOT NULL;

        INSERT INTO mdm.spe_enriched_format (
            spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, source_system, source, rnvp_score, created_at
        )
        SELECT
            d.chosen_spe_masterid,
            s.spe_nom_normalized,
            s.spe_prenom_normalized,
            s.spe_dateNaissance,
            s.spe_communeNaissance,
            s.source_system,
            s.source,
            s.rnvp_score,
            s.created_at
        FROM decisions d
        INNER JOIN stg.stg_new_decl_spe s
            ON s.id_ligne_declaration = d.id_ligne_declaration
        WHERE d.decision_status = 'APPROVED'
          AND d.chosen_spe_masterid IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM mdm.spe_enriched_format f
            WHERE f.spe_masterid = d.chosen_spe_masterid
              AND f.spe_nom_normalized = s.spe_nom_normalized
              AND f.spe_prenom_normalized = s.spe_prenom_normalized
              AND f.spe_dateNaissance = s.spe_dateNaissance
              AND f.spe_communeNaissance = s.spe_communeNaissance
          );

        UPDATE m
        SET m.spe_match_status = 'Rejected',
            m.updated_at = SYSUTCDATETIME()
        FROM mdm.declaration_ref_mapping m
        INNER JOIN decisions d
            ON d.id_ligne_declaration = m.id_ligne_declaration
        WHERE d.decision_status = 'REJECTED';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_apply_stewardship_decisions', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO
