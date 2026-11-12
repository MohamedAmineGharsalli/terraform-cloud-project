# Module `storage`

Crée un **bucket S3 privé** (versioning, chiffrement, blocage de l'accès public,
cycle de vie), malgré une **limitation du Learner Lab**.

## Pourquoi un `local-exec` ?

Le **SCP** du AWS Academy Learner Lab refuse l'action
`s3:GetBucketObjectLockConfiguration`. Or la ressource `aws_s3_bucket` lit ce
réglage : elle échoue donc **quelle que soit la version du provider** (voir
`README.md` §5 et `docs/securite.md` §6).

Le bucket est donc créé **hors du provider S3**, par un appel **AWS CLI** dans un
`terraform_data` : il reste ainsi **dans le state Terraform** (contrairement au
bucket d'état, créé par `scripts/bootstrap-backend.ps1`).

```
terraform_data.bucket  --local-exec-->  scripts/s3_bucket_admin.{ps1,sh}  --AWS CLI-->  S3
        │
        └── output.bucket ──> aws_s3_bucket_versioning / _server_side_encryption_configuration
                              / _public_access_block / _lifecycle_configuration
```

### Cross-platform

`local-exec` n'utilise pas PowerShell : Terraform exécute la commande via
`cmd.exe` sous Windows et `/bin/sh` sous Linux (CI `ubuntu-latest`).

- **Création** : l'OS est détecté **à la compilation** :

  ```hcl
  is_windows = substr(pathexpand("~"), 0, 1) != "/"
  ```

  puis la commande appelle `scripts/s3_bucket_admin.ps1` (via `powershell.exe`)
  sous Windows, ou `scripts/s3_bucket_admin.sh` (via `bash`) sous Linux.

- **Destruction** : la commande est **indépendante de l'OS**. Elle essaie
  PowerShell puis bascule sur bash grâce à `||` :

  ```hcl
  command = "powershell ... s3_bucket_admin.ps1 -Action destroy ... || bash \"...\" s3_bucket_admin.sh destroy ..."
  ```

> ⚠️ **Piège Terraform** : un provisioner de **destruction** ne peut référencer
> que `self` (et `path.module`), donc `is_windows` n'est **pas** lisible au
> moment de la destruction. C'est précisément pour cela que la commande de
> destruction est OS-agnostique : `input` ne contient **que** le nom du bucket
> et la région.
>
> Conséquence importante : **appliquer sous Windows et détruire sous Linux (CI)
> ne modifie pas `input`**, donc `terraform_data` n'est **pas recréé** et le
> bucket n'est **pas supprimé par accident**.

### Scripts

`scripts/s3_bucket_admin.ps1` et `scripts/s3_bucket_admin.sh` implémentent :

- `create` : `aws s3api create-bucket` (**idempotent**, sans
  `LocationConstraint` en `us-east-1`) ;
- `destroy` : suppression de **toutes les versions** puis de **tous les delete
  markers** (`list-object-versions` → `delete-object`), puis `delete-bucket`.
  Sans cela, un bucket versionné refuse d'être supprimé.
  - ⚠️ `aws ... --output text` imprime la chaîne littérale **`None`** (et non
    une chaîne vide) quand la requête ne renvoie rien : les deux scripts
    l'ignorent explicitement, sinon la boucle ne se terminerait jamais.

La logique métier est ainsi **hors de Terraform** et testable seule (phase 7).

## Sous-ressources gérées par Terraform

| Ressource | Rôle |
|-----------|------|
| `aws_s3_bucket_versioning` | Versioning (`Enabled`) |
| `aws_s3_bucket_server_side_encryption_configuration` | Chiffrement `AES256` (SSE-S3) par défaut, `aws:kms` possible |
| `aws_s3_bucket_public_access_block` | Les 4 réglages de blocage public activés |
| `aws_s3_bucket_lifecycle_configuration` | Abandon des uploads multipart incomplets + expiration des versions non courantes |

Ces sous-ressources appellent des API S3 **différentes** de celle bloquée par le
SCP. **Repli** : si l'une d'elles était aussi refusée au `apply`, la même
technique (`aws s3api put-bucket-versioning`, `put-bucket-encryption`,
`put-public-access-block`, `put-bucket-lifecycle-configuration`) serait
appliquée dans `local-exec` (voir `docs/notes-storage-module.md` §3).

## Nom du bucket

Par défaut : `<name_prefix>-storage-<account_id>` (unique au monde). Peut être
forcé via `bucket_name`.

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage, ex. `cloud5-dev` |
| `bucket_name` | `string` | `""` | Nom explicite (sinon calculé) |
| `aws_region` | `string` | `us-east-1` | Région du bucket (doit correspondre au provider) |
| `enable_versioning` | `bool` | `true` | Active le versioning |
| `sse_algorithm` | `string` | `AES256` | `AES256`, `aws:kms` ou `aws:kms:dsse` (validé) |
| `kms_master_key_id` | `string` | `""` | ARN de la clé KMS (requis si `aws:kms`) |
| `block_public_access` | `bool` | `true` | Active les 4 réglages de blocage public |
| `enable_lifecycle` | `bool` | `true` | Active la configuration de cycle de vie |
| `noncurrent_version_expiration_days` | `number` | `30` | Expiration des versions non courantes (0 = désactivé) |
| `tags` | `map(string)` | `{}` | Tags communs |

## Outputs

| Nom | Type | Description |
|-----|------|-------------|
| `bucket_id` | `string` | Nom du bucket |
| `bucket_arn` | `string` | ARN du bucket |
| `bucket_domain_name` | `string` | Nom de domaine global |
| `bucket_regional_domain_name` | `string` | Nom de domaine régional |

## Exemple d'utilisation

```hcl
module "storage" {
  source = "../../modules/storage"

  name_prefix         = local.name_prefix
  aws_region          = var.aws_region
  enable_versioning   = true
  block_public_access = true
  tags                = local.common_tags
}
```

## Prérequis

- **AWS CLI** installée et configurée (mêmes identifiants que le provider).
- `powershell.exe` (Windows) ou `bash` (Linux) — présents par défaut.
