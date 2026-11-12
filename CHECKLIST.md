# CHECKLIST — correspondance exigences ↔ fichiers

Légende : ✅ fait · ⚠️ écart assumé (contrainte du Learner Lab, documenté) ·
🔲 à faire au moment de la remise (captures d'écran).

## 1. Terraform : organisation et modularité

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Code organisé en modules réutilisables | ✅ | `modules/{network,security,load-balancer,compute,database,storage}/` |
| Variables d'entrée typées et documentées | ✅ | `modules/*/variables.tf` |
| Sorties (outputs) | ✅ | `modules/*/outputs.tf`, `environments/*/outputs.tf` |
| Contraintes de version Terraform et provider | ✅ | `modules/*/versions.tf`, `environments/*/terraform.tf` |
| Fichiers de verrouillage versionnés | ✅ | `modules/*/.terraform.lock.hcl`, `environments/*/.terraform.lock.hcl` |
| Code formaté (`terraform fmt`) et valide (`terraform validate`) | ✅ | vérifié par `tests/run-tests.ps1` et le job CI `fmt`/`validate` |
| Utilisation de `for_each` / `count` / `dynamic` | ✅ | `modules/network/main.tf`, `modules/security/main.tf`, `modules/storage/main.tf` |
| Validations / préconditions | ✅ | `modules/compute/main.tf`, `modules/database/main.tf`, `modules/load-balancer/main.tf`, `modules/storage/main.tf` |

## 2. Infrastructure demandée

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| VPC dédié, ≥ 2 zones de disponibilité | ✅ | `modules/network/main.tf` |
| Sous-réseaux publics et privés | ✅ | `modules/network/main.tf` (public / app / db) |
| Internet Gateway + NAT Gateway | ✅ | `modules/network/main.tf` |
| Application Load Balancer public | ✅ | `modules/load-balancer/main.tf` |
| Auto Scaling Group + Launch Template | ✅ | `modules/compute/main.tf` |
| Politique de scaling | ✅ | `modules/compute/main.tf` (target tracking CPU 50 %) |
| Base de données relationnelle privée | ✅ | `modules/database/main.tf` (RDS MySQL) |
| Bucket S3 applicatif | ✅ | `modules/storage/main.tf` |
| Page Web de démonstration | ✅ | `scripts/user_data.sh` (nginx) |

## 3. Sécurité

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Security Groups en chaîne (moindre privilège) | ✅ | `modules/security/main.tf` |
| Pas d'accès SSH (SSM Session Manager) | ✅ | `modules/compute/main.tf`, `modules/security/main.tf` |
| IMDSv2 obligatoire | ✅ | `modules/compute/main.tf` (`http_tokens = "required"`) |
| Volumes EBS chiffrés | ✅ | `modules/compute/main.tf` |
| Base de données chiffrée et non publique | ✅ | `modules/database/main.tf` |
| Bucket S3 privé (blocage public, chiffrement) | ✅ | `modules/storage/main.tf`, `scripts/bootstrap-backend.ps1` |
| Aucun secret dans le dépôt | ✅ | `db_password` via `TF_VAR_db_password`/`DB_PASSWORD`, `.gitignore` |
| Mot de passe marqué `sensitive` | ✅ | `environments/*/variables.tf`, `modules/database/variables.tf` |

## 4. Backend et état

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Backend distant S3 | ✅ | `environments/*/backend.tf` |
| Verrouillage de l'état | ✅ | `use_lockfile = true` (`environments/*/backend.tf`) |
| Un état par environnement | ✅ | clés `dev/`, `test/`, `prod/` |
| Création du bucket d'état hors Terraform | ✅ | `scripts/bootstrap-backend.ps1` |

## 5. Multi-environnements

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Environnements `dev` / `test` / `prod` | ✅ | `environments/{dev,test,prod}/` |
| CIDR distincts | ✅ | `environments/*/variables.tf` (`10.20/21/22.0.0/16`) |
| Réglages adaptés (coût vs HA) | ✅ | `environments/*/variables.tf`, `terraform.tfvars.example` |
| Valeurs par défaut fonctionnelles sans `.tfvars` | ✅ | `environments/*/variables.tf` |

## 6. CI/CD

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Pipeline GitHub Actions | ✅ | `.github/workflows/terraform.yml` |
| `fmt` + `validate` automatiques | ✅ | jobs `fmt`, `validate` |
| `plan` sur Pull Request | ✅ | job `plan` |
| `apply` sur `main` | ✅ | job `apply` |
| Tests automatisés | ✅ | job `test` → `tests/run-tests.ps1` |
| Secrets gérés hors du code | ✅ | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `DB_PASSWORD` |
| Pas de création IAM par le pipeline | ✅ | *data sources* `LabRole`/`LabInstanceProfile` |

## 7. Tests

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| Script de test exécutable | ✅ | `tests/run-tests.ps1` |
| Tests hors AWS (format, validate, scripts) | ✅ | suites `terraform`, `scripts` |
| Test d'intégration AWS (bucket versionné) | ✅ | suite `aws` (`-IncludeAws`) |
| Journal de test | ✅ | `docs/tests/run-tests.log` |

## 8. Documentation

| Exigence | Statut | Fichiers |
|----------|--------|----------|
| README complet (en français) | ✅ | `README.md` |
| Documentation d'architecture | ✅ | `docs/architecture.md` |
| Justification sécurité | ✅ | `docs/securite.md` |
| Estimation des coûts | ✅ | `docs/couts.md` |
| Rapport de projet | ✅ | `docs/rapport.md` |
| Support de soutenance | ✅ | `docs/soutenance.md` |
| Note de conception du module storage | ✅ | `docs/notes-storage-module.md` |
| README par module | ✅ | `modules/*/README.md` |
| README des tests | ✅ | `tests/README.md` |

## 9. Contraintes du Learner Lab (écarts assumés)

| Contrainte | Statut | Traitement |
|------------|--------|------------|
| SCP bloque `s3:GetBucketObjectLockConfiguration` | ⚠️ | Bucket créé par AWS CLI / `local-exec` (`docs/notes-storage-module.md`) |
| Création IAM interdite | ⚠️ | `LabRole` / `LabInstanceProfile` via *data sources* |
| Région limitée à `us-east-1` | ⚠️ | `aws_region` par défaut `us-east-1` |
| Identifiants temporaires | ⚠️ | Secrets GitHub rafraîchis à chaque session |
| Pas de domaine / certificat ACM | ⚠️ | HTTPS optionnel (`enable_https`), désactivé par défaut |

## 10. À faire pour la remise (captures d'écran)

| Élément | Statut |
|---------|--------|
| Sortie de `terraform plan` (39 ressources) | 🔲 |
| Sortie de `terraform apply` | 🔲 |
| Page Web de l'ALB (2 rafraîchissements → 2 instance id) | 🔲 |
| `aws sts get-caller-identity` | 🔲 |
| Console RDS : instance non publique | 🔲 |
| Console S3 : blocage de l'accès public activé | 🔲 |
| Onglet Actions : pipeline vert | 🔲 |
| Sortie de `tests/run-tests.ps1` (24 tests) | 🔲 |
