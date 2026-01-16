SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_05_build_intrarun_graph
    @run_id uniqueidentifier,
    @threshold float = 0.8
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start datetime2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.spe_nodes WHERE run_id = @run_id;
        DELETE FROM stg.spe_edges WHERE run_id = @run_id;

        INSERT INTO stg.spe_nodes (
            run_id, node_id, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, employment_type, date_debut_prestation, source_system, source, rnvp_score, created_at
        )
        SELECT
            s.run_id,
            s.id_ligne_declaration,
            s.spe_nom_normalized,
            s.spe_prenom_normalized,
            s.spe_dateNaissance,
            s.spe_communeNaissance,
            s.employment_type,
            s.date_debut_prestation,
            s.source_system,
            s.source,
            s.rnvp_score,
            s.created_at
        FROM stg.stg_spe_nonmatched s
        WHERE s.run_id = @run_id;

        INSERT INTO stg.spe_edges (
            run_id, node_a, node_b, score_total, score_nom, score_prenom, score_dob, score_commune
        )
        SELECT
            @run_id,
            a.node_id,
            b.node_id,
            dq.fn_spe_score(a.spe_nom_normalized, b.spe_nom_normalized, a.spe_prenom_normalized, b.spe_prenom_normalized,
                a.spe_dateNaissance, b.spe_dateNaissance, a.spe_communeNaissance, b.spe_communeNaissance) AS score_total,
            dq.fn_similarity(a.spe_nom_normalized, b.spe_nom_normalized) AS score_nom,
            dq.fn_similarity(a.spe_prenom_normalized, b.spe_prenom_normalized) AS score_prenom,
            dq.fn_date_similarity(a.spe_dateNaissance, b.spe_dateNaissance) AS score_dob,
            dq.fn_similarity(a.spe_communeNaissance, b.spe_communeNaissance) AS score_commune
        FROM stg.spe_nodes a
        INNER JOIN stg.spe_nodes b
            ON a.run_id = @run_id
           AND b.run_id = @run_id
           AND a.blocking_year = b.blocking_year
           AND a.blocking_nom2 = b.blocking_nom2
           AND a.blocking_pre2 = b.blocking_pre2
           AND a.node_id < b.node_id
        WHERE dq.fn_spe_score(a.spe_nom_normalized, b.spe_nom_normalized, a.spe_prenom_normalized, b.spe_prenom_normalized,
                a.spe_dateNaissance, b.spe_dateNaissance, a.spe_communeNaissance, b.spe_communeNaissance) >= @threshold;

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_05_build_intrarun_graph', @@ROWCOUNT, DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'build graph';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_05_build_intrarun_graph', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_06_compute_connected_components
    @run_id uniqueidentifier,
    @max_iter int = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @iter int = 0;
    DECLARE @rows int = 1;

    BEGIN TRY
        DELETE FROM stg.spe_components WHERE run_id = @run_id;

        INSERT INTO stg.spe_components (run_id, node_id, component_id)
        SELECT run_id, node_id, node_id
        FROM stg.spe_nodes
        WHERE run_id = @run_id;

        WHILE @rows > 0
        BEGIN
            SET @iter += 1;
            IF @iter > @max_iter
            BEGIN
                THROW 51000, 'Connected components: max iterations exceeded', 1;
            END;

            IF OBJECT_ID('tempdb..#proposals') IS NOT NULL DROP TABLE #proposals;
            CREATE TABLE #proposals (node_id bigint NOT NULL, proposed_component bigint NOT NULL);

            INSERT INTO #proposals (node_id, proposed_component)
            SELECT e.node_a, MIN(c.component_id)
            FROM stg.spe_edges e
            INNER JOIN stg.spe_components c
                ON c.run_id = e.run_id AND c.node_id = e.node_b
            WHERE e.run_id = @run_id
            GROUP BY e.node_a
            UNION ALL
            SELECT e.node_b, MIN(c.component_id)
            FROM stg.spe_edges e
            INNER JOIN stg.spe_components c
                ON c.run_id = e.run_id AND c.node_id = e.node_a
            WHERE e.run_id = @run_id
            GROUP BY e.node_b;

            IF OBJECT_ID('tempdb..#new_comp') IS NOT NULL DROP TABLE #new_comp;
            SELECT node_id, MIN(proposed_component) AS new_component
            INTO #new_comp
            FROM #proposals
            GROUP BY node_id;

            UPDATE c
            SET c.component_id = n.new_component,
                c.updated_at = SYSUTCDATETIME()
            FROM stg.spe_components c
            INNER JOIN #new_comp n
                ON n.node_id = c.node_id
            WHERE c.run_id = @run_id
              AND n.new_component < c.component_id;

            SET @rows = @@ROWCOUNT;
        END;

        EXEC ctl.sp_log_metric @run_id, 'sp_mm_06_compute_connected_components', @iter, NULL, 'iterations';
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_06_compute_connected_components', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_07_new_spe_dedup_deterministic
    @run_id uniqueidentifier,
    @status_created varchar(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF OBJECT_ID('tempdb..#clusters') IS NOT NULL DROP TABLE #clusters;
        SELECT
            s.spe_nom_normalized,
            s.spe_prenom_normalized,
            s.spe_dateNaissance,
            s.spe_communeNaissance,
            MIN(s.id_ligne_declaration) AS cluster_key
        INTO #clusters
        FROM stg.stg_spe_nonmatched s
        WHERE s.run_id = @run_id
        GROUP BY s.spe_nom_normalized, s.spe_prenom_normalized, s.spe_dateNaissance, s.spe_communeNaissance;

        IF OBJECT_ID('tempdb..#cluster_master') IS NOT NULL DROP TABLE #cluster_master;
        SELECT
            c.*, NEXT VALUE FOR mdm.seq_spe_masterid AS spe_masterid
        INTO #cluster_master
        FROM #clusters c;

        UPDATE m
        SET m.spe_masterid = cm.spe_masterid,
            m.spe_match_status = @status_created,
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.stg_spe_nonmatched s
            ON s.run_id = @run_id AND s.id_ligne_declaration = m.id_ligne_declaration
        INNER JOIN #cluster_master cm
            ON cm.spe_nom_normalized = s.spe_nom_normalized
           AND cm.spe_prenom_normalized = s.spe_prenom_normalized
           AND cm.spe_dateNaissance = s.spe_dateNaissance
           AND cm.spe_communeNaissance = s.spe_communeNaissance
        WHERE m.spe_masterid IS NULL;

        INSERT INTO mdm.declaration_ref_mapping (
            id_ligne_declaration, spe_masterid, spe_match_status, run_id
        )
        SELECT
            s.id_ligne_declaration,
            cm.spe_masterid,
            @status_created,
            @run_id
        FROM stg.stg_spe_nonmatched s
        INNER JOIN #cluster_master cm
            ON cm.spe_nom_normalized = s.spe_nom_normalized
           AND cm.spe_prenom_normalized = s.spe_prenom_normalized
           AND cm.spe_dateNaissance = s.spe_dateNaissance
           AND cm.spe_communeNaissance = s.spe_communeNaissance
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
            cm.spe_masterid,
            s.spe_nom_normalized,
            s.spe_prenom_normalized,
            s.spe_dateNaissance,
            s.spe_communeNaissance,
            s.source_system,
            s.source,
            s.rnvp_score,
            s.created_at
        FROM stg.stg_spe_nonmatched s
        INNER JOIN #cluster_master cm
            ON cm.spe_nom_normalized = s.spe_nom_normalized
           AND cm.spe_prenom_normalized = s.spe_prenom_normalized
           AND cm.spe_dateNaissance = s.spe_dateNaissance
           AND cm.spe_communeNaissance = s.spe_communeNaissance
        WHERE s.run_id = @run_id
          AND NOT EXISTS (
            SELECT 1 FROM mdm.spe_enriched_format f
            WHERE f.spe_masterid = cm.spe_masterid
              AND f.spe_nom_normalized = s.spe_nom_normalized
              AND f.spe_prenom_normalized = s.spe_prenom_normalized
              AND f.spe_dateNaissance = s.spe_dateNaissance
              AND f.spe_communeNaissance = s.spe_communeNaissance
          );
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_07_new_spe_dedup_deterministic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE silver.sp_mm_08_new_spe_dedup_probabilistic
    @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DELETE FROM dq.spe_match_candidates_intrarun WHERE run_id = @run_id;

        IF OBJECT_ID('tempdb..#comp_stats') IS NOT NULL DROP TABLE #comp_stats;
        SELECT
            c.component_id,
            COUNT(*) AS node_count,
            COUNT(DISTINCT m.spe_masterid) AS masterid_count
        INTO #comp_stats
        FROM stg.spe_components c
        LEFT JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = c.node_id
        WHERE c.run_id = @run_id
        GROUP BY c.component_id;

        IF OBJECT_ID('tempdb..#anchors') IS NOT NULL DROP TABLE #anchors;
        SELECT
            c.component_id,
            m.spe_masterid,
            c.node_id
        INTO #anchors
        FROM stg.spe_components c
        INNER JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = c.node_id
        WHERE c.run_id = @run_id
          AND m.spe_masterid IS NOT NULL;

        -- Case masterid_count = 1
        INSERT INTO dq.spe_match_candidates_intrarun (
            run_id, node_id, candidate_spe_masterid, score_total, score_nom, score_prenom, score_dob, score_commune
        )
        SELECT
            @run_id,
            c.node_id,
            a.spe_masterid,
            MAX(e.score_total) AS score_total,
            MAX(e.score_nom) AS score_nom,
            MAX(e.score_prenom) AS score_prenom,
            MAX(e.score_dob) AS score_dob,
            MAX(e.score_commune) AS score_commune
        FROM stg.spe_components c
        INNER JOIN #comp_stats cs
            ON cs.component_id = c.component_id AND cs.masterid_count = 1
        INNER JOIN #anchors a
            ON a.component_id = c.component_id
        LEFT JOIN stg.spe_edges e
            ON e.run_id = @run_id
           AND ((e.node_a = c.node_id AND e.node_b = a.node_id) OR (e.node_b = c.node_id AND e.node_a = a.node_id))
        LEFT JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = c.node_id
        WHERE c.run_id = @run_id
          AND m.spe_masterid IS NULL
        GROUP BY c.node_id, a.spe_masterid;

        UPDATE m
        SET m.spe_match_status = 'Proba_One_Match_to_stewardship',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.spe_components c
            ON c.run_id = @run_id AND c.node_id = m.id_ligne_declaration
        INNER JOIN #comp_stats cs
            ON cs.component_id = c.component_id AND cs.masterid_count = 1
        WHERE m.spe_masterid IS NULL;

        -- Case masterid_count > 1
        INSERT INTO dq.spe_match_candidates_intrarun (
            run_id, node_id, candidate_spe_masterid, score_total, score_nom, score_prenom, score_dob, score_commune
        )
        SELECT
            @run_id,
            c.node_id,
            a.spe_masterid,
            MAX(e.score_total) AS score_total,
            MAX(e.score_nom) AS score_nom,
            MAX(e.score_prenom) AS score_prenom,
            MAX(e.score_dob) AS score_dob,
            MAX(e.score_commune) AS score_commune
        FROM stg.spe_components c
        INNER JOIN #comp_stats cs
            ON cs.component_id = c.component_id AND cs.masterid_count > 1
        INNER JOIN #anchors a
            ON a.component_id = c.component_id
        LEFT JOIN stg.spe_edges e
            ON e.run_id = @run_id
           AND ((e.node_a = c.node_id AND e.node_b = a.node_id) OR (e.node_b = c.node_id AND e.node_a = a.node_id))
        LEFT JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = c.node_id
        WHERE c.run_id = @run_id
          AND m.spe_masterid IS NULL
        GROUP BY c.node_id, a.spe_masterid;

        UPDATE m
        SET m.spe_match_status = 'Proba_Several_Match_to_stewardship',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.spe_components c
            ON c.run_id = @run_id AND c.node_id = m.id_ligne_declaration
        INNER JOIN #comp_stats cs
            ON cs.component_id = c.component_id AND cs.masterid_count > 1
        WHERE m.spe_masterid IS NULL;

        -- Case masterid_count = 0: pivot is MIN(node_id)
        IF OBJECT_ID('tempdb..#proba_only') IS NOT NULL DROP TABLE #proba_only;
        SELECT
            c.component_id,
            MIN(c.node_id) AS pivot_node_id
        INTO #proba_only
        FROM stg.spe_components c
        INNER JOIN #comp_stats cs
            ON cs.component_id = c.component_id AND cs.masterid_count = 0
        WHERE c.run_id = @run_id
        GROUP BY c.component_id;

        IF OBJECT_ID('tempdb..#pivot_master') IS NOT NULL DROP TABLE #pivot_master;
        SELECT p.*, NEXT VALUE FOR mdm.seq_spe_masterid AS spe_masterid
        INTO #pivot_master
        FROM #proba_only p;

        UPDATE m
        SET m.spe_masterid = pm.spe_masterid,
            m.spe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN #pivot_master pm
            ON pm.pivot_node_id = m.id_ligne_declaration
        WHERE m.spe_masterid IS NULL;

        INSERT INTO mdm.declaration_ref_mapping (id_ligne_declaration, spe_masterid, spe_match_status, run_id)
        SELECT pm.pivot_node_id, pm.spe_masterid, 'Matched', @run_id
        FROM #pivot_master pm
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK)
            WHERE m.id_ligne_declaration = pm.pivot_node_id
        );

        INSERT INTO mdm.spe_enriched_format (
            spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, source_system, source, rnvp_score, created_at
        )
        SELECT
            pm.spe_masterid,
            n.spe_nom_normalized,
            n.spe_prenom_normalized,
            n.spe_dateNaissance,
            n.spe_communeNaissance,
            n.source_system,
            n.source,
            n.rnvp_score,
            n.created_at
        FROM #pivot_master pm
        INNER JOIN stg.spe_nodes n
            ON n.run_id = @run_id AND n.node_id = pm.pivot_node_id
        WHERE NOT EXISTS (
            SELECT 1 FROM mdm.spe_enriched_format f
            WHERE f.spe_masterid = pm.spe_masterid
              AND f.spe_nom_normalized = n.spe_nom_normalized
              AND f.spe_prenom_normalized = n.spe_prenom_normalized
              AND f.spe_dateNaissance = n.spe_dateNaissance
              AND f.spe_communeNaissance = n.spe_communeNaissance
        );

        INSERT INTO dq.spe_match_candidates_intrarun (
            run_id, node_id, candidate_spe_masterid, score_total, score_nom, score_prenom, score_dob, score_commune
        )
        SELECT
            @run_id,
            c.node_id,
            pm.spe_masterid,
            MAX(e.score_total) AS score_total,
            MAX(e.score_nom) AS score_nom,
            MAX(e.score_prenom) AS score_prenom,
            MAX(e.score_dob) AS score_dob,
            MAX(e.score_commune) AS score_commune
        FROM stg.spe_components c
        INNER JOIN #pivot_master pm
            ON pm.component_id = c.component_id
        LEFT JOIN stg.spe_edges e
            ON e.run_id = @run_id
           AND ((e.node_a = c.node_id AND e.node_b = pm.pivot_node_id) OR (e.node_b = c.node_id AND e.node_a = pm.pivot_node_id))
        LEFT JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = c.node_id
        WHERE c.run_id = @run_id
          AND c.node_id <> pm.pivot_node_id
          AND m.spe_masterid IS NULL
        GROUP BY c.node_id, pm.spe_masterid;

        UPDATE m
        SET m.spe_match_status = 'Proba_One_Match_to_stewardship',
            m.updated_at = SYSUTCDATETIME(),
            m.run_id = @run_id
        FROM mdm.declaration_ref_mapping m
        INNER JOIN stg.spe_components c
            ON c.run_id = @run_id AND c.node_id = m.id_ligne_declaration
        INNER JOIN #pivot_master pm
            ON pm.component_id = c.component_id
        WHERE m.spe_masterid IS NULL;

        -- Case isolated nodes (no edges, no masterid): create master
        INSERT INTO mdm.declaration_ref_mapping (id_ligne_declaration, spe_masterid, spe_match_status, run_id)
        SELECT
            n.node_id,
            NEXT VALUE FOR mdm.seq_spe_masterid,
            'Matched',
            @run_id
        FROM stg.spe_nodes n
        LEFT JOIN stg.spe_edges e
            ON e.run_id = @run_id AND (e.node_a = n.node_id OR e.node_b = n.node_id)
        LEFT JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = n.node_id
        WHERE n.run_id = @run_id
          AND e.node_a IS NULL
          AND m.spe_masterid IS NULL;

        INSERT INTO mdm.spe_enriched_format (
            spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance,
            spe_communeNaissance, source_system, source, rnvp_score, created_at
        )
        SELECT
            m.spe_masterid,
            n.spe_nom_normalized,
            n.spe_prenom_normalized,
            n.spe_dateNaissance,
            n.spe_communeNaissance,
            n.source_system,
            n.source,
            n.rnvp_score,
            n.created_at
        FROM stg.spe_nodes n
        INNER JOIN mdm.declaration_ref_mapping m
            ON m.id_ligne_declaration = n.node_id
        LEFT JOIN stg.spe_edges e
            ON e.run_id = @run_id AND (e.node_a = n.node_id OR e.node_b = n.node_id)
        WHERE n.run_id = @run_id
          AND e.node_a IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM mdm.spe_enriched_format f
            WHERE f.spe_masterid = m.spe_masterid
              AND f.spe_nom_normalized = n.spe_nom_normalized
              AND f.spe_prenom_normalized = n.spe_prenom_normalized
              AND f.spe_dateNaissance = n.spe_dateNaissance
              AND f.spe_communeNaissance = n.spe_communeNaissance
          );
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_08_new_spe_dedup_probabilistic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH;
END;
GO
