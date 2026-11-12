# Module `load-balancer`

Crée l'**Application Load Balancer** public, son **groupe de cibles** et ses
**écouteurs** (HTTP, et HTTPS optionnel).

## Ce qui est créé

| Ressource | Détail |
|-----------|--------|
| `aws_lb` | ALB `application`, `internet-facing`, placé dans les sous-réseaux publics |
| `aws_lb_target_group` | Cible HTTP sur le port 80, health check sur `/`, `healthy_threshold = 2`, `unhealthy_threshold = 2` (intervalle 30 s, timeout 5 s) |
| `aws_lb_listener` (http) | Port 80 : redirige vers 443 si HTTPS est activé, sinon transfère au groupe de cibles |
| `aws_lb_listener` (https) | Port 443, créé **uniquement si `enable_https = true`** (nécessite un certificat ACM) |

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage, ex. `cloud5-dev` |
| `vpc_id` | `string` | — (requis) | ID du VPC |
| `public_subnet_ids` | `list(string)` | — (requis) | Sous-réseaux publics (≥ 2, validé) |
| `alb_security_group_id` | `string` | — (requis) | SG de l'ALB (module `security`) |
| `enable_https` | `bool` | `false` | Active l'écouteur HTTPS + redirection 80 → 443 |
| `certificate_arn` | `string` | `""` | ARN du certificat ACM (obligatoire si `enable_https`) |
| `health_check_path` | `string` | `/` | Chemin du health check |
| `tags` | `map(string)` | `{}` | Tags communs |

## Outputs

| Nom | Type | Description | Consommé par |
|-----|------|-------------|--------------|
| `alb_dns_name` | `string` | DNS public de l'ALB | environnement (output), tests |
| `target_group_arn` | `string` | ARN du groupe de cibles | module `compute` |

## Exemple d'utilisation

```hcl
module "load_balancer" {
  source = "../../modules/load-balancer"

  name_prefix           = local.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  enable_https          = var.enable_https
  certificate_arn       = var.enable_https ? var.certificate_arn : ""
  tags                  = local.common_tags
}
```

## HTTPS (optionnel)

HTTPS nécessite un **nom de domaine** et un **certificat ACM validé** en
`us-east-1`. Dans le Learner Lab, cela suppose un domaine externe (Route 53 ou
autre) ; par défaut `enable_https = false` et l'accès se fait en HTTP. Voir
`docs/securite.md` et le README principal.
