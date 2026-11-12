# Module `compute`

Crée le **Launch Template** et l'**Auto Scaling Group** des instances
applicatives (Amazon Linux 2023) placées dans les sous-réseaux privés.

## Ce qui est créé

| Ressource | Détail |
|-----------|--------|
| `data.aws_ssm_parameter` | AMI **Amazon Linux 2023** via le paramètre public `al2023-ami-kernel-default-x86_64` |
| `data.aws_ami` | **Repli** si les lectures SSM sont bloquées par le SCP (`use_ssm_ami = false`) |
| `aws_launch_template` | `user_data` via `templatefile`, **IMDSv2 obligatoire**, volume racine gp3 **chiffré**, profil d'instance du lab |
| `aws_autoscaling_group` | `health_check_type = "ELB"`, attaché au groupe de cibles, tags propagés aux instances |
| `aws_autoscaling_policy` | *Target tracking* sur la **CPU moyenne à 50 %** |

## Résolution de l'AMI

1. **Par défaut** (`use_ssm_ami = true`) : lecture du paramètre SSM public
   `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`.
2. **Repli** (`use_ssm_ami = false`) : `data.aws_ami` sur les AMI `al2023-ami-2023.*-x86_64`
   d'Amazon, si le SCP refuse la lecture des paramètres SSM.

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage |
| `project_name` | `string` | — (requis) | Nom affiché sur la page de démonstration |
| `app_subnet_ids` | `list(string)` | — (requis) | Sous-réseaux applicatifs (≥ 2, validé) |
| `app_security_group_id` | `string` | — (requis) | SG applicatif (module `security`) |
| `instance_profile_name` | `string` | — (requis) | Profil d'instance du lab (module `security`) |
| `target_group_arn` | `string` | — (requis) | Groupe de cibles de l'ALB |
| `instance_type` | `string` | `t3.micro` | Type d'instance (validé par regex) |
| `min_size` | `number` | `2` | Taille minimale (validé : ≥ 2) |
| `max_size` | `number` | `3` | Taille maximale (validé : ≥ `min_size`) |
| `desired_capacity` | `number` | `2` | Capacité souhaitée (validé : entre min et max) |
| `root_volume_size` | `number` | `8` | Taille du volume racine gp3 (Go) |
| `cpu_target_value` | `number` | `50` | Cible de CPU (%) du target tracking |
| `use_ssm_ami` | `bool` | `true` | Résolution de l'AMI par SSM (sinon `aws_ami`) |
| `tags` | `map(string)` | `{}` | Tags communs |

## Outputs

| Nom | Type | Description | Consommé par |
|-----|------|-------------|--------------|
| `asg_name` | `string` | Nom de l'Auto Scaling Group | environnement, scripts de test |
| `launch_template_id` | `string` | ID du Launch Template | documentation / rapport |

## Exemple d'utilisation

```hcl
module "compute" {
  source = "../../modules/compute"

  name_prefix             = local.name_prefix
  project_name            = var.project_name
  app_subnet_ids          = module.network.app_subnet_ids
  app_security_group_id   = module.security.app_security_group_id
  instance_profile_name   = module.security.lab_instance_profile_name
  target_group_arn        = module.load_balancer.target_group_arn
  instance_type           = var.instance_type
  min_size                = var.min_size
  max_size                = var.max_size
  desired_capacity        = var.desired_capacity
  use_ssm_ami             = var.use_ssm_ami
  tags                    = local.common_tags

  # Les instances ont besoin de la route NAT pour joindre SSM et les dépôts :
  depends_on = [module.network]
}
```

## Remarques

- **Aucun SSH** : l'administration se fait par **SSM Session Manager** via
  `LabInstanceProfile`.
- **IMDSv2 obligatoire** (`http_tokens = "required"`) : le `user_data` demande
  un jeton avant de lire l'instance id.
- Le volume racine est **chiffré** (`encrypted = true`, gp3).
- La dépendance à la route NAT est déclarée explicitement par l'environnement
  (`depends_on = [module.network]`) pour éviter une dépendance implicite.
