SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE mdm.sp_mm_09_merge_spe
    @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @last_ts datetime2(3) = (SELECT last_success_ts FROM ctl.merge_log WHERE label = 'spe');

    BEGIN TRY
        IF OBJECT_ID('tempdb..#impacted') IS NOT NULL DROP TABLE #impacted;
        SELECT DISTINCT m.spe_masterid
        INTO #impacted
        FROM mdm.declaration_ref_mapping m
        WHERE m.spe_masterid IS NOT NULL
          AND (m.updated_at > ISNULL(@last_ts, '1900-01-01'));

        IF OBJECT_ID('tempdb..#candidate') IS NOT NULL DROP TABLE #candidate;
        SELECT
            e.spe_masterid,
            e.spe_nom_normalized,
            e.spe_prenom_normalized,
            e.spe_dateNaissance,
            e.spe_communeNaissance,
            e.source_system,
            e.source,
            e.rnvp_score,
            e.created_at,
            ROW_NUMBER() OVER (
                PARTITION BY e.spe_masterid
                ORDER BY
                    CASE WHEN e.source_system = 'CRM' THEN 1 WHEN e.source_system = 'UCN' THEN 2 ELSE 3 END,
                    CASE WHEN e.rnvp_score = 1 THEN 1 ELSE 2 END,
                    CASE WHEN e.source = 'PAJEMPLOI' THEN 1 WHEN e.source = 'CESU' THEN 2 ELSE 3 END,
                    e.created_at DESC
            ) AS rn
        INTO #candidate
        FROM mdm.spe_enriched_format e
        INNER JOIN #impacted i
            ON i.spe_masterid = e.spe_masterid;

        IF OBJECT_ID('tempdb..#winning') IS NOT NULL DROP TABLE #winning;
        SELECT * INTO #winning FROM #candidate WHERE rn = 1;

        UPDATE cur
        SET cur.valid_to = SYSUTCDATETIME(),
            cur.is_current = 0
        FROM mdm.spe_master cur
        INNER JOIN #winning w
            ON w.spe_masterid = cur.spe_masterid
        WHERE cur.is_current = 1
          AND cur.row_hash <> HASHBYTES('SHA2_256', CONCAT_WS('|', w.spe_nom_normalized, w.spe_prenom_normalized, w.spe_dateNaissance, w.spe_communeNaissance, w.source_system, w.source, w.rnvp_score));

        INSERT INTO mdm.spe_master (
            spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, source_system, source, rnvp_score, valid_from, valid_to, is_current, row_hash
        )
        SELECT
            w.spe_masterid,
            w.spe_nom_normalized,
            w.spe_prenom_normalized,
            w.spe_dateNaissance,
            w.spe_communeNaissance,
            w.source_system,
            w.source,
            w.rnvp_score,
            SYSUTCDATETIME(),
            NULL,
            1,
            HASHBYTES('SHA2_256', CONCAT_WS('|', w.spe_nom_normalized, w.spe_prenom_normalized, w.spe_dateNaissance, w.spe_communeNaissance, w.source_system, w.source, w.rnvp_score))
        FROM #winning w
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.spe_master cur
            WHERE cur.spe_masterid = w.spe_masterid
              AND cur.is_current = 1
              AND cur.row_hash = HASHBYTES('SHA2_256', CONCAT_WS('|', w.spe_nom_normalized, w.spe_prenom_normalized, w.spe_dateNaissance, w.spe_communeNaissance, w.source_system, w.source, w.rnvp_score))
        );

        MERGE_LOG:
        IF EXISTS (SELECT 1 FROM ctl.merge_log WHERE label = 'spe')
            UPDATE ctl.merge_log SET last_success_ts = SYSUTCDATETIME() WHERE label = 'spe';
        ELSE
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES ('spe', SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_09_merge_spe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE mdm.sp_mm_10_merge_pe
    @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @last_ts datetime2(3) = (SELECT last_success_ts FROM ctl.merge_log WHERE label = 'pe');

    BEGIN TRY
        IF OBJECT_ID('tempdb..#impacted') IS NOT NULL DROP TABLE #impacted;
        SELECT DISTINCT m.pe_masterid
        INTO #impacted
        FROM mdm.declaration_ref_mapping m
        WHERE m.pe_masterid IS NOT NULL
          AND (m.updated_at > ISNULL(@last_ts, '1900-01-01'));

        IF OBJECT_ID('tempdb..#candidate') IS NOT NULL DROP TABLE #candidate;
        SELECT
            e.pe_masterid,
            e.pe_pseudoSiret,
            e.pe_nom_normalized,
            e.pe_commune,
            e.source_system,
            e.source,
            e.rnvp_score,
            e.created_at,
            ROW_NUMBER() OVER (
                PARTITION BY e.pe_masterid
                ORDER BY
                    CASE WHEN e.source_system = 'CRM' THEN 1 WHEN e.source_system = 'UCN' THEN 2 ELSE 3 END,
                    CASE WHEN e.rnvp_score = 1 THEN 1 ELSE 2 END,
                    CASE WHEN e.source = 'PAJEMPLOI' THEN 1 WHEN e.source = 'CESU' THEN 2 ELSE 3 END,
                    e.created_at DESC
            ) AS rn
        INTO #candidate
        FROM mdm.pe_enriched_format e
        INNER JOIN #impacted i
            ON i.pe_masterid = e.pe_masterid;

        IF OBJECT_ID('tempdb..#winning') IS NOT NULL DROP TABLE #winning;
        SELECT * INTO #winning FROM #candidate WHERE rn = 1;

        UPDATE cur
        SET cur.valid_to = SYSUTCDATETIME(),
            cur.is_current = 0
        FROM mdm.pe_master cur
        INNER JOIN #winning w
            ON w.pe_masterid = cur.pe_masterid
        WHERE cur.is_current = 1
          AND cur.row_hash <> HASHBYTES('SHA2_256', CONCAT_WS('|', w.pe_pseudoSiret, w.pe_nom_normalized, w.pe_commune, w.source_system, w.source, w.rnvp_score));

        INSERT INTO mdm.pe_master (
            pe_masterid, pe_pseudoSiret, pe_nom_normalized, pe_commune,
            source_system, source, rnvp_score, valid_from, valid_to, is_current, row_hash
        )
        SELECT
            w.pe_masterid,
            w.pe_pseudoSiret,
            w.pe_nom_normalized,
            w.pe_commune,
            w.source_system,
            w.source,
            w.rnvp_score,
            SYSUTCDATETIME(),
            NULL,
            1,
            HASHBYTES('SHA2_256', CONCAT_WS('|', w.pe_pseudoSiret, w.pe_nom_normalized, w.pe_commune, w.source_system, w.source, w.rnvp_score))
        FROM #winning w
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.pe_master cur
            WHERE cur.pe_masterid = w.pe_masterid
              AND cur.is_current = 1
              AND cur.row_hash = HASHBYTES('SHA2_256', CONCAT_WS('|', w.pe_pseudoSiret, w.pe_nom_normalized, w.pe_commune, w.source_system, w.source, w.rnvp_score))
        );

        IF EXISTS (SELECT 1 FROM ctl.merge_log WHERE label = 'pe')
            UPDATE ctl.merge_log SET last_success_ts = SYSUTCDATETIME() WHERE label = 'pe';
        ELSE
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES ('pe', SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_10_merge_pe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE mdm.sp_mm_11_merge_relation
    @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @last_ts datetime2(3) = (SELECT last_success_ts FROM ctl.merge_log WHERE label = 'relation');

    BEGIN TRY
        IF OBJECT_ID('tempdb..#relation_src') IS NOT NULL DROP TABLE #relation_src;
        SELECT
            sm.spe_masterid,
            pm.pe_masterid,
            s.employment_type,
            MIN(s.date_debut_prestation) AS date_debut_relation,
            MAX(s.date_debut_prestation) AS date_fin_relation
        INTO #relation_src
        FROM stg.stg_new_decl_spe s
        INNER JOIN mdm.declaration_ref_mapping sm
            ON sm.id_ligne_declaration = s.id_ligne_declaration
           AND sm.spe_match_status = 'Matched'
        INNER JOIN mdm.declaration_ref_mapping pm
            ON pm.id_ligne_declaration = s.id_ligne_declaration
           AND pm.pe_match_status = 'Matched'
        WHERE s.run_id = @run_id
        GROUP BY sm.spe_masterid, pm.pe_masterid, s.employment_type;

        UPDATE cur
        SET cur.valid_to = SYSUTCDATETIME(),
            cur.is_current = 0
        FROM mdm.Silver_master_relation cur
        INNER JOIN #relation_src r
            ON r.spe_masterid = cur.spe_masterid
           AND r.pe_masterid = cur.pe_masterid
        WHERE cur.is_current = 1
          AND cur.row_hash <> HASHBYTES('SHA2_256', CONCAT_WS('|', r.spe_masterid, r.pe_masterid, r.employment_type, r.date_debut_relation, r.date_fin_relation));

        INSERT INTO mdm.Silver_master_relation (
            spe_masterid, pe_masterid, employment_type, date_debut_relation, date_fin_relation,
            valid_from, valid_to, is_current, row_hash
        )
        SELECT
            r.spe_masterid,
            r.pe_masterid,
            r.employment_type,
            r.date_debut_relation,
            r.date_fin_relation,
            SYSUTCDATETIME(),
            NULL,
            1,
            HASHBYTES('SHA2_256', CONCAT_WS('|', r.spe_masterid, r.pe_masterid, r.employment_type, r.date_debut_relation, r.date_fin_relation))
        FROM #relation_src r
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.Silver_master_relation cur
            WHERE cur.spe_masterid = r.spe_masterid
              AND cur.pe_masterid = r.pe_masterid
              AND cur.is_current = 1
              AND cur.row_hash = HASHBYTES('SHA2_256', CONCAT_WS('|', r.spe_masterid, r.pe_masterid, r.employment_type, r.date_debut_relation, r.date_fin_relation))
        );

        IF EXISTS (SELECT 1 FROM ctl.merge_log WHERE label = 'relation')
            UPDATE ctl.merge_log SET last_success_ts = SYSUTCDATETIME() WHERE label = 'relation';
        ELSE
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES ('relation', SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_11_merge_relation', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO
