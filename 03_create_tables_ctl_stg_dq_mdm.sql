SET NOCOUNT ON;
GO

PRINT 'Creating control tables...';
GO
IF OBJECT_ID('ctl.process_run') IS NULL
BEGIN
    CREATE TABLE ctl.process_run
    (
        run_id        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        process_name  SYSNAME          NOT NULL,
        start_ts      DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        end_ts        DATETIME2(3)     NULL,
        status        VARCHAR(20)      NULL,
        error_message NVARCHAR(4000)   NULL,
        host_name     NVARCHAR(255)    NULL,
        executed_by   NVARCHAR(255)    NULL
    );
END;
GO

IF OBJECT_ID('ctl.process_metrics') IS NULL
BEGIN
    CREATE TABLE ctl.process_metrics
    (
        run_id      UNIQUEIDENTIFIER NOT NULL,
        step_name   NVARCHAR(200)    NOT NULL,
        row_count   BIGINT           NULL,
        duration_ms BIGINT           NULL,
        comment     NVARCHAR(4000)   NULL,
        created_at  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, step_name, created_at)
    );
END;
GO

IF OBJECT_ID('ctl.process_error') IS NULL
BEGIN
    CREATE TABLE ctl.process_error
    (
        run_id         UNIQUEIDENTIFIER NOT NULL,
        step_name      NVARCHAR(200)    NOT NULL,
        error_number   INT              NULL,
        error_message  NVARCHAR(4000)   NULL,
        error_line     INT              NULL,
        error_procedure NVARCHAR(200)   NULL,
        error_ts       DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID('ctl.merge_log') IS NULL
BEGIN
    CREATE TABLE ctl.merge_log
    (
        label            SYSNAME      NOT NULL PRIMARY KEY,
        last_success_ts  DATETIME2(3) NULL
    );
END;
GO

PRINT 'Creating staging tables...';
GO

IF OBJECT_ID('stg.stg_new_decl_spe') IS NULL
BEGIN
    CREATE TABLE stg.stg_new_decl_spe
    (
        run_id                     UNIQUEIDENTIFIER NOT NULL,
        id_ligne_declaration       BIGINT           NOT NULL,
        spe_nom                    NVARCHAR(255)    NULL,
        spe_nom_normalized         NVARCHAR(255)    NULL,
        spe_prenom                 NVARCHAR(255)    NULL,
        spe_prenom_normalized      NVARCHAR(255)    NULL,
        spe_dateNaissance          DATE             NULL,
        spe_communeNaissance       NVARCHAR(255)    NULL,
        created_at                 DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        blocking_year AS YEAR(spe_dateNaissance) PERSISTED,
        blocking_nom2 AS LEFT(spe_nom_normalized,2) PERSISTED,
        blocking_pre2 AS LEFT(spe_prenom_normalized,2) PERSISTED,
        PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;
GO

IF OBJECT_ID('stg.stg_new_decl_pe') IS NULL
BEGIN
    CREATE TABLE stg.stg_new_decl_pe
    (
        run_id                 UNIQUEIDENTIFIER NOT NULL,
        id_ligne_declaration   BIGINT           NOT NULL,
        pseudo_siret           NVARCHAR(20)     NULL,
        pe_masterid            BIGINT           NULL,
        created_at             DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;
GO

IF OBJECT_ID('stg.stg_spe_nonmatched') IS NULL
BEGIN
    CREATE TABLE stg.stg_spe_nonmatched
    (
        run_id                     UNIQUEIDENTIFIER NOT NULL,
        id_ligne_declaration       BIGINT           NOT NULL,
        spe_nom_normalized         NVARCHAR(255)    NULL,
        spe_prenom_normalized      NVARCHAR(255)    NULL,
        spe_dateNaissance          DATE             NULL,
        spe_communeNaissance       NVARCHAR(255)    NULL,
        created_at                 DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        blocking_year AS YEAR(spe_dateNaissance) PERSISTED,
        blocking_nom2 AS LEFT(spe_nom_normalized,2) PERSISTED,
        blocking_pre2 AS LEFT(spe_prenom_normalized,2) PERSISTED,
        PRIMARY KEY (run_id, id_ligne_declaration)
    );
END;
GO

IF OBJECT_ID('stg.spe_nodes') IS NULL
BEGIN
    CREATE TABLE stg.spe_nodes
    (
        run_id               UNIQUEIDENTIFIER NOT NULL,
        node_id              BIGINT           NOT NULL,
        id_ligne_declaration BIGINT           NOT NULL,
        spe_nom_normalized   NVARCHAR(255)    NULL,
        spe_prenom_normalized NVARCHAR(255)   NULL,
        spe_dateNaissance    DATE             NULL,
        spe_communeNaissance NVARCHAR(255)    NULL,
        spe_masterid         BIGINT           NULL,
        created_at           DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        blocking_year AS YEAR(spe_dateNaissance) PERSISTED,
        blocking_nom2 AS LEFT(spe_nom_normalized,2) PERSISTED,
        blocking_pre2 AS LEFT(spe_prenom_normalized,2) PERSISTED,
        PRIMARY KEY (run_id, node_id)
    );
END;
GO

IF OBJECT_ID('stg.spe_edges') IS NULL
BEGIN
    CREATE TABLE stg.spe_edges
    (
        run_id        UNIQUEIDENTIFIER NOT NULL,
        node_a        BIGINT           NOT NULL,
        node_b        BIGINT           NOT NULL,
        score_total   FLOAT            NOT NULL,
        score_nom     FLOAT            NULL,
        score_prenom  FLOAT            NULL,
        score_dob     FLOAT            NULL,
        score_commune FLOAT            NULL,
        created_at    DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, node_a, node_b)
    );
END;
GO

IF OBJECT_ID('stg.spe_components') IS NULL
BEGIN
    CREATE TABLE stg.spe_components
    (
        run_id     UNIQUEIDENTIFIER NOT NULL,
        node_id    BIGINT           NOT NULL,
        component_id BIGINT         NOT NULL,
        updated_at DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, node_id)
    );
END;
GO

PRINT 'Creating DQ tables...';
GO

IF OBJECT_ID('dq.spe_match_candidates') IS NULL
BEGIN
    CREATE TABLE dq.spe_match_candidates
    (
        run_id                 UNIQUEIDENTIFIER NOT NULL,
        id_ligne_declaration   BIGINT           NOT NULL,
        candidate_spe_masterid BIGINT           NOT NULL,
        score_total            FLOAT            NOT NULL,
        score_nom              FLOAT            NULL,
        score_prenom           FLOAT            NULL,
        score_dob              FLOAT            NULL,
        score_commune          FLOAT            NULL,
        created_at             DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, id_ligne_declaration, candidate_spe_masterid)
    );
END;
GO

IF OBJECT_ID('dq.spe_match_candidates_intrarun') IS NULL
BEGIN
    CREATE TABLE dq.spe_match_candidates_intrarun
    (
        run_id                 UNIQUEIDENTIFIER NOT NULL,
        node_id                BIGINT           NOT NULL,
        candidate_spe_masterid BIGINT           NOT NULL,
        score_total            FLOAT            NOT NULL,
        created_at             DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (run_id, node_id, candidate_spe_masterid)
    );
END;
GO

IF OBJECT_ID('dq.spe_stewardship_decision') IS NULL
BEGIN
    CREATE TABLE dq.spe_stewardship_decision
    (
        decision_id          BIGINT          IDENTITY(1,1) PRIMARY KEY,
        run_id               UNIQUEIDENTIFIER NULL,
        id_ligne_declaration BIGINT           NOT NULL,
        decision_status      VARCHAR(30)      NOT NULL,
        chosen_spe_masterid  BIGINT           NULL,
        decided_by           NVARCHAR(255)    NULL,
        decided_at           DATETIME2(3)     NULL DEFAULT SYSUTCDATETIME(),
        comment              NVARCHAR(2000)   NULL
    );
END;
GO

PRINT 'Creating MDM SCD2 tables...';
GO

IF OBJECT_ID('mdm.Silver_master_spe') IS NULL
BEGIN
    CREATE TABLE mdm.Silver_master_spe
    (
        spe_masterid     BIGINT        NOT NULL,
        valid_from       DATETIME2(3)  NOT NULL,
        valid_to         DATETIME2(3)  NULL,
        is_current       BIT           NOT NULL DEFAULT 1,
        source_system    NVARCHAR(50)  NULL,
        spe_nom          NVARCHAR(255) NULL,
        spe_prenom       NVARCHAR(255) NULL,
        spe_dateNaissance DATE         NULL,
        spe_communeNaissance NVARCHAR(255) NULL,
        rnvp_ok          BIT           NULL,
        row_hash         VARBINARY(32) NOT NULL,
        created_at       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (spe_masterid, valid_from)
    );
END;
GO

PRINT 'Creating Silver enriched tables...';
GO

IF OBJECT_ID('silver.Silver_decl_spe') IS NULL
BEGIN
    CREATE TABLE silver.Silver_decl_spe
    (
        id_ligne_declaration   BIGINT        NOT NULL PRIMARY KEY,
        spe_nom                NVARCHAR(255) NULL,
        spe_nom_normalized     NVARCHAR(255) NULL,
        spe_prenom             NVARCHAR(255) NULL,
        spe_prenom_normalized  NVARCHAR(255) NULL,
        spe_dateNaissance      DATE          NULL,
        spe_communeNaissance   NVARCHAR(255) NULL,
        created_at             DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        valid_to               DATETIME2(3)  NULL
    );
END;
GO

IF OBJECT_ID('silver.Silver_decl_pe') IS NULL
BEGIN
    CREATE TABLE silver.Silver_decl_pe
    (
        id_ligne_declaration BIGINT        NOT NULL PRIMARY KEY,
        pseudo_siret         NVARCHAR(20)  NULL,
        created_at           DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        valid_to             DATETIME2(3)  NULL
    );
END;
GO

IF OBJECT_ID('silver.Silver_spe_enriched') IS NULL
BEGIN
    CREATE TABLE silver.Silver_spe_enriched
    (
        spe_masterid         BIGINT         NOT NULL,
        spe_nom_normalized   NVARCHAR(255)  NULL,
        spe_prenom_normalized NVARCHAR(255) NULL,
        spe_dateNaissance    DATE           NULL,
        spe_communeNaissance NVARCHAR(255)  NULL,
        rnvp_ok              BIT            NULL,
        created_at           DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
        valid_to             DATETIME2(3)   NULL,
        blocking_year AS YEAR(spe_dateNaissance) PERSISTED,
        blocking_nom2 AS LEFT(spe_nom_normalized,2) PERSISTED,
        blocking_pre2 AS LEFT(spe_prenom_normalized,2) PERSISTED
    );
END;
GO

IF OBJECT_ID('silver.Silver_pe_enriched') IS NULL
BEGIN
    CREATE TABLE silver.Silver_pe_enriched
    (
        pe_masterid   BIGINT        NOT NULL,
        pseudo_siret  NVARCHAR(20)  NULL,
        rnvp_ok       BIT           NULL,
        created_at    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        valid_to      DATETIME2(3)  NULL
    );
END;
GO

IF OBJECT_ID('mdm.Silver_master_pe') IS NULL
BEGIN
    CREATE TABLE mdm.Silver_master_pe
    (
        pe_masterid    BIGINT        NOT NULL,
        valid_from     DATETIME2(3)  NOT NULL,
        valid_to       DATETIME2(3)  NULL,
        is_current     BIT           NOT NULL DEFAULT 1,
        source_system  NVARCHAR(50)  NULL,
        pseudo_siret   NVARCHAR(20)  NULL,
        rnvp_ok        BIT           NULL,
        row_hash       VARBINARY(32) NOT NULL,
        created_at     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (pe_masterid, valid_from)
    );
END;
GO

IF OBJECT_ID('mdm.Silver_master_relation') IS NULL
BEGIN
    CREATE TABLE mdm.Silver_master_relation
    (
        spe_masterid        BIGINT       NOT NULL,
        pe_masterid         BIGINT       NOT NULL,
        employment_type     NVARCHAR(50) NULL,
        valid_from          DATETIME2(3) NOT NULL,
        valid_to            DATETIME2(3) NULL,
        is_current          BIT          NOT NULL DEFAULT 1,
        date_debut_relation DATE         NULL,
        date_fin_relation   DATE         NULL,
        row_hash            VARBINARY(32) NOT NULL,
        created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        PRIMARY KEY (spe_masterid, pe_masterid, valid_from)
    );
END;
GO

PRINT 'Creating mapping table (Silver layer adapter)...';
GO

IF OBJECT_ID('silver.Silver_declaration_ref_mapping') IS NULL
BEGIN
    CREATE TABLE silver.Silver_declaration_ref_mapping
    (
        id_ligne_declaration    BIGINT        NOT NULL PRIMARY KEY,
        spe_masterid            BIGINT        NULL,
        pe_masterid             BIGINT        NULL,
        spe_match_status        VARCHAR(40)   NULL,
        pe_match_status         VARCHAR(40)   NULL,
        best_candidate_masterid BIGINT        NULL,
        best_score              FLOAT         NULL,
        created_at              DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at              DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        valid_to                DATETIME2(3)  NULL
    );
END;
GO
