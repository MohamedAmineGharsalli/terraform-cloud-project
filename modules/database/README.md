# Module `database`

Crée une instance **RDS MySQL privée**, chiffrée au repos, joignable
**uniquement** depuis les instances applicatives.

## Ce qui est créé

| Ressource | Détail |
|-----------|--------|
| `aws_db_subnet_group` | Groupe de sous-réseaux **privés** (sous-réseaux DB du module `network`, sans route Internet) |
| `aws_db_instance` | MySQL, `storage_encrypted = true`, `publicly_accessible = false`, `multi_az` piloté par variable |

## Sécurité

- **Aucun accès public** : `publicly_accessible = false`, et le Security Group
  `db-sg` n'autorise le port 3306 **que depuis le SG applicatif** (chaîne de
  sécurité du module `security`).
- **Sous-réseaux privés** : les sous-réseaux DB n'ont **aucune route vers
  Internet** (module `network`).
- **Chiffrement au repos** : `storage_encrypted = true`.
- **Mot de passe** : jamais dans le code. Fourni via
  `$env:TF_VAR_db_password` (local) ou le secret GitHub `DB_PASSWORD` (CI).
  La variable est `sensitive = true`.

## Inputs

| Nom | Type | Défaut | Description |
|-----|------|--------|-------------|
| `name_prefix` | `string` | — (requis) | Préfixe de nommage, ex. `cloud5-dev` |
| `db_subnet_ids` | `list(string)` | — (requis) | Sous-réseaux DB (≥ 2, validé) |
| `db_security_group_id` | `string` | — (requis) | SG de la base (module `security`) |
| `db_name` | `string` | `cloud5db` | Nom de la base initiale (validé) |
| `db_username` | `string` | `cloud5admin` | Utilisateur maître (validé) |
| `db_password` | `string` | — (requis) | Mot de passe maître (**sensible**, 8–41 caractères) |
| `engine` | `string` | `mysql` | Moteur |
| `engine_version` | `string` | `8.0` | Version du moteur |
| `instance_class` | `string` | `db.t3.micro` | Classe d'instance (validée) |
| `allocated_storage` | `number` | `20` | Stockage alloué (Go, ≥ 20) |
| `max_allocated_storage` | `number` | `0` | Plafond d'autoscaling du stockage (`0` = désactivé) |
| `storage_type` | `string` | `gp3` | Type de stockage |
| `multi_az` | `bool` | `false` | `true` en prod (haute disponibilité) |
| `backup_retention_period` | `number` | `7` | Jours de sauvegardes automatiques (0–35) |
| `backup_window` | `string` | `03:00-04:00` | Fenêtre de sauvegarde (UTC) |
| `maintenance_window` | `string` | `sun:04:30-sun:05:30` | Fenêtre de maintenance (UTC) |
| `skip_final_snapshot` | `bool` | `true` | `true` en dev/test, `false` en prod |
| `final_snapshot_identifier` | `string` | `""` | Snapshot final (requis si `skip_final_snapshot = false`) |
| `deletion_protection` | `bool` | `false` | `true` en prod |
| `apply_immediately` | `bool` | `false` | Applique les changements immédiatement |
| `tags` | `map(string)` | `{}` | Tags communs |

## Outputs

| Nom | Type | Description | Consommé par |
|-----|------|-------------|--------------|
| `db_instance_id` | `string` | Identifiant de l'instance | environnement, tests |
| `db_instance_arn` | `string` | ARN de l'instance | documentation |
| `db_address` | `string` | Hôte DNS (sans port) | scripts de test |
| `db_endpoint` | `string` | Endpoint `host:port` | environnement (output) |
| `db_port` | `number` | Port | tests |
| `db_name` | `string` | Nom de la base | tests |
| `db_resource_id` | `string` | Identifiant immuable | documentation |
| `db_subnet_group_name` | `string` | Nom du groupe de sous-réseaux | documentation |

## Exemple d'utilisation

```hcl
module "database" {
  source = "../../modules/database"

  name_prefix          = local.name_prefix
  db_subnet_ids        = module.network.db_subnet_ids
  db_security_group_id = module.security.db_security_group_id

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  instance_class          = var.db_instance_class
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention
  skip_final_snapshot     = var.db_skip_final_snapshot
  deletion_protection     = var.db_deletion_protection

  tags = local.common_tags
}
```

## Remarques

- `db.t3.micro` et `allocated_storage = 20` restent dans le budget du lab.
- En **prod**, utiliser `multi_az = true`, `deletion_protection = true` et
  `skip_final_snapshot = false` avec un `final_snapshot_identifier`.
- Deux `precondition` empêchent les configurations incohérentes (snapshot final
  manquant, autoscaling inférieur au stockage alloué).
