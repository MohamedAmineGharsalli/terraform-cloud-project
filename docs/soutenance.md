# Soutenance — plan, démonstration et questions

## 1. Plan de la présentation (12–15 diapositives)

1. **Contexte & objectifs** — déployer une plateforme Web HA sur AWS, de façon
   modulaire, sécurisée et reproductible.
2. **Architecture cible** — schéma (`docs/architecture.md`) : VPC, 3 niveaux de
   sous-réseaux, ALB, ASG, RDS, S3.
3. **Découpage réseau** — 2 AZ, sous-réseaux publics / applicatifs / base de
   données, IGW + NAT.
4. **Sécurité** — Security Groups chaînés, pas de SSH (SSM), IMDSv2, chiffrement
   (`docs/securite.md`).
5. **Terraform : modularité** — 6 modules, variables/outputs, `for_each`/`count`,
   `preconditions`.
6. **Multi-environnements** — `dev` / `test` / `prod`, différences de réglages.
7. **Backend distant** — S3 + `use_lockfile`, séparation des états.
8. **Contrainte du Learner Lab** — SCP `s3:GetBucketObjectLockConfiguration` et
   contournement AWS CLI (`docs/notes-storage-module.md`).
9. **CI/CD** — jobs `fmt` / `validate` / `test` / `plan` / `apply`, secrets.
10. **Tests** — suites `terraform` / `scripts` / `aws`, résultats.
11. **Coûts** — postes, estimations, optimisations (`docs/couts.md`).
12. **Difficultés & solutions** — voir `docs/rapport.md` §8.
13. **Améliorations possibles** — OIDC, SSE-KMS, WAF, HTTPS, multi-région.
14. **Conclusion** — ce qui est démontré, limites assumées.
15. **Questions.**

## 2. Démonstration pas à pas

```powershell
# 0. Identifiants du Learner Lab (AWS Details -> AWS CLI)
aws sts get-caller-identity

# 1. Backend distant (idempotent : ne recrée pas s'il existe)
./scripts/bootstrap-backend.ps1

# 2. Tests hors déploiement (format, validate, scripts)
./tests/run-tests.ps1

# 3. Plan puis apply de l'environnement dev
$env:TF_VAR_db_password = "un-mot-de-passe-solide"
cd environments/dev
terraform init
terraform plan
terraform apply

# 4. Vérifications
terraform output website_url      # ouvrir l'URL, rafraîchir : le hostname change (load balancing)
terraform output db_endpoint      # endpoint RDS (privé)
terraform output bucket_id        # bucket S3

# 5. Nettoyage (IMPORTANT pour le budget)
terraform destroy
```

Points à montrer pendant la démo :

- `terraform plan` : **39 ressources** à créer, aucune modification.
- L'URL de l'ALB : **rafraîchir plusieurs fois** → l'`Instance ID` change
  (répartition sur 2 instances / 2 AZ).
- La page affiche le nom du projet, le hostname, l'instance id et l'AZ.
- Dans la console : la RDS est **non publique**, le bucket S3 **bloque l'accès
  public**, les instances n'ont **pas** de port SSH ouvert.

## 3. Questions / réponses anticipées

**Pourquoi ne pas créer de rôle IAM ?**
Le lab interdit la création de rôles/politiques/OIDC. On réutilise `LabRole` et
`LabInstanceProfile` via des *data sources* (`modules/security`).

**Pourquoi pas de SSH ?**
Aucun port 22 ouvert : l'accès se fait par **SSM Session Manager**, ce qui
supprime la gestion des clés et réduit la surface d'attaque.

**Pourquoi `aws_s3_bucket` n'est-il pas utilisé ?**
Le SCP du lab refuse `s3:GetBucketObjectLockConfiguration`, action lue par la
ressource : elle échoue **quelle que soit la version du provider**. Le bucket est
donc créé par un `terraform_data` + `local-exec` (AWS CLI), tout en restant dans
le *state* Terraform.

**Pourquoi un `local-exec` et pas un module dédié ?**
C'est le seul moyen de contourner le SCP tout en gardant le bucket suivi par
Terraform. Les sous-ressources (versioning, chiffrement, blocage public, cycle de
vie) restent, elles, gérées nativement par le provider.

**Pourquoi `use_lockfile` et pas DynamoDB ?**
Terraform ≥ 1.10 propose un verrouillage natif S3 : plus besoin de table
DynamoDB, donc moins de ressources et de coûts.

**Comment sont gérés les secrets ?**
Aucun mot de passe dans le dépôt : `db_password` est fourni par
`TF_VAR_db_password` (local) ou le secret GitHub `DB_PASSWORD` (CI), et marqué
`sensitive`. Les identifiants AWS sont temporaires et stockés en secrets GitHub.

**Comment ça monte en charge ?**
Politique *target tracking* sur la CPU moyenne (cible 50 %) : l'ASG ajoute des
instances entre `min_size` et `max_size`.

**Qu'est-ce qui change entre dev et prod ?**
`prod` : NAT par AZ, RDS Multi-AZ, sauvegardes 7 jours, protection contre la
suppression, snapshot final. `dev`/`test` : un seul NAT, mono-AZ, réglages
légers (voir `docs/architecture.md` §4).

**Le pipeline déploie-t-il les 3 environnements à chaque push ?**
Non : un `push` sur `main` déploie **`dev`** uniquement (maîtrise du budget).
`test`/`prod` se déploient via *Run workflow* (`workflow_dispatch`).

**Comment l'état est-il sécurisé ?**
Bucket S3 dédié : versioning, chiffrement SSE-S3, blocage total de l'accès
public, politique refusant les requêtes non TLS, états séparés par environnement.

**Que ferait-on dans un vrai compte AWS ?**
Identité fédérée **GitHub OIDC** (plus de secrets), rôles au moindre privilège,
**SSE-KMS**, HTTPS avec ACM, WAF, et bucket **géré par Terraform**.
