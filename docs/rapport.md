# Rapport de projet — Terraform & CI/CD (plateforme Web HA sur AWS)

> **Squelette complété au fil des phases.** Les sections sont remplies en phase 8 ;
> la section **Limitation du Learner Lab (SCP)** est déjà définitive.

## Sommaire

1. Contexte et objectifs
2. Architecture cible
3. Choix techniques
4. Sécurité
5. CI/CD
6. Tests
7. Coûts
8. Difficultés rencontrées
9. Améliorations possibles
10. Annexes (captures d'écran)

---

## 1. Contexte et objectifs

*(phase 8)*

## 2. Architecture cible

*(phase 8 — voir `docs/architecture.md`)*

## 3. Choix techniques

*(phase 8)*

## 4. Sécurité

*(phase 8 — voir `docs/securite.md`)*

## 5. CI/CD

*(phase 8)*

## 6. Tests

*(phase 8 — journaux dans `docs/tests/`)*

## 7. Coûts

*(phase 8 — voir `docs/couts.md`)*

## 8. Difficultés rencontrées

### 8.1 Limitation du Learner Lab : SCP et ressource `aws_s3_bucket`

**Constat.** La création du bucket d'état via la ressource Terraform
`aws_s3_bucket` échouait systématiquement :

```
Error: creating S3 Bucket: ... AccessDenied: ... not authorized to perform:
s3:GetBucketObjectLockConfiguration ...
```

**Analyse.** Le SCP du Learner Lab refuse `s3:GetBucketObjectLockConfiguration`.
Le provider `hashicorp/aws` appelle cette action lors du `Create`/`Read` de
`aws_s3_bucket`. Le bucket est bien créé, mais la lecture échoue et Terraform
détruit le bucket puis renvoie une erreur. Le problème persiste **quelle que soit
la version du provider** (testé avec `5.100.0` et `5.40.0`), ce qui exclut une
régression de version.

**Décision.** Abandon d'un module Terraform dédié à la création du bucket (il
échouait sur le SCP) au profit d'un script **AWS CLI idempotent**
(`scripts/bootstrap-backend.ps1`) qui crée le bucket et
applique les quatre protections (versioning, SSE-S3, blocage public, politique
TLS-only). Le bucket d'état existant (`cloud5-tfstate-766760778474`) a été créé
avec l'AWS CLI. En phase 4, le bucket applicatif suivra la même approche
(`terraform_data` + `local-exec`) afin de rester dans le state Terraform tout en
contournant le SCP.

**Impact.** Le bucket d'état n'est pas géré par Terraform (pas de `destroy`
automatique — souhaitable pour un bucket d'état). L'idempotence du script
compense l'absence de `plan`. Voir `docs/securite.md` §6 et
`docs/notes-storage-module.md`.

### 8.2 Autres difficultés

*(phase 8)*

## 9. Améliorations possibles

*(phase 8)*

## 10. Annexes — captures d'écran

*(phase 8)*
