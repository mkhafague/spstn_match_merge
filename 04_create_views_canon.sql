SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Adapter views: TODO map columns from Silver tables.

CREATE OR ALTER VIEW silver.v_decl_spe_canon AS
SELECT
    CAST(NULL AS bigint) AS id_ligne_declaration, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_nom_normalized, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_prenom_normalized, -- TODO map
    CAST(NULL AS date) AS spe_dateNaissance, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_communeNaissance, -- TODO map
    CAST(NULL AS nvarchar(50)) AS spe_pseudoSiret, -- TODO map
    CAST(NULL AS nvarchar(50)) AS employment_type, -- TODO map
    CAST(NULL AS date) AS date_debut_prestation, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source_system, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source, -- TODO map
    CAST(NULL AS bit) AS rnvp_score, -- TODO map
    CAST(NULL AS datetime2(3)) AS created_at, -- TODO map
    CAST(NULL AS datetime2(3)) AS valid_to -- TODO map
WHERE 1 = 0;
GO

CREATE OR ALTER VIEW silver.v_decl_pe_canon AS
SELECT
    CAST(NULL AS bigint) AS id_ligne_declaration, -- TODO map
    CAST(NULL AS nvarchar(50)) AS pe_pseudoSiret, -- TODO map
    CAST(NULL AS nvarchar(200)) AS pe_nom_normalized, -- TODO map
    CAST(NULL AS nvarchar(200)) AS pe_commune, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source_system, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source, -- TODO map
    CAST(NULL AS bit) AS rnvp_score, -- TODO map
    CAST(NULL AS datetime2(3)) AS created_at, -- TODO map
    CAST(NULL AS datetime2(3)) AS valid_to -- TODO map
WHERE 1 = 0;
GO

CREATE OR ALTER VIEW silver.v_spe_enriched_canon AS
SELECT
    CAST(NULL AS bigint) AS spe_masterid, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_nom_normalized, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_prenom_normalized, -- TODO map
    CAST(NULL AS date) AS spe_dateNaissance, -- TODO map
    CAST(NULL AS nvarchar(200)) AS spe_communeNaissance, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source_system, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source, -- TODO map
    CAST(NULL AS bit) AS rnvp_score, -- TODO map
    CAST(NULL AS datetime2(3)) AS created_at -- TODO map
WHERE 1 = 0;
GO

CREATE OR ALTER VIEW silver.v_pe_enriched_canon AS
SELECT
    CAST(NULL AS bigint) AS pe_masterid, -- TODO map
    CAST(NULL AS nvarchar(50)) AS pe_pseudoSiret, -- TODO map
    CAST(NULL AS nvarchar(200)) AS pe_nom_normalized, -- TODO map
    CAST(NULL AS nvarchar(200)) AS pe_commune, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source_system, -- TODO map
    CAST(NULL AS nvarchar(50)) AS source, -- TODO map
    CAST(NULL AS bit) AS rnvp_score, -- TODO map
    CAST(NULL AS datetime2(3)) AS created_at -- TODO map
WHERE 1 = 0;
GO

CREATE OR ALTER VIEW silver.v_mapping_canon AS
SELECT
    id_ligne_declaration,
    spe_masterid,
    pe_masterid,
    spe_match_status,
    pe_match_status,
    best_candidate_masterid,
    best_candidate_score,
    run_id,
    created_at,
    updated_at
FROM mdm.declaration_ref_mapping;
GO
