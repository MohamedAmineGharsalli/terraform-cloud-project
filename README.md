# cloud5 — Plateforme Web haute disponibilité (Terraform + CI/CD, AWS)

Projet Terraform 5 — Parcours Cloud et Réseaux.

Infrastructure AWS **modulaire**, **sécurisée** et **reproductible**, déployée sur
trois environnements (`dev`, `test`, `prod`) et validée/déployée par un pipeline
**GitHub Actions**.

---

## 1. Architecture (résumé)

- **VPC** `10.20.0.0/16` (dev) sur **2 zones de disponibilité** (us-east-1a / us-east-1b).
- 2 sous-réseaux **publics** (ALB), 2 sous-réseaux **privés applicatifs** (EC2),
  2 sous-réseaux **privés base de données** (RDS, sans route vers Internet).
- **Internet Gateway** + **NAT Gateway** (une seule en dev/test via
  `single_nat_gateway`, une par AZ en prod).
- **Application Load Balancer** public → **Auto Scaling Group** d'instances
  privées (Launch Template, IMDSv2, volumes chiffrés).
- **RDS MySQL** privé, chiffré, dans un groupe de sous-réseaux dédiés.
- **Bucket S3** pour les ressources/journaux (versioning, chiffrement, cycle de vie).
- **Backend Terraform distant** (S3 + verrou natif) et **pipeline CI/CD**.

> Schéma complet : `docs/architecture.md`.

---

## 2. Prérequis

| Outil | Version minimale | Remarque |
|-------|------------------|----------|
| Terraform | **>= 1.10.0** | Requis pour le verrouillage natif S3 (`use_lockfile = true`) |
| AWS CLI | v2 | Pour le bootstrap du backend et les scripts de test |
| Git | récent | |
| PowerShell | 5.1+ | Poste de travail Windows |

Région : **`us-east-1`** (le Learner Lab n'autorise que `us-east-1` / `us-west-2`).

---

## 3. Authentification AWS (Learner Lab) sans secret dans le dépôt

Les identifiants du Learner Lab sont **temporaires** (clé d'accès + secret +
**jeton de session**). Ils ne doivent **jamais** être versionnés.

Depuis le panneau *AWS Details → AWS CLI* du Learner Lab, copie les trois valeurs
puis renseigne le fichier de credentials (ou utilise `aws configure`) :

```powershell
aws configure set aws_access_key_id     "AKIA..."
aws configure set aws_secret_access_key "..."
aws configure set aws_session_token     "..."
aws configure set region                "us-east-1"
aws sts get-caller-identity
```

> Les trois valeurs **expirent à chaque session** de lab : pense à les rafraîchir
> (et à mettre à jour les secrets GitHub, voir la section **CI/CD**).

---

## 4. Backend distant (état Terraform)

L'état Terraform est **centralisé** dans un bucket S3 :

- Bucket : **`cloud5-tfstate-766760778474`**
- Région : `us-east-1`
- Chiffrement : `encrypt = true` (SSE-S3 / AES256)
- Verrouillage : `use_lockfile = true` (verrou natif S3, **sans DynamoDB**)
- Séparation des états : `dev/terraform.tfstate`, `test/terraform.tfstate`,
  `prod/terraform.tfstate`

### 4.1 Pour une autre équipe : remplace le nom du bucket

Un bloc `backend "s3"` **ne peut pas** utiliser de variable Terraform : le nom du
bucket est donc **écrit en dur** dans `environments/{dev,test,prod}/backend.tf`.

Avant ton premier `terraform init`, remplace :

```hcl
bucket = "cloud5-tfstate-766760778474"
```

par le nom de **ton** bucket (`cloud5-tfstate-<ton_account_id>`).

### 4.2 Créer / sécuriser le bucket (hors Terraform)

> ⚠️ Voir la section 5 : la ressource `aws_s3_bucket` **ne fonctionne pas** dans
> ce lab. Le bucket est créé par un **script AWS CLI idempotent**.

```powershell
./scripts/bootstrap-backend.ps1
```

Le script :

1. ne recrée pas le bucket s'il existe déjà (`head-bucket`) ;
2. active le **versioning** ;
3. active le **chiffrement SSE-S3 (AES256)** ;
4. active le **blocage total de l'accès public** (4 options) ;
5. attache une **politique refusant toute requête non TLS**.

---

## 5. Limitation du Learner Lab (SCP) et contournement

**Symptôme.** La ressource `aws_s3_bucket` échoue à la création avec
`AccessDenied` / `not authorized to perform: s3:GetBucketObjectLockConfiguration`.

**Cause.** Le **SCP** (Service Control Policy) de l'AWS Academy Learner Lab
refuse l'action `s3:GetBucketObjectLockConfiguration`. Or le provider
`hashicorp/aws` appelle cette action lors du `Create`/`Read` de `aws_s3_bucket`
(le bucket est créé, mais la lecture de la configuration Object Lock échoue et
Terraform annule). Le problème est **indépendant de la version du provider**
(testé avec `5.100.0` et `5.40.0`).

**Contournement retenu.**

- Le **bucket d'état** est créé **hors Terraform** par
  `scripts/bootstrap-backend.ps1` (AWS CLI, idempotent).
- Le **bucket applicatif** (module `storage`) est créé par un `terraform_data` +
  `local-exec` (AWS CLI), ce qui contourne le SCP **tout en gardant le bucket
  dans le state Terraform**.

**Conséquence.** Le bucket d'état n'est pas géré par le state Terraform : il
n'est pas supprimé par `terraform destroy` (souhaitable pour un bucket d'état).
Les protections sont appliquées de façon **idempotente** par le script.

> Détails de conception : `docs/notes-storage-module.md`. Impact sécurité :
> `docs/securite.md` §6.

---

## 6. Procédure Terraform (par environnement)

```powershell
cd environments/dev
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Le mot de passe de la base n'est **jamais** dans un fichier versionné : il est
fourni par la variable d'environnement `TF_VAR_db_password`.

```powershell
$env:TF_VAR_db_password = "un-mot-de-passe-solide"
```

Afficher les résultats :

```powershell
terraform output website_url   # URL de l'application (ALB)
terraform output db_endpoint   # endpoint RDS
terraform output bucket_id     # bucket S3
```

Destruction (à faire après la démonstration) :

```powershell
terraform destroy
```

> Chaque environnement est **fonctionnel par défaut** (les valeurs par défaut de
> `variables.tf` suffisent). Copie `terraform.tfvars.example` vers
> `terraform.tfvars` uniquement si tu veux personnaliser.

---

## 7. Tests

```powershell
# Suites par défaut (terraform + scripts) : aucun identifiant AWS requis
./tests/run-tests.ps1

# Tout, y compris les tests AWS (identifiants Learner Lab requis)
./tests/run-tests.ps1 -Suite all -IncludeAws
```

| Suite | Identifiants AWS | Contenu |
|-------|------------------|---------|
| `terraform` | non | `fmt -check`, `validate` (6 modules + 3 envs), rendu du template `user_data.sh` |
| `scripts` | non | fins de ligne LF, `bash -n`, arguments des scripts, contenu `user_data.sh` |
| `aws` | oui | identité AWS, bucket d'état, cycle de vie d'un bucket versionné temporaire |

Le journal est écrit dans `docs/tests/run-tests.log`. Détails : `tests/README.md`.

---

## 8. CI/CD (GitHub Actions)

Le pipeline est défini dans `.github/workflows/terraform.yml`. Il **ne crée
aucune ressource IAM** : il utilise le rôle pré-existant `LabRole` /
`LabInstanceProfile` du Learner Lab (via les *data sources* des modules
`security` et `compute`).

### 8.1 Déclencheurs

| Événement | Environnements | Actions exécutées |
|-----------|----------------|-------------------|
| `pull_request` | `dev`, `test`, `prod` | `fmt` → `validate` → `test` → `plan` (publié en commentaire de PR) |
| `push` sur `main` | `dev` | `fmt` → `validate` → `test` → `plan` + `apply` |
| `workflow_dispatch` | au choix (`dev`, `test`, `prod` ou `all`) | `fmt` → `validate` → `test` → `plan` + `apply` |

> Par défaut, un `push` sur `main` ne déploie que **`dev`** (limite de budget).
> Pour déployer `test` ou `prod`, lance le workflow manuellement
> (*Actions → terraform → Run workflow*) et choisis l'environnement.

> Les jobs d'`apply` s'exécutent **uniquement sur `main`**
> (`if: github.ref == 'refs/heads/main'`) et déclarent un **environment GitHub**
> (`dev` / `test` / `prod`). Chaque environnement possède sa propre **groupe de
> concurrence** (`cancel-in-progress: false`) : deux déploiements du même
> environnement ne se chevauchent jamais, et un déploiement en cours n'est pas
> annulé par un nouveau.

### 8.2 Jobs

| Job | Rôle |
|-----|------|
| `prepare` | Calcule les environnements à traiter et les indicateurs `run_dev` / `run_test` / `run_prod` |
| `fmt` | `terraform fmt -check -recursive` |
| `validate` | `terraform init -backend=false` + `terraform validate` pour les 6 modules et les 3 environnements (matrice) |
| `test` | `tests/run-tests.ps1 -Suite scripts` (tests des scripts, via `pwsh`) |
| `plan` | `terraform init` (backend S3) + `terraform plan -out=tfplan` ; `plan.txt` (sans couleurs) est publié dans le résumé du job **et en commentaire de PR** (tronqué, un marqueur par environnement met à jour le commentaire existant) |
| `apply-dev` / `apply-test` / `apply-prod` | `terraform init` + `terraform plan -out=tfplan` **puis** `terraform apply tfplan` dans le **même job** (l'apply consomme exactement le plan produit), suivi de `terraform output` |

> Le **plan binaire** (`tfplan`) n'est **jamais** publié comme artefact : seul le
> rendu lisible `plan.txt` est partagé. Le workflow utilise des **permissions
> minimales** (`contents: read`, plus `pull-requests: write` uniquement pour le
> job `plan`).

### 8.3 Secrets GitHub requis

| Secret | Contenu |
|--------|---------|
| `AWS_ACCESS_KEY_ID` | Clé d'accès temporaire du Learner Lab |
| `AWS_SECRET_ACCESS_KEY` | Secret d'accès temporaire |
| `AWS_SESSION_TOKEN` | **Jeton de session** (obligatoire, les identifiants du lab sont temporaires) |
| `DB_PASSWORD` | Mot de passe maître RDS (injecté via `TF_VAR_db_password`) |

Les trois identifiants AWS sont copiés depuis *AWS Details → AWS CLI* du Learner
Lab. **Ils expirent à chaque session** : pense à mettre à jour les secrets
GitHub avant de relancer le pipeline.

Configuration (une seule fois), au choix :

```powershell
# Via GitHub CLI
gh secret set AWS_ACCESS_KEY_ID     --body "AKIA..."
gh secret set AWS_SECRET_ACCESS_KEY --body "..."
gh secret set AWS_SESSION_TOKEN     --body "..."
gh secret set DB_PASSWORD           --body "un-mot-de-passe-solide"
```

ou dans l'interface : *Settings → Secrets and variables → Actions → New
repository secret*.

### 8.4 Ce qui n'est pas géré par le pipeline

- Le **bucket d'état** doit exister **avant** le premier `init` : il est créé
  hors Terraform par `scripts/bootstrap-backend.ps1` (section 4).
- Le **bucket de stockage** applicatif est créé par le module `storage` via
  `local-exec` (section 5), pas par le provider S3.

---

## 9. Modules

| Module | Responsabilité | README |
|--------|----------------|--------|
| `network` | VPC, sous-réseaux (public/app/db), IGW, NAT, tables de routage | `modules/network/README.md` |
| `security` | Security Groups chaînés + *data sources* `LabRole`/`LabInstanceProfile` | `modules/security/README.md` |
| `load-balancer` | ALB, groupe cible, écouteurs HTTP/HTTPS | `modules/load-balancer/README.md` |
| `compute` | AMI AL2023, Launch Template, Auto Scaling Group, scaling CPU | `modules/compute/README.md` |
| `database` | Groupe de sous-réseaux + instance RDS MySQL privée | `modules/database/README.md` |
| `storage` | Bucket S3 privé (via `terraform_data` + AWS CLI) | `modules/storage/README.md` |

Chaque module a ses propres `variables.tf`, `outputs.tf`, `versions.tf` et
`README.md`. Les environnements ne font que **câbler** ces modules.

---

## 10. Variables et sorties

### 10.1 Variables principales (environnements)

Valeurs par défaut **`dev`** (voir `environments/dev/variables.tf`) ; les
défauts de `test`/`prod` diffèrent (voir §11 et `docs/architecture.md` §4).

| Variable | Défaut (dev) | Rôle |
|----------|--------------|------|
| `project_name` | `cloud5` | Préfixe de nommage + affiché sur la page |
| `aws_region` | `us-east-1` | Région (imposée par le lab) |
| `vpc_cidr` | `10.20.0.0/16` | CIDR du VPC (`10.21`/`10.22` en test/prod) |
| `single_nat_gateway` | `true` | `true` = 1 NAT ; `false` = 1 par AZ (prod) |
| `enable_https` / `certificate_arn` | `false` / `""` | Écouteur HTTPS (domaine + ACM requis) |
| `instance_type` | `t3.micro` | Type des instances |
| `min_size` / `max_size` / `desired_capacity` | `2` / `3` / `2` | Dimensionnement de l'ASG |
| `cpu_target_value` | `50` | Cible CPU (%) du scaling |
| `use_ssm_ami` | `true` | Résout l'AMI via SSM (repli `aws_ami`) |
| `db_name` / `db_username` | `cloud5db` / `cloud5admin` | Base et utilisateur RDS |
| `db_password` | — (**requis**, sensible) | Mot de passe RDS (`TF_VAR_db_password`) |
| `db_instance_class` | `db.t3.micro` | Classe RDS |
| `db_allocated_storage` | `20` | Stockage RDS (Go) |
| `db_multi_az` | `false` | RDS Multi-AZ (`true` en prod) |
| `db_backup_retention` | `1` | Jours de sauvegarde (1 / 3 / 7) |
| `db_skip_final_snapshot` | `true` | Snapshot final (`false` en prod) |
| `db_final_snapshot_identifier` | `""` | Nom du snapshot final (prod) |
| `db_deletion_protection` | `false` | Protection suppression (`true` en prod) |
| `db_apply_immediately` | `true` | Application immédiate des changements |
| `bucket_name` | `""` | Nom S3 explicite (sinon calculé) |
| `enable_versioning` | `true` | Versioning S3 |
| `tags` | `{}` | Tags additionnels |

### 10.2 Sorties (environnements)

| Sortie | Description |
|--------|-------------|
| `website_url` | URL de l'application via l'ALB |
| `alb_dns_name` | DNS de l'ALB |
| `vpc_id` | Identifiant du VPC |
| `app_subnet_ids` | Sous-réseaux applicatifs privés |
| `asg_name` | Nom de l'Auto Scaling Group |
| `db_endpoint` / `db_address` / `db_name` | Connexion RDS |
| `bucket_id` / `bucket_arn` | Bucket S3 applicatif |
| `lab_role_arn` | ARN du rôle pré-existant `LabRole` |
| `name_prefix` | Préfixe de nommage de l'environnement |

> Le détail des variables/sorties de **chaque module** figure dans son
> `modules/<module>/README.md`.

---

## 11. Coûts

| Environnement | Estimation / mois | Estimation / heure |
|---------------|-------------------|--------------------|
| `dev` | ~82 $ | ~0,11 $ |
| `test` | ~82 $ | ~0,11 $ |
| `prod` | ~128 $ | ~0,18 $ |

Le **NAT Gateway** est le premier poste (~40 %) : d'où un **NAT unique** en
`dev`/`test`. Les ressources sont facturées **à l'heure** : une démonstration de
quelques heures coûte moins d'un dollar, mais laisser tourner les trois
environnements un mois consomme plus que le crédit du lab.

**→ `terraform destroy` après chaque démonstration.**

Détails et optimisations : `docs/couts.md`.

---

## 12. Dépannage

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `Error: ... s3:GetBucketObjectLockConfiguration` | SCP du lab | Normal : ne pas utiliser `aws_s3_bucket`. Le bucket est créé par AWS CLI (section 5). |
| `terraform init` : `AccessDenied` sur le backend | Identifiants expirés, ou bucket d'état absent | Rafraîchir les identifiants ; lancer `./scripts/bootstrap-backend.ps1` |
| `Error acquiring the state lock` | Verrou resté après un run interrompu | Attendre, ou (si sûr) `terraform force-unlock <ID>` |
| `Error: creating IAM Role ...` | Création IAM interdite dans le lab | Utiliser `LabRole` / `LabInstanceProfile` (déjà le cas) |
| Les instances ne s'enregistrent pas (cible *unhealthy*) | Route NAT absente au démarrage | `depends_on = [module.network]` (déjà présent) ; attendre ~2 min |
| `db_password` manquant | Variable non fournie | `$env:TF_VAR_db_password = "..."` (ou secret `DB_PASSWORD`) |
| CI : `plan`/`apply` en échec | Secrets GitHub absents ou expirés | Rafraîchir `AWS_*` et `DB_PASSWORD` (section 8.3) |
| Tests bash sous Windows : *No such file or directory* | Chemin Windows mangé par bash | Utiliser `tests/run-tests.ps1` (gère déjà le cas) |
| `terraform fmt -check` échoue en CI | Fichier non formaté | `terraform fmt -recursive` puis commit |

---

## 13. Documentation complémentaire

| Fichier | Contenu |
|---------|---------|
| `docs/architecture.md` | Schéma d'architecture (Mermaid) et découpage réseau |
| `docs/securite.md` | Justification des choix de sécurité (+ limitation SCP) |
| `docs/couts.md` | Ressources facturables et estimation |
| `docs/rapport.md` | Rapport de projet 10–15 pages |
| `docs/soutenance.md` | Plan de soutenance, démo et questions/réponses |
| `docs/notes-storage-module.md` | Note de conception du module `storage` |
| `tests/README.md` | Documentation de la suite de tests |
| `CHECKLIST.md` | Correspondance exigences ↔ fichiers |
| `modules/*/README.md` | Documentation de chaque module |

---

## 14. Licence

MIT — voir `LICENSE`.
