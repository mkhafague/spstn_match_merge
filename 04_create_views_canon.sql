SET NOCOUNT ON;
GO

PRINT 'Creating adapter views (canon)...';
GO

-- TODO: Adapter layer - map les colonnes réelles des tables Silver vers les noms canoniques attendus.
IF OBJECT_ID('silver.v_decl_spe_canon') IS NOT NULL DROP VIEW silver.v_decl_spe_canon;
GO
CREATE VIEW silver.v_decl_spe_canon
AS
SELECT
    d.id_ligne_declaration,
    d.spe_nom,
    d.spe_nom_normalized,
    d.spe_prenom,
    d.spe_prenom_normalized,
    d.spe_dateNaissance,
    d.spe_communeNaissance,
    d.created_at,
    d.valid_to
FROM silver.Silver_decl_spe d;
GO

IF OBJECT_ID('silver.v_decl_pe_canon') IS NOT NULL DROP VIEW silver.v_decl_pe_canon;
GO
CREATE VIEW silver.v_decl_pe_canon
AS
SELECT
    p.id_ligne_declaration,
    p.pseudo_siret,
    p.created_at,
    p.valid_to
FROM silver.Silver_decl_pe p;
GO

IF OBJECT_ID('silver.v_spe_enriched_canon') IS NOT NULL DROP VIEW silver.v_spe_enriched_canon;
GO
CREATE VIEW silver.v_spe_enriched_canon
AS
SELECT
    e.spe_masterid,
    e.spe_nom_normalized,
    e.spe_prenom_normalized,
    e.spe_dateNaissance,
    e.spe_communeNaissance,
    e.rnvp_ok,
    e.created_at,
    e.valid_to,
    e.blocking_year,
    e.blocking_nom2,
    e.blocking_pre2
FROM silver.Silver_spe_enriched e;
GO

IF OBJECT_ID('silver.v_pe_enriched_canon') IS NOT NULL DROP VIEW silver.v_pe_enriched_canon;
GO
CREATE VIEW silver.v_pe_enriched_canon
AS
SELECT
    e.pe_masterid,
    e.pseudo_siret,
    e.rnvp_ok,
    e.created_at,
    e.valid_to
FROM silver.Silver_pe_enriched e;
GO

IF OBJECT_ID('silver.v_mapping_canon') IS NOT NULL DROP VIEW silver.v_mapping_canon;
GO
CREATE VIEW silver.v_mapping_canon
AS
SELECT
    m.id_ligne_declaration,
    m.spe_masterid,
    m.pe_masterid,
    m.spe_match_status,
    m.pe_match_status,
    m.created_at,
    m.valid_to
FROM silver.Silver_declaration_ref_mapping m;
GO
