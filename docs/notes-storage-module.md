# Note de conception — module `storage` (phase 4)

> **Statut : conception validée, aucun code écrit.** Ce document fige les décisions
> avant l'implémentation du module `modules/storage`.
>
> 🔴 **Décision en attente de ta validation** : l'approche cross-platform (§4) doit
> être confirmée avant que j'écrive le module.

## 1. Contrainte

Le SCP du Learner Lab refuse `s3:GetBucketObjectLockConfiguration`. La ressource
`aws_s3_bucket` échoue donc à la création, quelle que soit la version du provider
(voir `README.md` §5 et `docs/securite.md` §6).

## 2. Solution : bucket créé via `terraform_data` + `local-exec`

Le bucket lui-même est créé **hors du provider S3**, par un appel AWS CLI dans un
`terraform_data`, afin qu'il reste **dans le state Terraform** (contrairement au
bucket d'état, créé par le script PowerShell).

```hcl
# modules/storage/main.tf (aperçu — non écrit)
resource "terraform_data" "bucket" {
  # Le nom du bucket (et la région) sont stockés dans input.
  # input est la SEULE valeur lisible par le provisioner de destruction.
  input = {
    bucket = local.bucket_name
    region = var.aws_region
  }

  provisioner "local-exec" {
    # create : aws s3api create-bucket (PAS de LocationConstraint en us-east-1)
    command = <voir §4>
  }

  provisioner "local-exec" {
    when    = destroy
    # Le provisioner de destruction ne peut référencer QUE self.
    # => on lit self.input.bucket / self.input.region, jamais var.*
    command = <voir §4>
  }
}
```

### Règles retenues

1. **Création** : `aws s3api create-bucket --bucket <name> --region us-east-1`,
   **sans** `--create-bucket-configuration` (interdit en `us-east-1`).
2. **Destruction** : le provisioner `when = destroy` ne peut référencer que
   `self`. Toutes les valeurs nécessaires sont donc dans `self.input`.
   Le script de destruction doit :
   1. supprimer **toutes les versions** des objets (`list-object-versions`
      → `delete-objects`) ;
   2. supprimer **tous les delete markers** ;
   3. **puis** supprimer le bucket (`delete-bucket`).
   Sans les étapes 1 et 2, un bucket versionné refuse d'être supprimé.
3. **Sous-ressources gérées par Terraform** (référencent la sortie de
   `terraform_data`) :
   - `aws_s3_bucket_versioning`
   - `aws_s3_bucket_server_side_encryption_configuration`
   - `aws_s3_bucket_public_access_block`
   - `aws_s3_bucket_lifecycle_configuration`
   Elles lisent `terraform_data.bucket.output.bucket`.

### ⚠️ Piège connu de `terraform_data`

`terraform_data` **remplace** la ressource quand `input` change → cela
déclencherait le provisioner de destruction (suppression du bucket !). Comme
`input` ne contient que le nom (stable) et la région (stable), le risque est
nul en pratique, mais **il ne faut jamais mettre une valeur variable** dans
`input` (ex. un timestamp).

## 3. Repli si le SCP bloque aussi les sous-ressources

Si `aws_s3_bucket_versioning`, `_server_side_encryption_configuration`,
`_public_access_block` ou `_lifecycle_configuration` sont également refusées
(elles appellent elles aussi des API S3 de lecture), le repli est le **même
contournement** :

- `aws s3api put-bucket-versioning`
- `aws s3api put-bucket-encryption`
- `aws s3api put-public-access-block`
- `aws s3api put-bucket-lifecycle-configuration`

→ soit dans le **même** `local-exec` de création, soit dans des `terraform_data`
supplémentaires. **On ne le saura qu'en phase 4**, en testant `terraform apply`.
Je te préviendrai à ce moment-là.

## 4. Approche cross-platform pour `local-exec` — **à valider**

### Le problème

`local-exec` n'utilise pas PowerShell : Terraform exécute la commande via
`cmd.exe` sous Windows et `/bin/sh` sous Linux (GitHub Actions `ubuntu-latest`).
Or supprimer **toutes les versions** d'un bucket exige une **boucle**
(liste → suppression), dont la syntaxe diffère totalement entre `cmd.exe` et `sh`.
Une commande unique ne peut donc pas être valide sur les deux OS.

### Option A — **recommandée** : commande conditionnée par l'OS + deux scripts

Détection de l'OS à la compilation (astuce fiable) :

```hcl
locals {
  # Sous Windows, pathexpand("~") = "C:\Users\..." ; sous Linux = "/home/..."
  is_windows = substr(pathexpand("~"), 0, 1) != "/"
}
```

Puis, pour chaque provisioner :

```hcl
command = local.is_windows
  ? "powershell -NoProfile -ExecutionPolicy Bypass -File \"${path.module}/../../scripts/s3_bucket_admin.ps1\" -Action create -Bucket ${self.input.bucket} -Region ${self.input.region}"
  : "bash \"${path.module}/../../scripts/s3_bucket_admin.sh\" create ${self.input.bucket} ${self.input.region}"
```

Deux petits scripts `scripts/s3_bucket_admin.ps1` et `scripts/s3_bucket_admin.sh`
implémentent `create` et `destroy` (suppression des versions + delete markers +
bucket). La logique métier est ainsi **hors de Terraform**, testable seule.

**Avantages**

- N'utilise que des outils **garantis présents** : `powershell.exe` (livré avec
  Windows) et `bash` (présent sur `ubuntu-latest`) ; + l'AWS CLI déjà requise.
- Aucune dépendance supplémentaire (ni PowerShell 7, ni Python).
- Scripts réutilisables par les tests PowerShell (phase 7).

**Inconvénients (trade-off)**

- **Logique dupliquée** en `.ps1` et `.sh` : il faut les maintenir en phase.
- Repose sur l'heuristique `pathexpand("~")` (fiable en pratique, mais c'est une
  heuristique et non une détection officielle d'OS).
- Le provisioner de destruction ne pouvant lire que `self.input`, **toutes** les
  valeurs utiles doivent y être stockées.

### Option B — forcer `pwsh` (PowerShell 7) partout

`interpreter = ["pwsh", "-NoProfile", "-Command"]` + un seul script `.ps1`.

- ➕ Un seul script.
- ➖ Exige **PowerShell 7** (`pwsh`) installé localement sous Windows ; Windows
  ne fournit que `powershell.exe` (5.1) par défaut. `ubuntu-latest` a bien `pwsh`.
  Dépendance locale non garantie → écartée.

### Option C — script Python unique

- ➕ Un seul script.
- ➖ Nom de l'interpréteur différent (`python` vs `python3`), et `boto3` non
  garanti. Dépendance supplémentaire → écartée.

### Recommandation

**Option A.** Elle ne dépend que d'outils présents par défaut sur les deux
plateformes et garde la logique testable.

## 5. Décisions à confirmer

- [ ] Option A (deux scripts + détection OS) pour le cross-platform.
- [ ] `input` de `terraform_data` = objet `{ bucket, region }`.
- [ ] Repli automatique vers `local-exec` pour les sous-ressources **si** le SCP
      les bloque (je te préviendrai au `apply` de phase 4).
