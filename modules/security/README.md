# Module `security`

Crée les **trois Security Groups chaînés** de la plateforme et expose les
ressources IAM **préexistantes** du AWS Academy Learner Lab.

## Chaîne de sécurité

```
Internet --80/443--> [alb-sg] --80--> [app-sg] --3306--> [db-sg]
```

Chaque maillon est autorisé par **référence de Security Group** (jamais par
CIDR), ce qui garantit qu'aucun autre composant ne peut atteindre les instances
applicatives ou la base.

| Security Group | Entrée | Sortie |
|----------------|--------|--------|
| `alb-sg` | TCP 80 depuis `0.0.0.0/0` (+ TCP 443 si `enable_https`) | tout |
| `app-sg` | TCP 80 depuis `alb-sg` uniquement | tout |
| `db-sg` | TCP 3306 depuis `app-sg` uniquement | tout (défaut AWS) |

## IAM dans le Learner Lab

Créer des rôles, politiques ou profils d'instance est **interdit** dans le
Learner Lab. Le module lit donc les ressources fournies par le lab via des
**data sources** :

- `data.aws_iam_role.lab_role` (rôle `LabRole`) ;
- `data.aws_iam_instance_profile.lab_instance_profile` (profil
  `LabInstanceProfile`).

> Le principe du moindre privilège est **limité par le lab** : toutes les
> instances partagent le rôle `LabRole`. Dans un vrai compte AWS, on créerait un
> rôle dédié au moindre privilège et on utiliserait OIDC pour la CI. Voir
> `docs/securite.md`.

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage, ex. `cloud5-dev` |
| `vpc_id` | `string` | — (requis) | ID du VPC (sortie du module `network`) |
| `enable_https` | `bool` | `false` | Autorise HTTPS (443) sur le SG de l'ALB |
| `lab_role_name` | `string` | `LabRole` | Nom du rôle préexistant du lab |
| `lab_instance_profile_name` | `string` | `LabInstanceProfile` | Nom du profil d'instance préexistant du lab |
| `tags` | `map(string)` | `{}` | Tags communs appliqués à toutes les ressources |

## Outputs

| Nom | Type | Description | Consommé par |
|-----|------|-------------|--------------|
| `alb_security_group_id` | `string` | ID du SG de l'ALB | `load-balancer` |
| `app_security_group_id` | `string` | ID du SG applicatif | `compute` |
| `db_security_group_id` | `string` | ID du SG de la base | `database` |
| `lab_instance_profile_name` | `string` | Nom du profil d'instance du lab | `compute` |
| `lab_role_arn` | `string` | ARN du rôle `LabRole` (documentation/vérification) | environnement (output informatif) |

## Exemple d'utilisation

```hcl
module "security" {
  source = "../../modules/security"

  name_prefix   = local.name_prefix
  vpc_id        = module.network.vpc_id
  enable_https  = var.enable_https
  tags          = local.common_tags
}
```

## Remarques

- **Aucun accès SSH** n'est ouvert : l'administration passe par **SSM Session
  Manager** (via `LabInstanceProfile`). Voir `docs/securite.md`.
- Le port 443 n'est ouvert que si `enable_https = true` (nécessite un
  certificat ACM et un domaine).
