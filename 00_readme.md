## Match & Merge ELT – SQL Server 2022 (v2)

### Architecture
- `ctl` : orchestration, audit, métriques, erreurs.
- `stg` : staging par `run_id`, graphe intra-run pour la déduplication SPE.
- `dq`  : scoring, candidats probabilistes, décisions de stewardship.
- `mdm` : référentiels SCD2 (SPE, PE, relations).

### Ordre d’exécution
1. `ctl.sp_mm_run` (orchestration et verrouillage applicatif)
2. `silver.sp_mm_01_stage_new_declarations`
3. `silver.sp_mm_02_match_pe`
4. `silver.sp_mm_03_match_spe_deterministic`
5. `silver.sp_mm_04_match_spe_probabilistic_candidates`
6. Déduplication SPE intra-run :
   - `silver.sp_mm_05_build_intrarun_graph`
   - `silver.sp_mm_06_compute_connected_components`
   - `silver.sp_mm_07_new_spe_dedup_deterministic`
   - `silver.sp_mm_08_new_spe_dedup_probabilistic`
7. `mdm.sp_mm_09_merge_spe`
8. `mdm.sp_mm_10_merge_pe`
9. `mdm.sp_mm_11_merge_relation`
10. `dq.sp_apply_stewardship_decisions` (asynchrone)

### Paramètres principaux
- `@threshold` (défaut `0.8`) pour les scores probabilistes.
- `@max_iter` (défaut `1000`) pour la propagation de labels des composantes connexes.
- `@status_created` (défaut `'Created'`) statut appliqué lors de la création de nouveaux `masterid`.

### Stewardship
- Consulter `dq.spe_match_candidates` (référentiel) et `dq.spe_match_candidates_intrarun` (intra-run).
- Enregistrer la décision dans `dq.spe_stewardship_decision`.
- Appliquer via `dq.sp_apply_stewardship_decisions` (met à jour le mapping et insère les formats enrichis).

### Performance & robustesse
- Colonnes calculées persistées pour les clés de blocage probabilistes : année de naissance, premières lettres nom/prénom.
- Index dédiés `IX_*_blocking` sur staging et enrichi.
- Traitement set-based, aucune utilisation de curseur.
- Transactions courtes par étape, verrouillage applicatif via `sp_getapplock` (`MM_RUN`).
- Journalisation : `ctl.process_run`, `ctl.process_metrics`, `ctl.process_error`.

### Limites connues
- Levenshtein T-SQL coûteux CPU : privilégier blocage strict et seuil adapté.
- Évolution possible : implémentation CLR pour Levenshtein (non incluse ici).

### Adapter layer (vues canon)
Les procédures ne dépendent que des vues canon :
- `silver.v_decl_spe_canon`
- `silver.v_decl_pe_canon`
- `silver.v_spe_enriched_canon`
- `silver.v_pe_enriched_canon`
- `silver.v_mapping_canon`

Adapter les mappings de colonnes Silver dans ces vues (TODO dans `04_create_views_canon.sql`).
