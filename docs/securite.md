# Sécurité — choix, justifications et limites

> Document **définitif**. Il couvre la chaîne de Security Groups, l'accès sans
> SSH, IMDSv2, le chiffrement, la gestion des secrets, et la limitation du
> Learner Lab (SCP).

## 1. Chaîne de Security Groups (moindre privilège réseau)

| Security Group | Entrée autorisée | Justification |
|----------------|------------------|---------------|
| `alb` | 80 (et 443 si `enable_https`) depuis `0.0.0.0/0` | Seul point d'entrée public |
| `app` | 80 **uniquement depuis le SG `alb`** (référence de SG) | Les instances ne sont jamais joignables directement depuis Internet |
| `db` | 3306 **uniquement depuis le SG `app`** (référence de SG) | La base n'accepte que les instances applicatives |

L'utilisation de **références de Security Groups** (et non de CIDR) garantit que
les règles suivent automatiquement les instances, sans dépendre d'adresses IP.

## 2. Pas de SSH — accès via SSM Session Manager

Aucun port **22** n'est ouvert, ni sur le Security Group de l'ALB, ni sur celui
des instances. L'administration se fait par **AWS Systems Manager Session
Manager** : les instances portent le *instance profile* `LabInstanceProfile`, qui
autorise l'agent SSM à s'enregistrer.

Avantages :

- **Surface d'attaque réduite** : aucun service d'administration exposé à
  Internet, aucun *bastion* à maintenir.
- **Pas de gestion de clés** : plus de paire SSH à générer, distribuer, révoquer.
- **Traçabilité** : les sessions SSM sont journalisables (audit).
- **Accès privé** : la session passe par l'agent SSM (sortie via le NAT), sans
  ouvrir de port entrant.

## 3. IMDSv2 obligatoire, volumes chiffrés

**IMDSv2.** Le *Launch Template* impose `http_tokens = "required"`
(`modules/compute/main.tf`). Le service de métadonnées n'accepte donc plus que
les requêtes **avec jeton** (session-oriented). Cela bloque la principale classe
d'attaques **SSRF** qui exploite IMDSv1 pour voler les identifiants du rôle de
l'instance. Le script `scripts/user_data.sh` obtient explicitement un jeton
(`PUT /latest/api/token`) avant de lire les métadonnées.

**Volumes chiffrés.** Le volume racine est un **gp3 chiffré**
(`encrypted = true`), `delete_on_termination = true`. Le chiffrement s'applique
au repos comme aux snapshots.

## 4. Chiffrement au repos et de l'état

| Élément | Chiffrement |
|---------|-------------|
| Volume EBS des instances | `gp3` chiffré (clé AWS managée) |
| Base de données RDS | `storage_encrypted = true` |
| Bucket S3 applicatif | SSE-S3 (`AES256`) par défaut |
| Bucket d'état Terraform | SSE-S3 (`AES256`) + `encrypt = true` dans le backend |
| État en transit | HTTPS (SDK AWS), politique de bucket refusant le non-TLS |

Les snapshots RDS et les sauvegardes héritent du chiffrement du volume.

## 5. Gestion des secrets

Principe : **aucun secret n'est écrit dans le dépôt**.

| Secret | Local | CI/CD |
|--------|-------|-------|
| Mot de passe RDS | variable d'environnement `TF_VAR_db_password` | secret GitHub `DB_PASSWORD` |
| Clé d'accès AWS | profil/credentials locaux (jamais versionnés) | secret `AWS_ACCESS_KEY_ID` |
| Secret d'accès AWS | idem | secret `AWS_SECRET_ACCESS_KEY` |
| Jeton de session AWS | idem | secret `AWS_SESSION_TOKEN` |

- La variable `db_password` est déclarée `sensitive = true` : sa valeur n'apparaît
  pas dans les sorties Terraform.
- `.gitignore` exclut `*.tfvars`, `.env`, `.aws/`, `*.pem`, etc. Les fichiers
  `terraform.tfvars.example` ne contiennent **que des exemples sans secret**.
- Les identifiants du Learner Lab sont **temporaires** : ils sont fournis au
  pipeline par les secrets GitHub et rafraîchis à chaque session.

## 6. Limitation du Learner Lab (SCP) et impact sécurité

### 6.1 Le problème

Le **SCP** de l'AWS Academy Learner Lab refuse l'action
`s3:GetBucketObjectLockConfiguration`. La ressource `aws_s3_bucket` du provider
`hashicorp/aws` appelle cette action pendant le cycle `Create`/`Read` : le bucket
est bien créé côté AWS, mais la lecture échoue et Terraform considère l'opération
comme un échec. Ce comportement est **indépendant de la version du provider**
(testé avec `5.100.0` et `5.40.0`).

Autres contraintes du lab, toutes documentées comme des **écarts assumés** :

- **Création de rôles / politiques / fournisseurs OIDC interdite.** On ne peut
  donc pas créer de rôle IAM dédié au pipeline ni au moindre privilège applicatif.
  → On utilise les ressources **préexistantes** du lab :
  `data "aws_iam_role" "lab_role"` (`LabRole`) et
  `data "aws_iam_instance_profile" "lab_instance_profile"` (`LabInstanceProfile`).
- **Identifiants temporaires** (clé + secret + jeton de session) : pas
  d'authentification par identité fédérée côté CI/CD.
- **Régions limitées** à `us-east-1` / `us-west-2`.

### 6.2 Contournement retenu

Le bucket S3 (état Terraform, puis en phase 4 le bucket applicatif) est créé et
sécurisé **hors Terraform**, par un script **AWS CLI idempotent**
(`scripts/bootstrap-backend.ps1`) qui applique les mêmes protections que la
ressource Terraform aurait appliquées :

1. versioning activé ;
2. chiffrement par défaut **SSE-S3 (AES256)** + bucket key ;
3. **blocage total de l'accès public** (les 4 options) ;
4. **politique de bucket** refusant toute requête non TLS
   (`aws:SecureTransport = false`).

### 6.3 Ce que l'on ferait dans un vrai compte AWS

| Contrainte du lab | Solution en production |
|-------------------|------------------------|
| `s3:GetBucketObjectLockConfiguration` refusé | Aucun problème : la ressource `aws_s3_bucket` complète fonctionne, y compris Object Lock / WORM |
| Rôles IAM interdits | Rôle IAM applicatif dédié (moindre privilège), instance profile dédié, **pas** de rôle de lab partagé |
| OIDC interdit | **Identité fédérée GitHub OIDC** (`aws_iam_openid_connect_provider`) + rôle au moindre privilège : plus aucun secret AWS stocké dans GitHub |
| Identifiants temporaires manuels | Rôle fédéré à courte durée, aucun `AWS_SECRET_ACCESS_KEY` en dur |
| Bucket créé hors Terraform | Bucket **géré par Terraform** (état traçable, `destroy` complet), ou ressource de bootstrap dédiée |
| Pas de KMS dédié | Chiffrement **SSE-KMS** avec clé gérée et rotation, politique de clé restrictive |
| Région imposée | Région choisie selon la résidence des données / la latence |

> Ces écarts sont volontaires et **imposés par l'environnement pédagogique** ;
> ils sont à mentionner explicitement dans le rapport (`docs/rapport.md`).
