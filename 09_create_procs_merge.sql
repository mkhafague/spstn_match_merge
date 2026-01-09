SET NOCOUNT ON;
GO

PRINT 'Creating merge (SCD2) stored procedures...';
GO

IF OBJECT_ID('mdm.sp_mm_09_merge_spe') IS NOT NULL DROP PROCEDURE mdm.sp_mm_09_merge_spe;
GO
CREATE PROCEDURE mdm.sp_mm_09_merge_spe
    @run_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME(), @last_ts DATETIME2(3);
    SELECT @last_ts = last_success_ts FROM ctl.merge_log WHERE label = 'merge_spe';

    BEGIN TRY
        ;WITH src AS (
            SELECT DISTINCT m.spe_masterid,
                            s.spe_nom_normalized, s.spe_prenom_normalized, s.spe_dateNaissance, s.spe_communeNaissance,
                            CAST(NULL AS BIT) AS rnvp_ok,
                            SYSUTCDATETIME() AS ref_ts
            FROM stg.stg_new_decl_spe s
            JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = s.id_ligne_declaration
            WHERE s.run_id = @run_id AND m.spe_match_status = 'Matched'
              AND m.spe_masterid IS NOT NULL
              AND ( @last_ts IS NULL OR s.created_at >= @last_ts )
        ),
        hashed AS (
            SELECT spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok,
                   HASHBYTES('SHA2_256', CONCAT_WS('|', spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok)) AS row_hash,
                   ref_ts
            FROM src
        )
        SELECT * INTO #spe_src FROM hashed;

        UPDATE tgt WITH (HOLDLOCK)
        SET valid_to = SYSUTCDATETIME(), is_current = 0, updated_at = SYSUTCDATETIME()
        FROM mdm.Silver_master_spe tgt
        JOIN #spe_src src ON src.spe_masterid = tgt.spe_masterid
        WHERE tgt.is_current = 1 AND tgt.row_hash <> src.row_hash;

        INSERT INTO mdm.Silver_master_spe(spe_masterid, valid_from, valid_to, is_current, source_system, spe_nom, spe_prenom, spe_dateNaissance, spe_communeNaissance, rnvp_ok, row_hash)
        SELECT src.spe_masterid, SYSUTCDATETIME(), NULL, 1, 'SILVER', src.spe_nom_normalized, src.spe_prenom_normalized, src.spe_dateNaissance, src.spe_communeNaissance, src.rnvp_ok, src.row_hash
        FROM #spe_src src
        LEFT JOIN mdm.Silver_master_spe cur ON cur.spe_masterid = src.spe_masterid AND cur.is_current = 1
        WHERE cur.spe_masterid IS NULL OR cur.row_hash <> src.row_hash;

        UPDATE ctl.merge_log WITH (HOLDLOCK)
        SET last_success_ts = SYSUTCDATETIME()
        WHERE label = 'merge_spe';
        IF @@ROWCOUNT = 0
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES('merge_spe', SYSUTCDATETIME());

        EXEC ctl.sp_log_metric @run_id, '09_merge_spe', (SELECT COUNT(*) FROM #spe_src), DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_09_merge_spe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('mdm.sp_mm_10_merge_pe') IS NOT NULL DROP PROCEDURE mdm.sp_mm_10_merge_pe;
GO
CREATE PROCEDURE mdm.sp_mm_10_merge_pe
    @run_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME(), @last_ts DATETIME2(3);
    SELECT @last_ts = last_success_ts FROM ctl.merge_log WHERE label = 'merge_pe';

    BEGIN TRY
        ;WITH src AS (
            SELECT DISTINCT m.pe_masterid, p.pseudo_siret, CAST(NULL AS BIT) AS rnvp_ok
            FROM stg.stg_new_decl_pe p
            JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = p.id_ligne_declaration
            WHERE p.run_id = @run_id AND m.pe_match_status = 'Matched'
              AND m.pe_masterid IS NOT NULL
              AND ( @last_ts IS NULL OR p.created_at >= @last_ts )
        ),
        hashed AS (
            SELECT pe_masterid, pseudo_siret, rnvp_ok,
                   HASHBYTES('SHA2_256', CONCAT_WS('|', pseudo_siret, rnvp_ok)) AS row_hash
            FROM src
        )
        SELECT * INTO #pe_src FROM hashed;

        UPDATE tgt WITH (HOLDLOCK)
        SET valid_to = SYSUTCDATETIME(), is_current = 0, updated_at = SYSUTCDATETIME()
        FROM mdm.Silver_master_pe tgt
        JOIN #pe_src src ON src.pe_masterid = tgt.pe_masterid
        WHERE tgt.is_current = 1 AND tgt.row_hash <> src.row_hash;

        INSERT INTO mdm.Silver_master_pe(pe_masterid, valid_from, valid_to, is_current, source_system, pseudo_siret, rnvp_ok, row_hash)
        SELECT src.pe_masterid, SYSUTCDATETIME(), NULL, 1, 'SILVER', src.pseudo_siret, src.rnvp_ok, src.row_hash
        FROM #pe_src src
        LEFT JOIN mdm.Silver_master_pe cur ON cur.pe_masterid = src.pe_masterid AND cur.is_current = 1
        WHERE cur.pe_masterid IS NULL OR cur.row_hash <> src.row_hash;

        UPDATE ctl.merge_log WITH (HOLDLOCK)
        SET last_success_ts = SYSUTCDATETIME()
        WHERE label = 'merge_pe';
        IF @@ROWCOUNT = 0
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES('merge_pe', SYSUTCDATETIME());

        EXEC ctl.sp_log_metric @run_id, '10_merge_pe', (SELECT COUNT(*) FROM #pe_src), DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_10_merge_pe', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('mdm.sp_mm_11_merge_relation') IS NOT NULL DROP PROCEDURE mdm.sp_mm_11_merge_relation;
GO
CREATE PROCEDURE mdm.sp_mm_11_merge_relation
    @run_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME(), @last_ts DATETIME2(3);
    SELECT @last_ts = last_success_ts FROM ctl.merge_log WHERE label = 'merge_relation';

    BEGIN TRY
        ;WITH rel AS (
            SELECT s.id_ligne_declaration, s.spe_dateNaissance, s.created_at,
                   m.spe_masterid, mp.pe_masterid,
                   CAST(NULL AS NVARCHAR(50)) AS employment_type,
                   CAST(NULL AS DATE) AS date_debut_prestation
            FROM stg.stg_new_decl_spe s
            JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = s.id_ligne_declaration AND m.spe_match_status = 'Matched'
            JOIN silver.Silver_declaration_ref_mapping mp ON mp.id_ligne_declaration = s.id_ligne_declaration AND mp.pe_match_status = 'Matched'
            WHERE s.run_id = @run_id
              AND ( @last_ts IS NULL OR s.created_at >= @last_ts )
        ),
        agg AS (
            SELECT spe_masterid, pe_masterid, employment_type,
                   MIN(date_debut_prestation) AS date_debut_relation,
                   MAX(date_debut_prestation) AS date_fin_relation
            FROM rel
            GROUP BY spe_masterid, pe_masterid, employment_type
        ),
        hashed AS (
            SELECT spe_masterid, pe_masterid, employment_type, date_debut_relation, date_fin_relation,
                   HASHBYTES('SHA2_256', CONCAT_WS('|', employment_type, date_debut_relation, date_fin_relation)) AS row_hash
            FROM agg
        )
        SELECT * INTO #rel_src FROM hashed;

        UPDATE tgt WITH (HOLDLOCK)
        SET valid_to = SYSUTCDATETIME(), is_current = 0, updated_at = SYSUTCDATETIME()
        FROM mdm.Silver_master_relation tgt
        JOIN #rel_src src ON src.spe_masterid = tgt.spe_masterid AND src.pe_masterid = tgt.pe_masterid AND ISNULL(src.employment_type,'') = ISNULL(tgt.employment_type,'')
        WHERE tgt.is_current = 1 AND tgt.row_hash <> src.row_hash;

        INSERT INTO mdm.Silver_master_relation(spe_masterid, pe_masterid, employment_type, valid_from, valid_to, is_current, date_debut_relation, date_fin_relation, row_hash)
        SELECT src.spe_masterid, src.pe_masterid, src.employment_type, SYSUTCDATETIME(), NULL, 1, src.date_debut_relation, src.date_fin_relation, src.row_hash
        FROM #rel_src src
        LEFT JOIN mdm.Silver_master_relation cur ON cur.spe_masterid = src.spe_masterid AND cur.pe_masterid = src.pe_masterid AND ISNULL(cur.employment_type,'') = ISNULL(src.employment_type,'') AND cur.is_current = 1
        WHERE cur.spe_masterid IS NULL OR cur.row_hash <> src.row_hash;

        UPDATE ctl.merge_log WITH (HOLDLOCK)
        SET last_success_ts = SYSUTCDATETIME()
        WHERE label = 'merge_relation';
        IF @@ROWCOUNT = 0
            INSERT INTO ctl.merge_log(label, last_success_ts) VALUES('merge_relation', SYSUTCDATETIME());

        EXEC ctl.sp_log_metric @run_id, '11_merge_relation', (SELECT COUNT(*) FROM #rel_src), DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_11_merge_relation', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO
