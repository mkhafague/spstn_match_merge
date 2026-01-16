SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ctl
IF OBJECT_ID('ctl.process_run','U') IS NULL
BEGIN
    CREATE TABLE ctl.process_run (
        run_id uniqueidentifier NOT NULL PRIMARY KEY,
        process_name sysname NOT NULL,
        start_ts datetime2(3) NOT NULL,
        end_ts datetime2(3) NULL,
        status varchar(20) NOT NULL,
        error_message nvarchar(4000) NULL,
        host_name sysname NULL,
        executed_by sysname NULL
    );
END;

IF OBJECT_ID('ctl.process_metrics','U') IS NULL
BEGIN
    CREATE TABLE ctl.process_metrics (
        run_id uniqueidentifier NOT NULL,
        step_name sysname NOT NULL,
        row_count bigint NULL,
        duration_ms bigint NULL,
        comment nvarchar(1000) NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_process_metrics_created_at DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('ctl.process_error','U') IS NULL
BEGIN
    CREATE TABLE ctl.process_error (
        run_id uniqueidentifier NULL,
        step_name sysname NULL,
        error_number int NULL,
        error_message nvarchar(4000) NULL,
        error_line int NULL,
        error_procedure sysname NULL,
        error_ts datetime2(3) NOT NULL CONSTRAINT DF_process_error_error_ts DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('ctl.merge_log','U') IS NULL
BEGIN
    CREATE TABLE ctl.merge_log (
        label sysname NOT NULL PRIMARY KEY,
        last_success_ts datetime2(3) NULL
    );
END;

-- stg
IF OBJECT_ID('stg.stg_new_decl_spe','U') IS NULL
BEGIN
    CREATE TABLE stg.stg_new_decl_spe (
        run_id uniqueidentifier NOT NULL,
        id_ligne_declaration bigint NOT NULL,
        spe_nom_normalized nvarchar(200) NULL,
        spe_prenom_normalized nvarchar(200) NULL,
        spe_dateNaissance date NULL,
        spe_communeNaissance nvarchar(200) NULL,
        spe_pseudoSiret nvarchar(50) NULL,
        employment_type nvarchar(50) NULL,
        date_debut_prestation date NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_stg_new_decl_spe_created_at DEFAULT SYSUTCDATETIME(),
        blocking_year AS (YEAR(spe_dateNaissance)) PERSISTED,
        blocking_nom2 AS (LEFT(spe_nom_normalized,2)) PERSISTED,
        blocking_pre2 AS (LEFT(spe_prenom_normalized,2)) PERSISTED,
        CONSTRAINT PK_stg_new_decl_spe PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;

IF OBJECT_ID('stg.stg_new_decl_pe','U') IS NULL
BEGIN
    CREATE TABLE stg.stg_new_decl_pe (
        run_id uniqueidentifier NOT NULL,
        id_ligne_declaration bigint NOT NULL,
        pe_pseudoSiret nvarchar(50) NULL,
        pe_nom_normalized nvarchar(200) NULL,
        pe_commune nvarchar(200) NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_stg_new_decl_pe_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_stg_new_decl_pe PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;

IF OBJECT_ID('stg.stg_spe_nonmatched','U') IS NULL
BEGIN
    CREATE TABLE stg.stg_spe_nonmatched (
        run_id uniqueidentifier NOT NULL,
        id_ligne_declaration bigint NOT NULL,
        spe_nom_normalized nvarchar(200) NULL,
        spe_prenom_normalized nvarchar(200) NULL,
        spe_dateNaissance date NULL,
        spe_communeNaissance nvarchar(200) NULL,
        employment_type nvarchar(50) NULL,
        date_debut_prestation date NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_stg_spe_nonmatched_created_at DEFAULT SYSUTCDATETIME(),
        blocking_year AS (YEAR(spe_dateNaissance)) PERSISTED,
        blocking_nom2 AS (LEFT(spe_nom_normalized,2)) PERSISTED,
        blocking_pre2 AS (LEFT(spe_prenom_normalized,2)) PERSISTED,
        CONSTRAINT PK_stg_spe_nonmatched PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;

IF OBJECT_ID('stg.spe_nodes','U') IS NULL
BEGIN
    CREATE TABLE stg.spe_nodes (
        run_id uniqueidentifier NOT NULL,
        node_id bigint NOT NULL,
        spe_nom_normalized nvarchar(200) NULL,
        spe_prenom_normalized nvarchar(200) NULL,
        spe_dateNaissance date NULL,
        spe_communeNaissance nvarchar(200) NULL,
        employment_type nvarchar(50) NULL,
        date_debut_prestation date NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_nodes_created_at DEFAULT SYSUTCDATETIME(),
        blocking_year AS (YEAR(spe_dateNaissance)) PERSISTED,
        blocking_nom2 AS (LEFT(spe_nom_normalized,2)) PERSISTED,
        blocking_pre2 AS (LEFT(spe_prenom_normalized,2)) PERSISTED,
        CONSTRAINT PK_spe_nodes PRIMARY KEY (run_id, node_id)
    );
END;

IF OBJECT_ID('stg.spe_edges','U') IS NULL
BEGIN
    CREATE TABLE stg.spe_edges (
        run_id uniqueidentifier NOT NULL,
        node_a bigint NOT NULL,
        node_b bigint NOT NULL,
        score_total float NULL,
        score_nom float NULL,
        score_prenom float NULL,
        score_dob float NULL,
        score_commune float NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_edges_created_at DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('stg.spe_components','U') IS NULL
BEGIN
    CREATE TABLE stg.spe_components (
        run_id uniqueidentifier NOT NULL,
        node_id bigint NOT NULL,
        component_id bigint NOT NULL,
        updated_at datetime2(3) NOT NULL CONSTRAINT DF_spe_components_updated_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_spe_components PRIMARY KEY (run_id, node_id)
    );
END;

-- dq
IF OBJECT_ID('dq.spe_match_candidates','U') IS NULL
BEGIN
    CREATE TABLE dq.spe_match_candidates (
        run_id uniqueidentifier NOT NULL,
        id_ligne_declaration bigint NOT NULL,
        candidate_spe_masterid bigint NOT NULL,
        score_total float NULL,
        score_nom float NULL,
        score_prenom float NULL,
        score_dob float NULL,
        score_commune float NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_match_candidates_created_at DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('dq.spe_match_candidates_intrarun','U') IS NULL
BEGIN
    CREATE TABLE dq.spe_match_candidates_intrarun (
        run_id uniqueidentifier NOT NULL,
        node_id bigint NOT NULL,
        candidate_spe_masterid bigint NOT NULL,
        score_total float NULL,
        score_nom float NULL,
        score_prenom float NULL,
        score_dob float NULL,
        score_commune float NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_match_candidates_intrarun_created_at DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('dq.spe_stewardship_decision','U') IS NULL
BEGIN
    CREATE TABLE dq.spe_stewardship_decision (
        decision_id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_id uniqueidentifier NULL,
        id_ligne_declaration bigint NOT NULL,
        decision_status varchar(20) NOT NULL,
        chosen_spe_masterid bigint NULL,
        decided_by sysname NULL,
        decided_at datetime2(3) NULL,
        comment nvarchar(1000) NULL
    );
END;

-- mdm
IF OBJECT_ID('mdm.declaration_ref_mapping','U') IS NULL
BEGIN
    CREATE TABLE mdm.declaration_ref_mapping (
        id_ligne_declaration bigint NOT NULL PRIMARY KEY,
        spe_masterid bigint NULL,
        pe_masterid bigint NULL,
        spe_match_status varchar(50) NULL,
        pe_match_status varchar(50) NULL,
        best_candidate_masterid bigint NULL,
        best_candidate_score float NULL,
        run_id uniqueidentifier NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_declaration_ref_mapping_created_at DEFAULT SYSUTCDATETIME(),
        updated_at datetime2(3) NOT NULL CONSTRAINT DF_declaration_ref_mapping_updated_at DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('mdm.spe_enriched_format','U') IS NULL
BEGIN
    CREATE TABLE mdm.spe_enriched_format (
        spe_masterid bigint NOT NULL,
        spe_nom_normalized nvarchar(200) NULL,
        spe_prenom_normalized nvarchar(200) NULL,
        spe_dateNaissance date NULL,
        spe_communeNaissance nvarchar(200) NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_enriched_format_created_at DEFAULT SYSUTCDATETIME(),
        blocking_year AS (YEAR(spe_dateNaissance)) PERSISTED,
        blocking_nom2 AS (LEFT(spe_nom_normalized,2)) PERSISTED,
        blocking_pre2 AS (LEFT(spe_prenom_normalized,2)) PERSISTED,
        CONSTRAINT PK_spe_enriched_format PRIMARY KEY (spe_masterid, spe_nom_normalized, spe_prenom_normalized, spe_dateNaissance, spe_communeNaissance)
    );
END;

IF OBJECT_ID('mdm.pe_enriched_format','U') IS NULL
BEGIN
    CREATE TABLE mdm.pe_enriched_format (
        pe_masterid bigint NOT NULL,
        pe_pseudoSiret nvarchar(50) NULL,
        pe_nom_normalized nvarchar(200) NULL,
        pe_commune nvarchar(200) NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_pe_enriched_format_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_pe_enriched_format PRIMARY KEY (pe_masterid, pe_pseudoSiret)
    );
END;

IF OBJECT_ID('mdm.spe_master','U') IS NULL
BEGIN
    CREATE TABLE mdm.spe_master (
        spe_masterid bigint NOT NULL,
        spe_nom_normalized nvarchar(200) NULL,
        spe_prenom_normalized nvarchar(200) NULL,
        spe_dateNaissance date NULL,
        spe_communeNaissance nvarchar(200) NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        valid_from datetime2(3) NOT NULL,
        valid_to datetime2(3) NULL,
        is_current bit NOT NULL,
        row_hash varbinary(32) NOT NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_spe_master_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_spe_master PRIMARY KEY (spe_masterid, valid_from)
    );
END;

IF OBJECT_ID('mdm.pe_master','U') IS NULL
BEGIN
    CREATE TABLE mdm.pe_master (
        pe_masterid bigint NOT NULL,
        pe_pseudoSiret nvarchar(50) NULL,
        pe_nom_normalized nvarchar(200) NULL,
        pe_commune nvarchar(200) NULL,
        source_system nvarchar(50) NULL,
        source nvarchar(50) NULL,
        rnvp_score bit NULL,
        valid_from datetime2(3) NOT NULL,
        valid_to datetime2(3) NULL,
        is_current bit NOT NULL,
        row_hash varbinary(32) NOT NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_pe_master_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_pe_master PRIMARY KEY (pe_masterid, valid_from)
    );
END;

IF OBJECT_ID('mdm.Silver_master_relation','U') IS NULL
BEGIN
    CREATE TABLE mdm.Silver_master_relation (
        spe_masterid bigint NOT NULL,
        pe_masterid bigint NOT NULL,
        employment_type nvarchar(50) NULL,
        date_debut_relation date NULL,
        date_fin_relation date NULL,
        valid_from datetime2(3) NOT NULL,
        valid_to datetime2(3) NULL,
        is_current bit NOT NULL,
        row_hash varbinary(32) NOT NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_Silver_master_relation_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Silver_master_relation PRIMARY KEY (spe_masterid, pe_masterid, valid_from)
    );
END;
GO
