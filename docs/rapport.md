# Rapport de projet — Terraform & CI/CD (plateforme Web HA sur AWS)

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

Ce projet consiste à concevoir, déployer et automatiser une **plateforme Web
hautement disponible** sur AWS, entièrement décrite en **Terraform** et livrée
par un pipeline **CI/CD GitHub Actions**.

Objectifs :

- **Reproductibilité** : toute l'infrastructure est décrite en code (IaC) ;
  aucun clic manuel dans la console AWS.
- **Modularité** : des modules réutilisables permettent de déployer la même
  architecture sur **trois environnements** (`dev`, `test`, `prod`).
- **Sécurité** : moindre privilège réseau, aucun SSH, chiffrement, aucun secret
  dans le dépôt.
- **Automatisation** : formatage, validation, tests, `plan` et `apply` exécutés
  par la CI.
- **Maîtrise des coûts** : dimensionnement minimal et réglages économiques
  (NAT unique en `dev`/`test`).

Le tout dans le cadre contraint de l'**AWS Academy Learner Lab** (région unique,
IAM interdit, SCP restrictif, identifiants temporaires), ce qui a façonné
plusieurs choix techniques décrits en §8.

## 2. Architecture cible

L'architecture est détaillée dans `docs/architecture.md`. En résumé :

- Un **VPC** sur **2 zones de disponibilité**, avec trois niveaux de
  sous-réseaux : **publics** (ALB, NAT), **applicatifs privés** (EC2) et
  **base de données privés** (RDS, sans route Internet).
- Un **Application Load Balancer** public devant un **Auto Scaling Group**
  d'instances `t3.micro` (Amazon Linux 2023, nginx).
- Une **base RDS MySQL** privée et chiffrée.
- Un **bucket S3** privé (versioning, chiffrement, cycle de vie).
- Un **backend Terraform distant** (S3 + verrou natif) et un **pipeline CI/CD**.

Le flux applicatif est le suivant :

```
Internet → ALB (80/443) → app-sg (80) → instances nginx
                                      → db-sg (3306) → RDS
instances → NAT → Internet (mises à jour, SSM)
```

## 3. Choix techniques

### 3.1 Découpage en modules

Six modules, chacun avec ses variables, sorties et README :

| Module | Responsabilité |
|--------|----------------|
| `network` | VPC, sous-réseaux, IGW, NAT, routage |
| `security` | Security Groups chaînés + *data sources* IAM du lab |
| `load-balancer` | ALB, groupe cible, écouteurs |
| `compute` | AMI, Launch Template, ASG, scaling |
| `database` | Groupe de sous-réseaux + RDS |
| `storage` | Bucket S3 (via `terraform_data` + AWS CLI) |

Les environnements (`environments/{dev,test,prod}`) ne font que **câbler** ces
modules avec des valeurs adaptées.

### 3.2 Idiomes Terraform utilisés

- **`for_each` sur des maps** pour les sous-réseaux et les NAT gateways : ajouter
  une zone ou un sous-réseau est une modification d'une ligne, et les adresses de
  ressources restent stables.
- **`count`** pour les ressources optionnelles (versioning, blocage public,
  HTTPS).
- **`dynamic`** pour les règles conditionnelles (règle HTTPS, règles de cycle de
  vie).
- **`preconditions`** pour valider la cohérence (`max_size >= min_size`,
  `final_snapshot_identifier` requis si pas de `skip_final_snapshot`, etc.).
- **`templatefile`** pour générer le `user_data` des instances.

### 3.3 Backend distant

L'état est stocké dans un bucket S3 dédié, avec :

- **`use_lockfile = true`** : verrouillage natif S3 (Terraform ≥ 1.10), donc
  **pas de table DynamoDB** à provisionner ni à payer ;
- **un état par environnement** (`dev/`, `test/`, `prod/`).

### 3.4 Résolution de l'AMI

L'AMI Amazon Linux 2023 est résolue par **paramètre SSM public**
(`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`), avec
un **repli** sur la *data source* `aws_ami` si le SCP bloquait SSM
(`use_ssm_ami = false`).

### 3.5 Contournement du SCP pour S3

Voir §8.1 et `docs/notes-storage-module.md` : le bucket est créé par un
`terraform_data` + `local-exec` (AWS CLI), ce qui contourne le SCP tout en
gardant le bucket **dans le state Terraform**.

## 4. Sécurité

Le détail est dans `docs/securite.md`. Points clés :

- **Security Groups chaînés** référencés par identifiant (jamais par CIDR) :
  `Internet → alb-sg → app-sg → db-sg`.
- **Aucun SSH** : accès par **SSM Session Manager**.
- **IMDSv2 obligatoire** et volumes **EBS chiffrés**.
- **RDS** chiffrée et **non publique** ; **S3** privé avec blocage public.
- **Secrets hors du dépôt** : `db_password` via `TF_VAR_db_password` /
  `DB_PASSWORD` ; identifiants AWS temporaires en secrets GitHub.

## 5. CI/CD

Le pipeline `.github/workflows/terraform.yml` s'exécute sur `ubuntu-latest` :

| Job | Déclencheur | Rôle |
|-----|-------------|------|
| `prepare` | toujours | choisit les environnements à traiter |
| `fmt` | toujours | `terraform fmt -check -recursive` |
| `validate` | toujours | `init -backend=false` + `validate` (6 modules + 3 envs) |
| `test` | toujours | `tests/run-tests.ps1 -Suite scripts` (pwsh) |
| `plan` | PR / manuel | `init` + `plan` (backend S3), publié en résumé + artefact |
| `apply` | `main` / manuel | `init` + `apply -auto-approve` + `output` |

- **Aucune ressource IAM** n'est créée : le pipeline utilise `LabRole` /
  `LabInstanceProfile`.
- Un `push` sur `main` déploie **`dev`** uniquement (budget) ; `test`/`prod` via
  `workflow_dispatch`.
- Les identifiants AWS et le mot de passe RDS proviennent de **secrets GitHub**.

## 6. Tests

La suite `tests/run-tests.ps1` couvre trois niveaux :

1. **`terraform`** (hors AWS) : `fmt -check`, `validate` des 6 modules et des
   3 environnements, et **rendu du template `user_data.sh`** via
   `terraform console`.
2. **`scripts`** (hors AWS) : fins de ligne **LF**, syntaxe **`bash -n`**,
   présence du **jeton IMDSv2** et du placeholder `${project_name}`, rejet des
   arguments invalides par les scripts `s3_bucket_admin.{ps1,sh}`.
3. **`aws`** (optionnel, `-IncludeAws`) : identité AWS, présence du bucket
   d'état, et **cycle de vie complet** d'un bucket versionné temporaire
   (création → 2 versions + 1 delete marker → destruction → bucket absent).

Résultat de la dernière exécution complète : **24 tests réussis, 0 échec**
(journal : `docs/tests/run-tests.log`).

## 7. Coûts

Le détail est dans `docs/couts.md`. En résumé :

- **`dev` ≈ 82 $/mois**, **`test` ≈ 82 $/mois**, **`prod` ≈ 128 $/mois**
  (tarifs on-demand approximatifs).
- Le **NAT Gateway** est le premier poste de coût (~40 %) : d'où un **NAT unique**
  en `dev`/`test`.
- Les ressources sont facturées **à l'heure** : une démonstration de quelques
  heures coûte moins d'un dollar, mais laisser tourner les trois environnements
  un mois consommerait plus que le crédit du lab → **`terraform destroy` après
  chaque démonstration**.

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
(`scripts/bootstrap-backend.ps1`) qui crée le bucket d'état et
applique les quatre protections (versioning, SSE-S3, blocage public, politique
TLS-only). Le bucket d'état existant (`cloud5-tfstate-766760778474`) a été créé
avec l'AWS CLI. Le bucket applicatif suit la même approche via
`terraform_data` + `local-exec` afin de rester dans le state Terraform tout en
contournant le SCP.

**Impact.** Le bucket d'état n'est pas géré par Terraform (pas de `destroy`
automatique — souhaitable pour un bucket d'état). L'idempotence du script
compense l'absence de `plan`. Voir `docs/securite.md` §6 et
`docs/notes-storage-module.md`.

### 8.2 Autres difficultés

**a) `terraform_data` : pas de valeur dynamique dans `input`.**
`terraform_data` **remplace** la ressource dès que `input` change — ce qui
déclencherait le provisioner de destruction (suppression du bucket !). Un premier
design stockait un drapeau `is_windows` dans `input` pour choisir le script de
destruction. Or, comme un `apply` sous Windows et un `destroy` sous Linux (CI)
produisent une valeur différente, la ressource aurait été recréée et le bucket
supprimé par accident.

**Solution.** `input` ne contient plus que `{ bucket, region }` (valeurs stables)
et la commande de destruction est rendue **indépendante de l'OS** :
`powershell ... || bash ...` (le provisioner de destruction ne peut lire que
`self` et `path.module`).

**b) Le littéral `None` de l'AWS CLI.**
`aws ... --output text` renvoie la chaîne littérale **`None`** (et non une chaîne
vide) quand la requête ne trouve rien. La boucle de suppression des versions ne
se terminait donc jamais et transmettait un `version-id` vide. Corrigé dans les
deux scripts (`s3_bucket_admin.ps1` / `.sh`), validé par le test d'intégration
AWS.

**c) Stderr natif sous `$ErrorActionPreference = 'Stop'`.**
Sous PowerShell 5.1, la sortie d'erreur d'une commande native devient une erreur
**terminante** quand `$ErrorActionPreference = 'Stop'`. Le `head-bucket` qui
teste l'existence d'un bucket (et écrit sur stderr en cas de 404) faisait donc
avorter le script. Corrigé en abaissant `$ErrorActionPreference` à
`SilentlyContinue` autour de la sonde uniquement.

**d) Chemins Windows passés à `bash`.**
Sous Windows, `bash` (MSYS/Git Bash) mange les antislashs des chemins absolus
(`C:\...` devient `C:...`). Les tests exécutent donc `bash` **depuis le
répertoire `scripts/`** avec un simple nom de fichier.

**e) `terraform_data.output` en lecture seule.**
Une piste de contournement (stocker l'OS dans `output` plutôt que `input`)
a été écartée : `output` est en **lecture seule**
(`Error: "output" attribute is read-only`).

**f) Identifiants temporaires.**
Les identifiants du Learner Lab expirent à chaque session ; le pipeline échoue
donc si les secrets GitHub ne sont pas rafraîchis. Contrainte documentée dans le
`README.md` (§7).

## 9. Améliorations possibles

- **Identité fédérée GitHub OIDC** : supprimer totalement les secrets AWS
  stockés dans GitHub (interdit dans le lab, à faire en production).
- **HTTPS réel** : domaine + certificat ACM pour activer l'écouteur 443 (déjà
  supporté par le module `load-balancer`, `enable_https = true`).
- **SSE-KMS** avec clé gérée et rotation, au lieu de SSE-S3.
- **AWS WAF** devant l'ALB et **AWS Shield** pour la protection DDoS.
- **Environnement `prod` réellement séparé** (compte AWS distinct, *OU*
  organisations) et rôles au moindre privilège par service.
- **Observabilité** : CloudWatch alarms, tableaux de bord, logs centralisés.
- **Tests plus poussés** : Terratest / `terraform test`, tests d'intégration de
  l'application, tests de charge.
- **Scan de sécurité IaC** : `tfsec`/`trivy` et `checkov` dans le pipeline.
- **Rotation des secrets** et stockage dans AWS Secrets Manager.

## 10. Annexes — captures d'écran

> À compléter au moment de la remise (voir `CHECKLIST.md` §10).

1. `aws sts get-caller-identity`
2. `terraform plan` (39 ressources)
3. `terraform apply`
4. Page Web de l'ALB — deux rafraîchissements montrant deux `Instance ID`
5. Console RDS : instance non publique
6. Console S3 : blocage de l'accès public activé
7. Onglet **Actions** de GitHub : pipeline vert
8. `tests/run-tests.ps1` : 24 tests réussis
