#!/usr/bin/env bash
# ==============================================================================
# REPÚBLICA DIGITAL DE NOVATLANTIS — BOOTSTRAP DAY-0 DA FUNDAÇÃO GITOPS & CI/CD
# Organização: https://github.com/LATAM-PS-CE-Team
# Repositório: novatlantis-iac
# Objetivo: Executado UMA única vez no projeto GCP para:
#   1. Habilitar APIs essenciais (Cloud Build, Secret Manager, Run, AlloyDB, IAM)
#   2. Criar o Bucket GCS de Estado Remoto do Terraform (gs://novatlantis-tfstate)
#      com versionamento e trava de concorrência (State Locking) para 'iac/dev' e 'iac/prod'
#   3. Criar a Service Account dedicada do Cloud Build (novatlantis-cicd-deployer)
# ==============================================================================

set -euo pipefail

export PATH="/google/data/ro/teams/cloud-sdk:/usr/lib/google-cloud-sdk/bin:${HOME}/.local/Homebrew/bin:${PATH}"

GCP_ACCOUNT="${GCP_ACCOUNT:-pedrocalixto@gcp.altostrat.com}"
PROJECT_ID="${GCP_PROJECT_ID:-novatlantis}"
REGION="${GCP_REGION:-us-central1}"
TF_STATE_BUCKET="${TF_STATE_BUCKET_NAME:-${PROJECT_ID}-tfstate}"
CICD_SA_NAME="novatlantis-cicd-deployer"
CICD_SA_EMAIL="${CICD_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

log_info() {
  printf "\033[1;34m[NOVATLANTIS-BOOTSTRAP]\033[0m %s\n" "$1"
}

log_ok() {
  printf "\033[1;32m[OK]\033[0m %s\n" "$1"
}

log_info "1. Configurando conta (${GCP_ACCOUNT}) e projeto Google Cloud: ${PROJECT_ID} (${REGION})..."
gcloud config set account "${GCP_ACCOUNT}" --quiet
gcloud config set project "${PROJECT_ID}" --quiet

log_info "2. Habilitando APIs essenciais para Terraform GitOps e Cloud Build..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  alloydb.googleapis.com \
  bigquery.googleapis.com \
  pubsub.googleapis.com \
  aiplatform.googleapis.com \
  --project="${PROJECT_ID}"

log_info "3. Provisionando Bucket de Estado Remoto do Terraform (gs://${TF_STATE_BUCKET})..."
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --quiet
fi

gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
  --versioning \
  --project="${PROJECT_ID}" \
  --quiet
log_ok "Bucket gs://${TF_STATE_BUCKET} ativo com Object Versioning e State Locking nativo."

log_info "4. Provisionando Service Account de Automação CI/CD (${CICD_SA_EMAIL})..."
if ! gcloud iam service-accounts describe "${CICD_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${CICD_SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Novatlantis Cloud Build CI/CD & Terraform GitOps Deployer"
fi

CICD_ROLES=(
  "roles/run.admin"
  "roles/artifactregistry.writer"
  "roles/artifactregistry.repoAdmin"
  "roles/compute.networkAdmin"
  "roles/compute.securityAdmin"
  "roles/compute.loadBalancerAdmin"
  "roles/alloydb.admin"
  "roles/secretmanager.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
  "roles/resourcemanager.projectIamAdmin"
  "roles/storage.admin"
  "roles/bigquery.admin"
  "roles/pubsub.admin"
  "roles/aiplatform.admin"
  "roles/cloudbuild.builds.builder"
  "roles/logging.logWriter"
)

for ROLE in "${CICD_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CICD_SA_EMAIL}" \
    --role="${ROLE}" \
    --quiet >/dev/null
done

log_ok "Service Account ${CICD_SA_EMAIL} configurada com permissões de CI/CD e GitOps."
echo ""
echo "=============================================================================="
echo " BOOTSTRAP CONCLUÍDO COM SUCESSO!"
echo " Próximo passo:"
echo "   1. Conecte a organização GitHub 'LATAM-PS-CE-Team' no Cloud Build"
echo "   2. Execute 'terraform init && terraform apply' em environments/dev e prod"
echo "=============================================================================="
