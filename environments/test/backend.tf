terraform {
  # Backend S3 distant : etat Terraform centralise, chiffre et verrouille.
  #
  # Le nom du bucket est fige ici car un bloc backend ne peut PAS utiliser de
  # variable Terraform. Le bucket est cree HORS Terraform par
  # scripts/bootstrap-backend.ps1 (voir README.md), car le SCP du Learner Lab
  # interdit l'action s3:GetBucketObjectLockConfiguration utilisee par la
  # ressource aws_s3_bucket.
  #
  # Autre equipe : remplace la valeur de "bucket" par le nom de TON bucket
  # d'etat (cloud5-tfstate-<ton_account_id>) avant de lancer terraform init.
  backend "s3" {
    bucket       = "cloud5-tfstate-766760778474"
    key          = "test/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
