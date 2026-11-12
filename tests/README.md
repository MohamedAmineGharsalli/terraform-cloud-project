# Tests — projet `cloud5`

Suite de tests **sans déploiement** : elle vérifie le formatage et la validité du
code Terraform, la robustesse des scripts, et (en option) le cycle de vie réel
d'un bucket S3 temporaire.

## Exécution

```powershell
# Suites par défaut (terraform + scripts) : aucun identifiant AWS requis
./tests/run-tests.ps1

# Tout, y compris les tests AWS (nécessite des identifiants Learner Lab valides)
./tests/run-tests.ps1 -Suite all -IncludeAws

# Une seule suite
./tests/run-tests.ps1 -Suite terraform
./tests/run-tests.ps1 -Suite scripts
./tests/run-tests.ps1 -Suite aws
```

Le script renvoie le code de sortie **0** si tout passe, **1** sinon (utilisable
en CI). Un journal est écrit dans `docs/tests/run-tests.log` (désactivable avec
`-NoLog`).

> Sur Linux/macOS, remplacer `./tests/run-tests.ps1` par
> `pwsh tests/run-tests.ps1`.

## Suites

| Suite | Identifiants AWS | Contenu |
|-------|------------------|---------|
| `terraform` | non | `terraform fmt -check -recursive` ; `terraform validate` des **6 modules** et des **3 environnements** (`init -backend=false`) ; rendu du template `scripts/user_data.sh` via `terraform console` |
| `scripts` | non | fins de ligne **LF** des `*.sh` ; syntaxe `bash -n` ; présence du **jeton IMDSv2** et du placeholder `${project_name}` dans `user_data.sh` ; rejet des arguments invalides par `s3_bucket_admin.ps1` / `s3_bucket_admin.sh` |
| `aws` | **oui** | `aws sts get-caller-identity` ; présence du **bucket d'état** ; **cycle de vie complet** d'un bucket versionné temporaire (création → 2 versions + 1 delete marker → destruction → bucket absent) |

## Ce que la suite AWS garantit

Le test « cycle de vie » reproduit exactement ce que fait le module `storage` au
`apply`/`destroy` :

1. `s3_bucket_admin.ps1 -Action create` crée le bucket ;
2. le versioning est activé et des versions + un **delete marker** sont créés ;
3. `-Action destroy` supprime **toutes les versions** puis **tous les delete
   markers**, puis le bucket ;
4. `head-bucket` confirme que le bucket n'existe plus.

Il valide donc la logique qui ne peut pas être couverte par `terraform validate`
(le contournement du SCP, la boucle de suppression, la gestion du littéral
`None` renvoyé par l'AWS CLI).

Le bucket de test (`cloud5-test-tmp-<account_id>`) est **supprimé dans tous les
cas** (`finally`), même si le test échoue.

## Intégration continue

Le job `test` du workflow `.github/workflows/terraform.yml` exécute
`run-tests.ps1 -Suite scripts -NoLog` sur `ubuntu-latest` (les suites
`terraform` et `aws` y sont déjà couvertes par les jobs `fmt`, `validate`,
`plan` et `apply`).
