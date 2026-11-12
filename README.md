# cloud5 — Plateforme Web haute disponibilité (Terraform + CI/CD, AWS)

Projet Terraform 5 — Parcours Cloud et Réseaux.

Infrastructure AWS **modulaire**, **sécurisée** et **reproductible**, déployée sur
trois environnements (`dev`, `test`, `prod`) et validée/déployée par un pipeline
**GitHub Actions**.

> 📌 **État de la documentation** — ce README est complété au fil des phases du
> projet. Les sections *Architecture*, *Backend*, *Limitation du Learner Lab* et
> *CI/CD* sont déjà complètes ; les sections *Modules*, *Variables/Outputs*,
> *Coûts* et *Dépannage* sont finalisées en phase 8.

---

## 1. Architecture (résumé)

- **VPC** `10.20.0.0/16` sur **2 zones de disponibilité** (us-east-1a / us-east-1b).
- 2 sous-réseaux **publics** (ALB), 2 sous-réseaux **privés applicatifs** (EC2),
  2 sous-réseaux **privés base de données** (RDS, sans route vers Internet).
- **Internet Gateway** + **NAT Gateway** (une seule en dev/test via
  `single_nat_gateway`, une par AZ en prod).
- **Application Load Balancer** public → **Auto Scaling Group** d'instances
  privées (Launch Template, IMDSv2, volumes chiffrés).
- **RDS MySQL** privé, chiffré, dans un groupe de sous-réseaux dédiés.
- **Bucket S3** pour les ressources/journaux (versioning, chiffrement, cycle de vie).
- **Backend Terraform distant** (S3 + verrou natif) et **pipeline CI/CD**.

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
> (et à mettre à jour les secrets GitHub, voir la section CI/CD).

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

**Contournement retenu.** Le bucket d'état (et, en phase 4, le bucket de
stockage applicatif) est **créé et configuré hors Terraform** via l'AWS CLI
(`scripts/bootstrap-backend.ps1`). Terraform gère ensuite le reste de
l'infrastructure normalement.

**Conséquence.** Le bucket n'est plus géré par le state Terraform : il n'est pas
supprimé par `terraform destroy` (ce qui est souhaitable pour le bucket d'état,
qui doit survivre aux environnements). Les protections sont appliquées de façon
**idempotente** par le script.

> 🔎 Le même SCP peut affecter les sous-ressources
> `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`,
> `aws_s3_bucket_public_access_block` et `aws_s3_bucket_lifecycle_configuration`.
> En phase 4, si l'une d'elles est refusée, on basculera sur le même contournement
> (`aws s3api put-bucket-*` via `local-exec`). Voir `docs/notes-storage-module.md`.

---

## 6. Procédure Terraform (par environnement)

```powershell
cd environments/dev
terraform init
terraform fmt -recursive
terraform validate
terraform plan  -var="db_password=$env:TF_VAR_db_password"
terraform apply
```

Le mot de passe de la base n'est **jamais** dans un fichier versionné : il est
fourni par la variable d'environnement `TF_VAR_db_password`.

```powershell
$env:TF_VAR_db_password = "un-mot-de-passe-solide"
```

Destruction (à faire après la démonstration) :

```powershell
terraform destroy
```

---

## 7. CI/CD (GitHub Actions)

Le pipeline est défini dans `.github/workflows/terraform.yml`. Il **ne crée
aucune ressource IAM** : il utilise le rôle pré-existant `LabRole` /
`LabInstanceProfile` du Learner Lab (via les *data sources* des modules
`security` et `compute`).

### 7.1 Déclencheurs

| Événement | Environnements | Actions exécutées |
|-----------|----------------|-------------------|
| `pull_request` | `dev`, `test`, `prod` | `fmt` → `validate` → `plan` |
| `push` sur `main` | `dev` | `fmt` → `validate` → `apply` |
| `workflow_dispatch` | au choix (`dev`, `test`, `prod` ou `all`) | `fmt` → `validate` → `plan` → `apply` |

> Par défaut, un `push` sur `main` ne déploie que **`dev`** (limite de budget).
> Pour déployer `test` ou `prod`, lance le workflow manuellement
> (*Actions → terraform → Run workflow*) et choisis l'environnement.

### 7.2 Jobs

| Job | Rôle |
|-----|------|
| `prepare` | Calcule la liste des environnements à traiter selon l'événement |
| `fmt` | `terraform fmt -check -recursive` + vérification syntaxique des scripts bash (`bash -n`) |
| `validate` | `terraform init -backend=false` + `terraform validate` pour les 6 modules et les 3 environnements (matrice) |
| `plan` | `terraform init` (backend S3) + `terraform plan` ; le plan est publié dans le résumé du job et en artefact |
| `apply` | `terraform init` + `terraform apply -auto-approve` puis `terraform output` |

### 7.3 Secrets GitHub requis

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

### 7.4 Ce qui n'est pas géré par le pipeline

- Le **bucket d'état** doit exister **avant** le premier `init` : il est créé
  hors Terraform par `scripts/bootstrap-backend.ps1` (section 4).
- Le **bucket de stockage** applicatif est créé par le module `storage` via
  `local-exec` (section 5), pas par le provider S3.

---

## 8. Documentation complémentaire

| Fichier | Contenu |
|---------|---------|
| `docs/architecture.md` | Schéma d'architecture (Mermaid) — *phase 8* |
| `docs/securite.md` | Justification des choix de sécurité (+ limitation SCP) |
| `docs/couts.md` | Ressources facturables et estimation — *phase 8* |
| `docs/rapport.md` | Rapport de projet 10–15 pages |
| `docs/soutenance.md` | Support de soutenance — *phase 8* |
| `docs/notes-storage-module.md` | Note de conception du module `storage` (phase 4) |
| `CHECKLIST.md` | Correspondance exigences ↔ fichiers — *phase 8* |

---

## 9. Licence

MIT — voir `LICENSE`.
