# Pack SQL Match & Merge v2 (SQL Server 2022 Standard)

## Objectif
Ce pack SQL implémente un processus ELT **Match & Merge** (SPE/PE) conforme aux contraintes SQL Server 2022 Standard et aux règles métier décrites dans la spécification (match déterministe + probabiliste, déduplication intra‑run par graphe, survivorship SCD2, stewardship).

## Architecture des schémas
- **ctl** : pilotage, audit, métriques, verrous.
- **stg** : staging par `run_id`, graphes intra‑run (nodes/edges/components).
- **dq** : scoring, candidats proba, décisions de stewardship.
- **mdm** : référentiels master (SCD2) et mapping déclaration ↔ master.
- **silver** : vues *adapter layer* (`silver.v_*_canon`) utilisées par les procédures.

## Ordre d’exécution (orchestration)
1. `ctl.sp_mm_run` (proc runner) appelle dans l’ordre :
   1. `silver.sp_mm_01_stage_new_declarations`
   2. `silver.sp_mm_02_match_pe`
   3. `silver.sp_mm_03_match_spe_deterministic`
   4. `silver.sp_mm_04_match_spe_probabilistic_candidates`
   5. `silver.sp_mm_05_build_intrarun_graph`
   6. `silver.sp_mm_06_compute_connected_components`
   7. `silver.sp_mm_07_new_spe_dedup_deterministic`
   8. `silver.sp_mm_08_new_spe_dedup_probabilistic`
   9. `mdm.sp_mm_09_merge_spe`
   10. `mdm.sp_mm_10_merge_pe`
   11. `mdm.sp_mm_11_merge_relation`

## Paramètres importants
- `@threshold` (par défaut 0.8) : seuil de similarité proba.
- `@max_iter` (par défaut 1000) : limite d’itérations pour les composantes connexes.
- `@status_created` (par défaut `'Created'`) : statut initial des nouveaux master.

## Stewardship (DQ)
- Les candidats proba sont stockés dans :
  - `dq.spe_match_candidates` (match proba vs référentiel)
  - `dq.spe_match_candidates_intrarun` (proba intra‑run via graphe)
- Les décisions humaines se déposent dans `dq.spe_stewardship_decision`.
- Application des décisions : `dq.sp_apply_stewardship_decisions`.

## Tuning performance
- Index de blocage proba sur colonnes calculées persistées (année, 2 premières lettres nom/prénom).
- Traitements set‑based.
- Transactions courtes par étape.

## Limites connues
- Levenshtein en T‑SQL est un compromis performance/maintenabilité. Une implémentation CLR pourrait améliorer la vitesse (non fournie).

## Adapter layer (views canon)
Les procédures lisent **exclusivement** les vues `silver.v_*_canon`. Les mappings de colonnes Silver sont à ajuster (TODO dans `04_create_views_canon.sql`).
