SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_01_stage_new_declarations
    @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start datetime2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.stg_new_decl_spe WHERE run_id = @run_id;
        DELETE FROM stg.stg_new_decl_pe WHERE run_id = @run_id;

        INSERT INTO stg.stg_new_decl_spe (
            run_id, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, spe_pseudoSiret, employment_type, date_debut_prestation, source_system,
            source, rnvp_score, created_at
        )
        SELECT
            @run_id,
            d.id_ligne_declaration,
            d.spe_nom_normalized,
            d.spe_prenom_normalized,
            d.spe_dateNaissance,
            d.spe_communeNaissance,
            d.spe_pseudoSiret,
            d.employment_type,
            d.date_debut_prestation,
            d.source_system,
            d.source,
            d.rnvp_score,
            COALESCE(d.created_at, SYSUTCDATETIME())
        FROM silver.v_decl_spe_canon d
        LEFT JOIN silver.v_mapping_canon m
            ON m.id_ligne_declaration = d.id_ligne_declaration
        WHERE d.valid_to IS NULL
          AND m.id_ligne_declaration IS NULL;

        INSERT INTO stg.stg_new_decl_pe (
            run_id, id_ligne_declaration, pe_pseudoSiret, pe_nom_normalized, pe_commune,
            source_system, source, rnvp_score, created_at
        )
        SELECT
            @run_id,
            d.id_ligne_declaration,
            d.pe_pseudoSiret,
            d.pe_nom_normalized,
            d.pe_commune,
            d.source_system,
            d.source,
            d.rnvp_score,
            COALESCE(d.created_at, SYSUTCDATETIME())
        FROM silver.v_decl_pe_canon d
        LEFT JOIN silver.v_mapping_canon m
            ON m.id_ligne_declaration = d.id_ligne_declaration
        WHERE d.valid_to IS NULL
          AND m.id_ligne_declaration IS NULL;

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_01_stage_new_declarations', @@ROWCOUNT, DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'staged declarations';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_01_stage_new_declarations', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_02_match_pe
    @run_id uniqueidentifier,
    @status_created varchar(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start datetime2(3) = SYSUTCDATETIME();
    BEGIN TRY
        ;WITH pe_latest AS (
            SELECT
                pe_masterid,
                pe_pseudoSiret,
                pe_nom_normalized,
                pe_commune,
                source_system,
                source,
                rnvp_score,
                created_at,
                ROW_NUMBER() OVER (PARTITION BY pe_pseudoSiret ORDER BY created_at DESC) AS rn
            FROM silver.v_pe_enriched_canon
        )
        UPDATE m
        SET
            m.pe_masterid = p.pe_masterid,
            m.pe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.stg_new_decl_pe s
            ON s.run_id = @run_id AND s.id_ligne_declaration = m.id_ligne_declaration
        INNER JOIN pe_latest p
            ON p.pe_pseudoSiret = s.pe_pseudoSiret AND p.rn = 1
        WHERE m.pe_masterid IS NULL;

        INSERT INTO mdm.declaration_ref_mapping (
            id_ligne_declaration, pe_masterid, pe_match_status, run_id
        )
        SELECT
            s.id_ligne_declaration,
            p.pe_masterid,
            'Matched',
            @run_id
        FROM stg.stg_new_decl_pe s
        INNER JOIN pe_latest p
            ON p.pe_pseudoSiret = s.pe_pseudoSiret AND p.rn = 1
        WHERE s.run_id = @run_id
          AND NOT EXISTS (
                SELECT 1 FROM mdm.declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK)
                WHERE m.id_ligne_declaration = s.id_ligne_declaration
          );

        ;WITH pe_missing AS (
            SELECT s.*
            FROM stg.stg_new_decl_pe s
            LEFT JOIN pe_latest p
                ON p.pe_pseudoSiret = s.pe_pseudoSiret AND p.rn = 1
            WHERE s.run_id = @run_id
              AND p.pe_masterid IS NULL
        ),
        assigned AS (
            SELECT
                s.*, NEXT VALUE FOR mdm.seq_pe_masterid AS new_masterid
            FROM pe_missing s
        )
        INSERT INTO mdm.declaration_ref_mapping (
            id_ligne_declaration, pe_masterid, pe_match_status, run_id
        )
        SELECT
            a.id_ligne_declaration,
            a.new_masterid,
            @status_created,
            @run_id
        FROM assigned a
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK)
            WHERE m.id_ligne_declaration = a.id_ligne_declaration
        );

        INSERT INTO mdm.pe_enriched_format (
            pe_masterid, pe_pseudoSiret, pe_nom_normalized, pe_commune,
            source_system, source, rnvp_score, created_at
        )
        SELECT DISTINCT
            a.new_masterid,
            a.pe_pseudoSiret,
            a.pe_nom_normalized,
            a.pe_commune,
            a.source_system,
            a.source,
            a.rnvp_score,
            a.created_at
        FROM assigned a
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.pe_enriched_format e
            WHERE e.pe_masterid = a.new_masterid
              AND e.pe_pseudoSiret = a.pe_pseudoSiret
        );

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_02_match_pe', @@ROWCOUNT, DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'match pe';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_02_match_pe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_03_match_spe_deterministic
    @run_id uniqueidentifier,
    @status_created varchar(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start datetime2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.stg_spe_nonmatched WHERE run_id = @run_id;

        UPDATE m
        SET
            m.spe_masterid = e.spe_masterid,
            m.spe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.stg_new_decl_spe s
            ON s.run_id = @run_id AND s.id_ligne_declaration = m.id_ligne_declaration
        INNER JOIN silver.v_spe_enriched_canon e
            ON e.spe_nom_normalized = s.spe_nom_normalized
           AND e.spe_prenom_normalized = s.spe_prenom_normalized
           AND e.spe_dateNaissance = s.spe_dateNaissance
           AND e.spe_communeNaissance = s.spe_communeNaissance
        WHERE m.spe_masterid IS NULL;

        INSERT INTO mdm.declaration_ref_mapping (
            id_ligne_declaration, spe_masterid, spe_match_status, run_id
        )
        SELECT
            s.id_ligne_declaration,
            e.spe_masterid,
            'Matched',
            @run_id
        FROM stg.stg_new_decl_spe s
        INNER JOIN silver.v_spe_enriched_canon e
            ON e.spe_nom_normalized = s.spe_nom_normalized
           AND e.spe_prenom_normalized = s.spe_prenom_normalized
           AND e.spe_dateNaissance = s.spe_dateNaissance
           AND e.spe_communeNaissance = s.spe_communeNaissance
        WHERE s.run_id = @run_id
          AND NOT EXISTS (
            SELECT 1 FROM mdm.declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK)
            WHERE m.id_ligne_declaration = s.id_ligne_declaration
          );

        INSERT INTO mdm.spe_enriched_format (
            spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, source_system, source, rnvp_score, created_at
        )
        SELECT DISTINCT
            e.spe_masterid,
            s.spe_nom_normalized,
            s.spe_prenom_normalized,
            s.spe_dateNaissance,
            s.spe_communeNaissance,
            s.source_system,
            s.source,
            s.rnvp_score,
            s.created_at
        FROM stg.stg_new_decl_spe s
        INNER JOIN silver.v_spe_enriched_canon e
            ON e.spe_nom_normalized = s.spe_nom_normalized
           AND e.spe_prenom_normalized = s.spe_prenom_normalized
           AND e.spe_dateNaissance = s.spe_dateNaissance
           AND e.spe_communeNaissance = s.spe_communeNaissance
        WHERE s.run_id = @run_id
          AND NOT EXISTS (
            SELECT 1 FROM mdm.spe_enriched_format f
            WHERE f.spe_masterid = e.spe_masterid
              AND f.spe_nom_normalized = s.spe_nom_normalized
              AND f.spe_prenom_normalized = s.spe_prenom_normalized
              AND f.spe_dateNaissance = s.spe_dateNaissance
              AND f.spe_communeNaissance = s.spe_communeNaissance
          );

        INSERT INTO stg.stg_spe_nonmatched (
            run_id, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, employment_type, date_debut_prestation, source_system, source, rnvp_score, created_at
        )
        SELECT
            s.run_id, s.id_ligne_declaration, s.spe_nom_normalized, s.spe_prenom_normalized, s.spe_dateNaissance,
            s.spe_communeNaissance, s.employment_type, s.date_debut_prestation, s.source_system, s.source, s.rnvp_score, s.created_at
        FROM stg.stg_new_decl_spe s
        LEFT JOIN silver.v_spe_enriched_canon e
            ON e.spe_nom_normalized = s.spe_nom_normalized
           AND e.spe_prenom_normalized = s.spe_prenom_normalized
           AND e.spe_dateNaissance = s.spe_dateNaissance
           AND e.spe_communeNaissance = s.spe_communeNaissance
        WHERE s.run_id = @run_id
          AND e.spe_masterid IS NULL;

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_03_match_spe_deterministic', @@ROWCOUNT, DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'match spe deterministic';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_03_match_spe_deterministic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_04_match_spe_probabilistic_candidates
    @run_id uniqueidentifier,
    @threshold float = 0.8
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start datetime2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM dq.spe_match_candidates WHERE run_id = @run_id;

        INSERT INTO dq.spe_match_candidates (
            run_id, id_ligne_declaration, candidate_spe_masterid, score_total,
            score_nom, score_prenom, score_dob, score_commune
        )
        SELECT
            @run_id,
            s.id_ligne_declaration,
            e.spe_masterid,
            dq.fn_spe_score(s.spe_nom_normalized, e.spe_nom_normalized, s.spe_prenom_normalized, e.spe_prenom_normalized,
                s.spe_dateNaissance, e.spe_dateNaissance, s.spe_communeNaissance, e.spe_communeNaissance) AS score_total,
            dq.fn_similarity(s.spe_nom_normalized, e.spe_nom_normalized) AS score_nom,
            dq.fn_similarity(s.spe_prenom_normalized, e.spe_prenom_normalized) AS score_prenom,
            dq.fn_date_similarity(s.spe_dateNaissance, e.spe_dateNaissance) AS score_dob,
            dq.fn_similarity(s.spe_communeNaissance, e.spe_communeNaissance) AS score_commune
        FROM stg.stg_spe_nonmatched s
        INNER JOIN mdm.spe_enriched_format e
            ON e.blocking_year = s.blocking_year
           AND e.blocking_nom2 = s.blocking_nom2
           AND e.blocking_pre2 = s.blocking_pre2
        WHERE s.run_id = @run_id
          AND dq.fn_spe_score(s.spe_nom_normalized, e.spe_nom_normalized, s.spe_prenom_normalized, e.spe_prenom_normalized,
                s.spe_dateNaissance, e.spe_dateNaissance, s.spe_communeNaissance, e.spe_communeNaissance) >= @threshold;

        ;WITH cand_counts AS (
            SELECT id_ligne_declaration,
                   COUNT(DISTINCT candidate_spe_masterid) AS cnt,
                   MAX(score_total) AS best_score,
                   MAX(CASE WHEN score_total = (SELECT MAX(score_total) FROM dq.spe_match_candidates c2
                                               WHERE c2.run_id = c1.run_id AND c2.id_ligne_declaration = c1.id_ligne_declaration)
                       THEN candidate_spe_masterid END) AS best_candidate
            FROM dq.spe_match_candidates c1
            WHERE run_id = @run_id
            GROUP BY id_ligne_declaration
        )
        UPDATE m
        SET
            m.spe_match_status = CASE WHEN c.cnt = 1 THEN 'Proba_One_Match_to_stewardship' ELSE 'Proba_Several_Match_to_stewardship' END,
            m.best_candidate_masterid = c.best_candidate,
            m.best_candidate_score = c.best_score,
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN cand_counts c
            ON c.id_ligne_declaration = m.id_ligne_declaration
        WHERE m.spe_masterid IS NULL;

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_04_match_spe_probabilistic_candidates', @@ROWCOUNT, DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'proba candidates';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_04_match_spe_probabilistic_candidates', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO
