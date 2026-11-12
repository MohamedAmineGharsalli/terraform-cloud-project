# Module `network`

Crée le réseau d'une plateforme Web hautement disponible sur **2 zones de
disponibilité** : VPC, sous-réseaux, Internet Gateway, NAT Gateway(s) et tables
de routage.

## Ce qui est créé

| Ressource | Détail |
|-----------|--------|
| `aws_vpc` | VPC avec DNS support et DNS hostnames activés |
| `aws_subnet` (×6) | 2 publics (ALB), 2 privés applicatifs (EC2), 2 privés base de données (RDS) — créés via `for_each` |
| `aws_internet_gateway` | Passerelle Internet du VPC |
| `aws_eip` + `aws_nat_gateway` | **1 NAT partagé** si `single_nat_gateway = true`, sinon **1 par AZ** |
| `aws_route_table` | Table publique (route vers l'IGW), une table par sous-réseau applicatif (route vers le NAT), une table DB **sans route Internet** |
| `aws_route` / `aws_route_table_association` | Routage et associations, créés via `for_each` |

### Plan d'adressage (avec `vpc_cidr = 10.20.0.0/16`)

| Sous-réseau | CIDR | Rôle |
|-------------|------|------|
| `public-a` / `public-b` | `10.20.1.0/24` / `10.20.2.0/24` | ALB |
| `app-a` / `app-b` | `10.20.11.0/24` / `10.20.12.0/24` | Instances applicatives (sortie via NAT) |
| `db-a` / `db-b` | `10.20.21.0/24` / `10.20.22.0/24` | RDS (aucune route vers Internet) |

Les CIDR sont calculés avec `cidrsubnet()` : changer `vpc_cidr` décale tout le
plan d'adressage.

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage, ex. `cloud5-dev` |
| `vpc_cidr` | `string` | `10.20.0.0/16` | Bloc CIDR du VPC (validé : CIDR valide, préfixe ≤ /16) |
| `single_nat_gateway` | `bool` | `true` | `true` = 1 NAT partagé (dev/test), `false` = 1 NAT par AZ (prod) |
| `tags` | `map(string)` | `{}` | Tags communs appliqués à toutes les ressources |

## Outputs

| Nom | Type | Description | Consommé par |
|-----|------|-------------|--------------|
| `vpc_id` | `string` | ID du VPC | `security`, `load-balancer`, `database` |
| `public_subnet_ids` | `list(string)` | IDs des sous-réseaux publics (triés par AZ) | `load-balancer` |
| `app_subnet_ids` | `list(string)` | IDs des sous-réseaux applicatifs (triés par AZ) | `compute` |
| `db_subnet_ids` | `list(string)` | IDs des sous-réseaux base de données (triés par AZ) | `database` |

## Exemple d'utilisation

```hcl
module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}
```

## Remarques

- Les sous-réseaux DB n'ont **aucune route vers Internet** (seule la route
  locale du VPC existe) : la base ne peut ni atteindre ni être atteinte depuis
  Internet.
- En `us-east-1`, la création du bucket/des ressources ne pose pas de problème
  de `LocationConstraint`, mais ce module n'est pas concerné.
- Les deux premiers AZ de la région (`opt-in-not-required`) sont utilisés.
