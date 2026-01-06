SET NOCOUNT ON;
GO

PRINT 'Creating graph and connected components procedures...';
GO

IF OBJECT_ID('silver.sp_mm_05_build_intrarun_graph') IS NOT NULL DROP PROCEDURE silver.sp_mm_05_build_intrarun_graph;
GO
CREATE PROCEDURE silver.sp_mm_05_build_intrarun_graph
    @run_id UNIQUEIDENTIFIER,
    @threshold FLOAT = 0.8
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.spe_edges WHERE run_id = @run_id;
        DELETE FROM stg.spe_nodes WHERE run_id = @run_id;

        INSERT INTO stg.spe_nodes(run_id, node_id, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at)
        SELECT @run_id, id_ligne_declaration, id_ligne_declaration, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, created_at
        FROM stg.stg_spe_nonmatched
        WHERE run_id = @run_id;

        INSERT INTO stg.spe_edges(run_id, node_a, node_b, score_total, score_nom, score_prenom, score_dob, score_commune)
        SELECT @run_id, n1.node_id, n2.node_id, s.score_total, s.score_nom, s.score_prenom, s.score_dob, s.score_commune
        FROM stg.spe_nodes n1
        JOIN stg.spe_nodes n2
          ON n1.run_id = n2.run_id
         AND n1.blocking_year = n2.blocking_year
         AND n1.blocking_nom2 = n2.blocking_nom2
         AND n1.blocking_pre2 = n2.blocking_pre2
         AND n1.node_id < n2.node_id
        CROSS APPLY (
            SELECT dq.fn_spe_score(n1.spe_nom_normalized, n2.spe_nom_normalized,
                                   n1.spe_prenom_normalized, n2.spe_prenom_normalized,
                                   n1.spe_dateNaissance, n2.spe_dateNaissance,
                                   n1.spe_communeNaissance, n2.spe_communeNaissance) AS score_total,
                   dq.fn_similarity(n1.spe_nom_normalized, n2.spe_nom_normalized) AS score_nom,
                   dq.fn_similarity(n1.spe_prenom_normalized, n2.spe_prenom_normalized) AS score_prenom,
                   dq.fn_date_similarity(n1.spe_dateNaissance, n2.spe_dateNaissance) AS score_dob,
                   dq.fn_similarity(n1.spe_communeNaissance, n2.spe_communeNaissance) AS score_commune
        ) s
        WHERE n1.run_id = @run_id
          AND s.score_total >= @threshold;

        EXEC ctl.sp_log_metric @run_id, '05_build_intrarun_graph', @@ROWCOUNT, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_05_build_intrarun_graph', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_06_compute_connected_components') IS NOT NULL DROP PROCEDURE silver.sp_mm_06_compute_connected_components;
GO
CREATE PROCEDURE silver.sp_mm_06_compute_connected_components
    @run_id UNIQUEIDENTIFIER,
    @max_iter INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @iter INT = 0, @updated INT = 0, @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM stg.spe_components WHERE run_id = @run_id;

        INSERT INTO stg.spe_components(run_id, node_id, component_id, updated_at)
        SELECT @run_id, node_id, node_id, SYSUTCDATETIME()
        FROM stg.spe_nodes
        WHERE run_id = @run_id;

        WHILE 1 = 1
        BEGIN
            SET @iter += 1;
            IF @iter > @max_iter
            BEGIN
                RAISERROR('Maximum iterations reached in label propagation', 16, 1);
            END;

            IF OBJECT_ID('tempdb..#proposals') IS NOT NULL DROP TABLE #proposals;
            IF OBJECT_ID('tempdb..#new_comp') IS NOT NULL DROP TABLE #new_comp;

            SELECT p.node_id, MIN(p.proposed_component) AS proposed_component
            INTO #proposals
            FROM (
                SELECT node_a AS node_id, MIN(c_b.component_id) AS proposed_component
                FROM stg.spe_edges e
                JOIN stg.spe_components c_a ON c_a.run_id = e.run_id AND c_a.node_id = e.node_a
                JOIN stg.spe_components c_b ON c_b.run_id = e.run_id AND c_b.node_id = e.node_b
                WHERE e.run_id = @run_id
                GROUP BY node_a
                UNION ALL
                SELECT node_b AS node_id, MIN(c_a.component_id) AS proposed_component
                FROM stg.spe_edges e
                JOIN stg.spe_components c_a ON c_a.run_id = e.run_id AND c_a.node_id = e.node_a
                JOIN stg.spe_components c_b ON c_b.run_id = e.run_id AND c_b.node_id = e.node_b
                WHERE e.run_id = @run_id
                GROUP BY node_b
            ) p
            GROUP BY p.node_id;

            SELECT p.node_id, MIN(p.proposed_component) AS new_component
            INTO #new_comp
            FROM #proposals p
            GROUP BY p.node_id;

            UPDATE c
            SET component_id = nc.new_component,
                updated_at = SYSUTCDATETIME()
            FROM stg.spe_components c
            JOIN #new_comp nc ON nc.node_id = c.node_id
            WHERE c.run_id = @run_id
              AND nc.new_component < c.component_id;

            SET @updated = @@ROWCOUNT;
            IF @updated = 0 BREAK;
        END;

        EXEC ctl.sp_log_metric @run_id, '06_compute_connected_components', @iter, DATEDIFF(ms, @t0, SYSUTCDATETIME()), CONCAT('updates=', @updated);
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_06_compute_connected_components', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_07_new_spe_dedup_deterministic') IS NOT NULL DROP PROCEDURE silver.sp_mm_07_new_spe_dedup_deterministic;
GO
CREATE PROCEDURE silver.sp_mm_07_new_spe_dedup_deterministic
    @run_id UNIQUEIDENTIFIER,
    @status_created VARCHAR(20) = 'Created'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        ;WITH base AS (
            SELECT n.run_id, n.node_id, n.id_ligne_declaration, n.spe_nom_normalized, n.spe_prenom_normalized, n.spe_dateNaissance, n.spe_communeNaissance,
                   m.spe_masterid
            FROM stg.spe_nodes n
            LEFT JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = n.id_ligne_declaration
            WHERE n.run_id = @run_id
              AND (m.spe_masterid IS NULL)
        ),
        clusters AS (
            SELECT spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance,
                   COUNT(*) AS cnt
            FROM base
            GROUP BY spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance
            HAVING COUNT(*) > 1
        )
        SELECT b.node_id, b.id_ligne_declaration, b.spe_nom_normalized, b.spe_prenom_normalized, b.spe_dateNaissance, b.spe_communeNaissance,
               ROW_NUMBER() OVER (PARTITION BY b.spe_nom_normalized, b.spe_prenom_normalized, b.spe_dateNaissance, b.spe_communeNaissance ORDER BY b.node_id) AS rn,
               DENSE_RANK() OVER (ORDER BY b.spe_nom_normalized, b.spe_prenom_normalized, b.spe_dateNaissance, b.spe_communeNaissance) AS cluster_rank
        INTO #det_nodes
        FROM base b
        JOIN clusters c
          ON c.spe_nom_normalized = b.spe_nom_normalized
         AND c.spe_prenom_normalized = b.spe_prenom_normalized
         AND c.spe_dateNaissance = b.spe_dateNaissance
         AND c.spe_communeNaissance = b.spe_communeNaissance;

        IF EXISTS (SELECT 1 FROM #det_nodes)
        BEGIN
            SELECT DISTINCT cluster_rank, NEXT VALUE FOR mdm.seq_spe_masterid AS spe_masterid
            INTO #det_master
            FROM #det_nodes;

            UPDATE n
            SET spe_masterid = m.spe_masterid
            FROM stg.spe_nodes n
            JOIN #det_nodes d ON d.node_id = n.node_id
            JOIN #det_master m ON m.cluster_rank = d.cluster_rank;

            -- Upsert mapping
            UPDATE map WITH (HOLDLOCK)
            SET map.spe_masterid = dm.spe_masterid,
                map.spe_match_status = @status_created,
                map.updated_at = SYSUTCDATETIME()
            FROM silver.Silver_declaration_ref_mapping map
            JOIN stg.spe_nodes n ON n.id_ligne_declaration = map.id_ligne_declaration AND n.run_id = @run_id
            JOIN #det_master dm ON EXISTS (
                SELECT 1 FROM #det_nodes dn WHERE dn.node_id = n.node_id AND dn.cluster_rank = dm.cluster_rank
            );

            INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_masterid, spe_match_status, created_at, updated_at)
            SELECT n.id_ligne_declaration, dm.spe_masterid, @status_created, SYSUTCDATETIME(), SYSUTCDATETIME()
            FROM stg.spe_nodes n
            JOIN #det_nodes d ON d.node_id = n.node_id
            JOIN #det_master dm ON dm.cluster_rank = d.cluster_rank
            WHERE NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = n.id_ligne_declaration);

            -- Insert enriched formats
            INSERT INTO silver.Silver_spe_enriched(spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok, created_at)
            SELECT DISTINCT dm.spe_masterid, d.spe_nom_normalized, d.spe_prenom_normalized, d.spe_dateNaissance, d.spe_communeNaissance, NULL, SYSUTCDATETIME()
            FROM #det_nodes d
            JOIN #det_master dm ON dm.cluster_rank = d.cluster_rank
            WHERE NOT EXISTS (
                SELECT 1 FROM silver.Silver_spe_enriched e
                WHERE e.spe_masterid = dm.spe_masterid
                  AND e.spe_nom_normalized = d.spe_nom_normalized
                  AND e.spe_prenom_normalized = d.spe_prenom_normalized
                  AND e.spe_dateNaissance = d.spe_dateNaissance
                  AND e.spe_communeNaissance = d.spe_communeNaissance
            );
        END;

        EXEC ctl.sp_log_metric @run_id, '07_new_spe_dedup_deterministic', (SELECT COUNT(*) FROM #det_nodes), DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_07_new_spe_dedup_deterministic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO

IF OBJECT_ID('silver.sp_mm_08_new_spe_dedup_probabilistic') IS NOT NULL DROP PROCEDURE silver.sp_mm_08_new_spe_dedup_probabilistic;
GO
CREATE PROCEDURE silver.sp_mm_08_new_spe_dedup_probabilistic
    @run_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSUTCDATETIME();
    BEGIN TRY
        DELETE FROM dq.spe_match_candidates_intrarun WHERE run_id = @run_id;

        IF OBJECT_ID('tempdb..#node_map') IS NOT NULL DROP TABLE #node_map;
        SELECT n.run_id, n.node_id, n.id_ligne_declaration, ISNULL(m.spe_masterid, n.spe_masterid) AS spe_masterid, m.spe_match_status
        INTO #node_map
        FROM stg.spe_nodes n
        LEFT JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = n.id_ligne_declaration
        WHERE n.run_id = @run_id;

        IF OBJECT_ID('tempdb..#comp_info') IS NOT NULL DROP TABLE #comp_info;
        SELECT c.component_id,
               COUNT(*) AS node_count,
               COUNT(DISTINCT CASE WHEN nm.spe_masterid IS NOT NULL THEN nm.spe_masterid END) AS masterid_count,
               MIN(c.node_id) AS pivot_node
        INTO #comp_info
        FROM stg.spe_components c
        LEFT JOIN #node_map nm ON nm.node_id = c.node_id
        WHERE c.run_id = @run_id
        GROUP BY c.component_id;

        -- Case 3 & 4: components with no masterid anchors
        DECLARE @pivot_master TABLE(component_id BIGINT, pivot_node BIGINT, spe_masterid BIGINT);
        INSERT INTO @pivot_master(component_id, pivot_node, spe_masterid)
        SELECT ci.component_id, ci.pivot_node,
               CASE WHEN ci.node_count = 1 THEN NEXT VALUE FOR mdm.seq_spe_masterid ELSE NEXT VALUE FOR mdm.seq_spe_masterid END
        FROM #comp_info ci
        WHERE ci.masterid_count = 0;

        -- Apply pivot assignments
        UPDATE n
        SET n.spe_masterid = pm.spe_masterid
        FROM stg.spe_nodes n
        JOIN stg.spe_components c ON c.run_id = n.run_id AND c.node_id = n.node_id
        JOIN @pivot_master pm ON pm.component_id = c.component_id AND pm.pivot_node = n.node_id
        WHERE n.run_id = @run_id;

        UPDATE m WITH (HOLDLOCK)
        SET m.spe_masterid = pm.spe_masterid,
            m.spe_match_status = 'Matched',
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN stg.spe_nodes n ON n.id_ligne_declaration = m.id_ligne_declaration
        JOIN stg.spe_components c ON c.node_id = n.node_id AND c.run_id = n.run_id
        JOIN @pivot_master pm ON pm.component_id = c.component_id AND pm.pivot_node = n.node_id
        WHERE n.run_id = @run_id;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_masterid, spe_match_status, created_at, updated_at)
        SELECT n.id_ligne_declaration, pm.spe_masterid, 'Matched', SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM stg.spe_nodes n
        JOIN stg.spe_components c ON c.node_id = n.node_id AND c.run_id = n.run_id
        JOIN @pivot_master pm ON pm.component_id = c.component_id AND pm.pivot_node = n.node_id
        WHERE n.run_id = @run_id
          AND NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = n.id_ligne_declaration);

        INSERT INTO silver.Silver_spe_enriched(spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance, rnvp_ok, created_at)
        SELECT pm.spe_masterid, n.spe_nom_normalized, n.spe_prenom_normalized, n.spe_dateNaissance, n.spe_communeNaissance, NULL, SYSUTCDATETIME()
        FROM stg.spe_nodes n
        JOIN stg.spe_components c ON c.node_id = n.node_id AND c.run_id = n.run_id
        JOIN @pivot_master pm ON pm.component_id = c.component_id AND pm.pivot_node = n.node_id
        WHERE n.run_id = @run_id
          AND NOT EXISTS (
              SELECT 1 FROM silver.Silver_spe_enriched e
              WHERE e.spe_masterid = pm.spe_masterid
                AND e.spe_nom_normalized = n.spe_nom_normalized
                AND e.spe_prenom_normalized = n.spe_prenom_normalized
                AND e.spe_dateNaissance = n.spe_dateNaissance
                AND e.spe_communeNaissance = n.spe_communeNaissance
          );

        -- Rebuild node map after pivot
        DELETE FROM #node_map;
        INSERT INTO #node_map
        SELECT n.run_id, n.node_id, n.id_ligne_declaration, ISNULL(m.spe_masterid, n.spe_masterid) AS spe_masterid, ISNULL(m.spe_match_status, 'Unknown') AS spe_match_status
        FROM stg.spe_nodes n
        LEFT JOIN silver.Silver_declaration_ref_mapping m ON m.id_ligne_declaration = n.id_ligne_declaration
        WHERE n.run_id = @run_id;

        -- Case 1: masterid_count = 1, nodes without masterid go to Proba_One
        INSERT INTO dq.spe_match_candidates_intrarun(run_id, node_id, candidate_spe_masterid, score_total, created_at)
        SELECT DISTINCT @run_id, n.node_id, anchor.spe_masterid,
               ISNULL(e.score_total, 1.0) AS score_total, SYSUTCDATETIME()
        FROM #comp_info ci
        JOIN stg.spe_components c ON c.component_id = ci.component_id AND c.run_id = @run_id
        JOIN #node_map n ON n.node_id = c.node_id AND n.spe_masterid IS NULL
        CROSS APPLY (
            SELECT TOP 1 nm2.spe_masterid, e.score_total
            FROM stg.spe_components c2
            JOIN #node_map nm2 ON nm2.node_id = c2.node_id
            LEFT JOIN stg.spe_edges e ON e.run_id = @run_id AND ((e.node_a = n.node_id AND e.node_b = nm2.node_id) OR (e.node_b = n.node_id AND e.node_a = nm2.node_id))
            WHERE c2.component_id = ci.component_id AND nm2.spe_masterid IS NOT NULL
            ORDER BY e.score_total DESC, nm2.spe_masterid
        ) anchor
        WHERE ci.masterid_count = 1;

        ;WITH cand AS (
            SELECT c.node_id, c.candidate_spe_masterid, c.score_total, comp.component_id
            FROM dq.spe_match_candidates_intrarun c
            JOIN stg.spe_components comp ON comp.node_id = c.node_id AND comp.run_id = c.run_id
            JOIN #comp_info ci ON ci.component_id = comp.component_id AND ci.masterid_count = 1
            WHERE c.run_id = @run_id
        ),
        best_one AS (
            SELECT node_id, candidate_spe_masterid, score_total,
                   ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY score_total DESC, candidate_spe_masterid) AS rn
            FROM cand
        )
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_match_status = 'Proba_One_Match_to_stewardship',
            m.best_candidate_masterid = b.candidate_spe_masterid,
            m.best_score = b.score_total,
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN best_one b ON b.node_id = m.id_ligne_declaration AND b.rn = 1;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_match_status, best_candidate_masterid, best_score, created_at, updated_at)
        SELECT n.id_ligne_declaration, 'Proba_One_Match_to_stewardship', b.candidate_spe_masterid, b.score_total, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM stg.spe_nodes n
        JOIN best_one b ON b.node_id = n.node_id AND b.rn = 1
        WHERE NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = n.id_ligne_declaration);

        -- Case 2: masterid_count > 1
        INSERT INTO dq.spe_match_candidates_intrarun(run_id, node_id, candidate_spe_masterid, score_total, created_at)
        SELECT DISTINCT @run_id, n.node_id, nm2.spe_masterid,
               ISNULL(e.score_total, 0.8) AS score_total, SYSUTCDATETIME()
        FROM #comp_info ci
        JOIN stg.spe_components c ON c.component_id = ci.component_id AND c.run_id = @run_id
        JOIN #node_map n ON n.node_id = c.node_id AND n.spe_masterid IS NULL
        JOIN stg.spe_components c2 ON c2.component_id = ci.component_id AND c2.run_id = @run_id
        JOIN #node_map nm2 ON nm2.node_id = c2.node_id AND nm2.spe_masterid IS NOT NULL
        LEFT JOIN stg.spe_edges e ON e.run_id = @run_id AND ((e.node_a = n.node_id AND e.node_b = nm2.node_id) OR (e.node_b = n.node_id AND e.node_a = nm2.node_id))
        WHERE ci.masterid_count > 1;

        ;WITH cand AS (
            SELECT c.node_id, c.candidate_spe_masterid, c.score_total, comp.component_id
            FROM dq.spe_match_candidates_intrarun c
            JOIN stg.spe_components comp ON comp.node_id = c.node_id AND comp.run_id = c.run_id
            JOIN #comp_info ci ON ci.component_id = comp.component_id AND ci.masterid_count > 1
            WHERE c.run_id = @run_id
        ),
        best_several AS (
            SELECT node_id, candidate_spe_masterid, score_total,
                   ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY score_total DESC, candidate_spe_masterid) AS rn
            FROM cand
        )
        UPDATE m WITH (HOLDLOCK)
        SET m.spe_match_status = 'Proba_Several_Match_to_stewardship',
            m.best_candidate_masterid = b.candidate_spe_masterid,
            m.best_score = b.score_total,
            m.updated_at = SYSUTCDATETIME()
        FROM silver.Silver_declaration_ref_mapping m
        JOIN best_several b ON b.node_id = m.id_ligne_declaration AND b.rn = 1
        WHERE m.spe_masterid IS NULL;

        INSERT INTO silver.Silver_declaration_ref_mapping(id_ligne_declaration, spe_match_status, best_candidate_masterid, best_score, created_at, updated_at)
        SELECT DISTINCT n.id_ligne_declaration, 'Proba_Several_Match_to_stewardship', b.candidate_spe_masterid, b.score_total, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM stg.spe_nodes n
        JOIN best_several b ON b.node_id = n.node_id AND b.rn = 1
        WHERE NOT EXISTS (SELECT 1 FROM silver.Silver_declaration_ref_mapping m WITH (HOLDLOCK, UPDLOCK) WHERE m.id_ligne_declaration = n.id_ligne_declaration);

        EXEC ctl.sp_log_metric @run_id, '08_new_spe_dedup_probabilistic', @@ROWCOUNT, DATEDIFF(ms, @t0, SYSUTCDATETIME()), NULL;
    END TRY
    BEGIN CATCH
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_08_new_spe_dedup_probabilistic', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        THROW;
    END CATCH
END;
GO
