# Coûts — ressources facturables et estimation

> ⚠️ **Estimations approximatives**, tarifs **on-demand us-east-1** à titre
> indicatif (base 730 h/mois). Les tarifs AWS évoluent : utilise le *AWS Pricing
> Calculator* pour un chiffrage officiel. L'objectif ici est de **classer** les
> postes de coût et de justifier les optimisations retenues.

## 1. Ressources facturables

| Ressource | Prix unitaire (approx.) | Remarque |
|-----------|-------------------------|----------|
| EC2 `t3.micro` | ~0,0104 $/h (~7,50 $/mois) | 2 instances en fonctionnement |
| EBS `gp3` (racine 8 Go) | ~0,08 $/Go-mois (~0,64 $/mois) | Chiffré |
| **NAT Gateway** | ~0,045 $/h (**~33 $/mois**) + 0,045 $/Go | **Poste le plus cher** |
| Application Load Balancer | ~0,0225 $/h (~16,50 $/mois) + LCU | |
| RDS `db.t3.micro` (MySQL) | ~0,017 $/h (~12,40 $/mois) | ×2 si **Multi-AZ** |
| Stockage RDS `gp2` (20 Go) | ~0,115 $/Go-mois (~2,30 $/mois) | |
| S3 Standard | ~0,023 $/Go-mois | Négligeable pour la démo |
| Elastic IP | **0 $** | Gratuite tant qu'elle est attachée |
| SSM Session Manager | 0 $ | Pas de coût d'accès |
| Données sortantes | ~0,09 $/Go | Faible pour une démo |

## 2. Estimation par environnement

| Poste | dev | test | prod |
|-------|-----|------|------|
| EC2 (2 × t3.micro) | ~15 $ | ~15 $ | ~15 $ |
| EBS racine (2 × 8 Go) | ~1,3 $ | ~1,3 $ | ~1,3 $ |
| NAT Gateway | ~33 $ (1) | ~33 $ (1) | **~66 $ (2)** |
| Application Load Balancer | ~17 $ | ~17 $ | ~17 $ |
| RDS (instance + stockage) | ~15 $ | ~15 $ | **~27 $ (Multi-AZ)** |
| S3 / divers | ~1 $ | ~1 $ | ~1 $ |
| **Total indicatif / mois** | **~82 $** | **~82 $** | **~128 $** |
| **Total indicatif / heure** | ~0,11 $ | ~0,11 $ | ~0,18 $ |

> Le **NAT Gateway** représente à lui seul **~40 %** du coût d'un environnement.
> C'est la raison du réglage `single_nat_gateway = true` en `dev`/`test`.

## 3. Coût réel pendant la démonstration

Les ressources sont facturées **à l'heure**. Un environnement `dev` déployé
seulement le temps de la démonstration (par exemple **4 heures**) coûte environ
**0,45 $** — négligeable. En revanche, laisser les **trois** environnements
tourner **24 h/24 pendant un mois** consommerait **~290 $**, soit bien plus que
le crédit d'un AWS Academy Learner Lab.

**Règle d'or : `terraform destroy` après chaque démonstration.**

## 4. Optimisations déjà appliquées

| Choix | Économie |
|-------|----------|
| `t3.micro` / `db.t3.micro` partout | Instances les moins chères éligibles au lab |
| **Un seul NAT Gateway** en `dev`/`test` | ~33 $/mois économisés par environnement |
| **Pas de NAT** pour les sous-réseaux base de données | La RDS n'a pas de route sortante (et c'est plus sûr) |
| Rétention de sauvegardes courte en `dev`/`test` (1–3 j) | Réduit le stockage de snapshots |
| `skip_final_snapshot = true` en `dev`/`test` | Pas de snapshot conservé après destruction |
| Cycle de vie S3 (abandon multipart + expiration des versions non courantes) | Évite l'accumulation d'objets |
| Un seul ALB, un seul bucket S3 | Mutualisation |

## 5. Suivi du budget

- Consulter **AWS Cost Explorer** / **Billing** dans la console.
- Le crédit restant du Learner Lab est visible dans l'onglet *AWS Details*.
- Le pipeline CI/CD ne déploie par défaut que **`dev`** (voir `README.md` §7) :
  cela évite de multiplier les environnements facturés à chaque `push`.
