SET NOCOUNT ON;
GO

PRINT 'Creating control stored procedures...';
GO

IF OBJECT_ID('ctl.sp_run_start') IS NOT NULL DROP PROCEDURE ctl.sp_run_start;
GO
CREATE PROCEDURE ctl.sp_run_start
    @process_name SYSNAME,
    @run_id UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @run_id IS NULL SET @run_id = NEWID();
    BEGIN TRY
        INSERT INTO ctl.process_run(run_id, process_name, start_ts, status, host_name, executed_by)
        VALUES(@run_id, @process_name, SYSUTCDATETIME(), 'Running', HOST_NAME(), SUSER_SNAME());
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_run_start', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('ctl.sp_run_end') IS NOT NULL DROP PROCEDURE ctl.sp_run_end;
GO
CREATE PROCEDURE ctl.sp_run_end
    @run_id UNIQUEIDENTIFIER,
    @status VARCHAR(20),
    @error_message NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        UPDATE ctl.process_run WITH (HOLDLOCK)
        SET end_ts = SYSUTCDATETIME(),
            status = @status,
            error_message = @error_message
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_run_end', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('ctl.sp_log_metric') IS NOT NULL DROP PROCEDURE ctl.sp_log_metric;
GO
CREATE PROCEDURE ctl.sp_log_metric
    @run_id UNIQUEIDENTIFIER,
    @step_name NVARCHAR(200),
    @row_count BIGINT = NULL,
    @duration_ms BIGINT = NULL,
    @comment NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO ctl.process_metrics(run_id, step_name, row_count, duration_ms, comment)
        VALUES(@run_id, @step_name, @row_count, @duration_ms, @comment);
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_log_metric', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
    END CATCH
END;
GO

IF OBJECT_ID('ctl.sp_mm_acquire_lock') IS NOT NULL DROP PROCEDURE ctl.sp_mm_acquire_lock;
GO
CREATE PROCEDURE ctl.sp_mm_acquire_lock
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @res INT;
    EXEC @res = sp_getapplock @Resource = 'MM_RUN', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 60000;
    IF @res < 0
        RAISERROR('Unable to acquire application lock MM_RUN', 16, 1);
END;
GO

IF OBJECT_ID('ctl.sp_mm_release_lock') IS NOT NULL DROP PROCEDURE ctl.sp_mm_release_lock;
GO
CREATE PROCEDURE ctl.sp_mm_release_lock
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_releaseapplock @Resource = 'MM_RUN', @LockOwner = 'Session';
END;
GO

PRINT 'Creating match stored procedures...';
GO

IF OBJECT_ID('silver.sp_mm_01_stage_new_declarations') IS NOT NULL DROP PROCEDURE silver.sp_mm_01_stage_new_declarations;
GO
CREATE PROCEDURE silver.sp_mm_01_stage_new_declarations
    @run_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.stg_new_decl_spe WHERE run_id = @run_id;
        DELETE FROM stg.stg_new_decl_pe WHERE run_id = @run_id;

        INSERT INTO stg.stg_new_decl_spe(run_id, id_ligne_declaration, spe_nom, spe_nom_normalized, spe_prenom, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
        SELECT @run_id, d.id_ligne_declaration, d.spe_nom, d.spe_nom_normalized, d.spe_prenom, d.spe_prenom_normalized, d.spe_dateNaissance, d.spe_communeNaissance, d.created_at
        FROM silver.v_decl_spe_canon d
        WHERE d.valid_to IS NULL
          AND NOT EXISTS (SELECT 1 FROM silver.v_mapping_canon m WHERE m.id_ligne_declaration = d.id_ligne_declaration AND m.valid_to IS NULL);

        INSERT INTO stg.stg_new_decl_pe(run_id, id_ligne_declaration, pseudo_siret, created_at)
        SELECT @run_id, p.id_ligne_declaration, p.pseudo_siret, p.created_at
        FROM silver.v_decl_pe_canon p
        WHERE p.valid_to IS NULL
          AND NOT EXISTS (SELECT 1 FROM silver.v_mapping_canon m WHERE m.id_ligne_declaration = p.id_ligne_declaration AND m.valid_to IS NULL);

        EXEC ctl.sp_log_metric @run_id, '01_stage_new_decl_spe', @@ROWCOUNT, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_01_stage_new_declarations', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_02_match_pe') IS NOT NULL DROP PROCEDURE silver.sp_mm_02_match_pe;
GO
CREATE PROCEDURE silver.sp_mm_02_match_pe
    @run_id UNIQUEIDENTIFIER,
    @status_created VARCHAR(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        ;WITH cte_pe AS (
            SELECT s.run_id, s.id_ligne_declaration, s.pseudo_siret,
                   ea.pe_masterid,
                   ROW_NUMBER() OVER (PARTITION BY s.id_ligne_declaration ORDER BY ea.created_at DESC) AS rn
            FROM stg.stg_new_decl_pe s
            OUTER APPLY (
                SELECT TOP 1 pe_masterid, created_at
                FROM silver.v_pe_enriched_canon e
                WHERE e.pseudo_siret = s.pseudo_siret AND e.valid_to IS NULL
                ORDER BY e.created_at DESC
            ) ea
        )
        SELECT run_id, id_ligne_declaration, pseudo_siret,
               CASE WHEN pe_masterid IS NULL THEN NEXT VALUE FOR mdm.seq_pe_masterid ELSE pe_masterid END AS chosen_masterid
        INTO #pe_match
        FROM cte_pe
        WHERE rn = 1;

        DECLARE @rows BIGINT = (SELECT COUNT(*) FROM #pe_match);

        -- Upsert mapping (update then insert)
        UPDATE m WITH (HOLDLOCK)
        SET m.pe_masterid = pm.chosen_masterid,
            m.pe_match_status = CASE WHEN pm.chosen_masterid IS NULL THEN NULL ELSE 'Matched' END,
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        INNER JOIN #pe_match pm ON pm.id_ligne_declaration = m.id_ligne_declaration;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, pe_masterid, pe_match_status, created_at, updated_at)
        SELECT pm.id_ligne_declaration, pm.chosen_masterid, 'Matched', SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #pe_match pm
        WHERE NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = pm.id_ligne_declaration);

        -- Insert enriched format if absent
        INSERT INTO silver.Silver_pe_enriched(pe_masterid, pseudo_siret, rnvp_ok, created_at)
        SELECT DISTINCT pm.chosen_masterid, pm.pseudo_siret, NULL, SYSUTCDATETIME()
        FROM #pe_match pm
        WHERE NOT EXISTS (
            SELECT 1 FROM silver.Silver_pe_enriched e
            WHERE e.pe_masterid = pm.chosen_masterid AND e.pseudo_siret = pm.pseudo_siret
        );

        EXEC ctl.sp_log_metric @run_id, '02_match_pe', @rows, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_02_match_pe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_03_match_spe_deterministic') IS NOT NULL DROP PROCEDURE silver.sp_mm_03_match_spe_deterministic;
GO
CREATE PROCEDURE silver.sp_mm_03_match_spe_deterministic
    @run_id UNIQUEIDENTIFIER,
    @status_created VARCHAR(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.stg_spe_nonmatched WHERE run_id = @run_id;

        ;WITH cte AS (
            SELECT s.*, e.spe_masterid,
                   ROW_NUMBER() OVER (PARTITION BY s.id_ligne_declaration ORDER BY e.created_at DESC) rn
            FROM stg.stg_new_decl_spe s
            LEFT JOIN silver.v_spe_enriched_canon e
              ON e.spe_nom_normalized = s.spe_nom_normalized
             AND e.spe_prenom_normalized = s.spe_prenom_normalized
             AND e.spe_dateNaissance = s.spe_dateNaissance
             AND e.spe_communeNaissance = s.spe_communeNaissance
             AND e.valid_to IS NULL
        )
        SELECT run_id, id_ligne_declaration, spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance
        INTO #det
        FROM cte WHERE rn = 1;

        -- Mapping update/insert
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_masterid = d.spe_masterid,
            m.spe_match_status = CASE WHEN d.spe_masterid IS NULL THEN NULL ELSE 'Matched' END,
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        INNER JOIN #det d ON d.id_ligne_declaration = m.id_ligne_declaration;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_masterid, spe_match_status, created_at, updated_at)
        SELECT d.id_ligne_declaration, d.spe_masterid, 'Matched', SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #det d
        WHERE d.spe_masterid IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = d.id_ligne_declaration);

        -- Non matched move to staging
        INSERT INTO stg.stg_spe_nonmatched(run_id, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
        SELECT @run_id, d.id_ligne_declaration, d.spe_nom_normalized, d.spe_prenom_normalized, d.spe_dateNaissance, d.spe_communeNaissance, SYSUTCDATETIME()
        FROM #det d
        WHERE d.spe_masterid IS NULL;

        -- Insert enriched format when missing
        INSERT INTO silver.Silver_spe_enriched(spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok, created_at)
        SELECT DISTINCT d.spe_masterid, d.spe_nom_normalized, d.spe_prenom_normalized, d.spe_dateNaissance, d.spe_communeNaissance, NULL, SYSUTCDATETIME()
        FROM #det d
        WHERE d.spe_masterid IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM silver.Silver_spe_enriched e
              WHERE e.spe_masterid = d.spe_masterid
                AND e.spe_nom_normalized = d.spe_nom_normalized
                AND e.spe_prenom_normalized = d.spe_prenom_normalized
                AND e.spe_dateNaissance = d.spe_dateNaissance
                AND e.spe_communeNaissance = d.spe_communeNaissance
          );

        EXEC ctl.sp_log_metric @run_id, '03_match_spe_deterministic', @@ROWCOUNT, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_03_match_spe_deterministic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_04_match_spe_probabilistic_candidates') IS NOT NULL DROP PROCEDURE silver.sp_mm_04_match_spe_probabilistic_candidates;
GO
CREATE PROCEDURE silver.sp_mm_04_match_spe_probabilistic_candidates
    @run_id UNIQUEIDENTIFIER,
    @threshold FLOAT = 0.8
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM dq.spe_match_candidates WHERE run_id = @run_id;

        INSERT INTO dq.spe_match_candidates
        (
            run_id, id_ligne_declaration, candidate_spe_masterid, score_total,
            score_nom, score_prenom, score_dob, score_commune, created_at
        )
        SELECT @run_id, n.id_ligne_declaration, e.spe_masterid, score_total, score_nom, score_prenom, score_dob, score_commune, SYSUTCDATETIME()
        FROM stg.stg_spe_nonmatched n
        JOIN silver.v_spe_enriched_canon e
          ON e.blocking_year = n.blocking_year
         AND e.blocking_nom2 = n.blocking_nom2
         AND e.blocking_pre2 = n.blocking_pre2
         AND e.valid_to IS NULL
        CROSS APPLY (
            SELECT dq.fn_spe_score(n.spe_nom_normalized, e.spe_nom_normalized,
                                   n.spe_prenom_normalized, e.spe_prenom_normalized,
                                   n.spe_dateNaissance, e.spe_dateNaissance,
                                   n.spe_communeNaissance, e.spe_communeNaissance) AS score_total,
                   dq.fn_similarity(n.spe_nom_normalized, e.spe_nom_normalized) AS score_nom,
                   dq.fn_similarity(n.spe_prenom_normalized, e.spe_prenom_normalized) AS score_prenom,
                   dq.fn_date_similarity(n.spe_dateNaissance, e.spe_dateNaissance) AS score_dob,
                   dq.fn_similarity(n.spe_communeNaissance, e.spe_communeNaissance) AS score_commune
        ) s
        WHERE s.score_total >= @threshold;

        ;WITH agg AS (
            SELECT id_ligne_declaration,
                   COUNT(DISTINCT candidate_spe_masterid) AS candidate_cnt,
                   MAX(score_total) AS best_score
            FROM dq.spe_match_candidates
            WHERE run_id = @run_id
            GROUP BY id_ligne_declaration
        ),
        best AS (
            SELECT id_ligne_declaration, candidate_spe_masterid AS best_candidate, score_total AS best_score,
                   ROW_NUMBER() OVER (PARTITION BY id_ligne_declaration ORDER BY score_total DESC, candidate_spe_masterid) AS rn
            FROM dq.spe_match_candidates
            WHERE run_id = @run_id
        )
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_match_status = CASE WHEN a.candidate_cnt = 1 THEN 'Proba_One_Match_to_stewardship' ELSE 'Proba_Several_Match_to_stewardship' END,
            m.best_candidate_masterid = b.best_candidate,
            m.best_score = b.best_score,
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN agg a ON a.id_ligne_declaration = m.id_ligne_declaration
        JOIN best b ON b.id_ligne_declaration = m.id_ligne_declaration AND b.rn = 1;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_match_status, best_candidate_masterid, best_score, created_at, updated_at)
        SELECT a.id_ligne_declaration,
               CASE WHEN a.candidate_cnt = 1 THEN 'Proba_One_Match_to_stewardship' ELSE 'Proba_Several_Match_to_stewardship' END,
               b.best_candidate, b.best_score, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM agg a
        JOIN best b ON b.id_ligne_declaration = a.id_ligne_declaration AND b.rn = 1
        WHERE NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = a.id_ligne_declaration);

        EXEC ctl.sp_log_metric @run_id, '04_match_spe_probabilistic_candidates', @@ROWCOUNT, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_04_match_spe_probabilistic_candidates', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO
