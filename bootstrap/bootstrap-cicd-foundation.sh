#!/usr/bin/env bash
# ==============================================================================
# REPÚBLICA DIGITAL DE NOVATLANTIS — BOOTSTRAP DAY-0 (Projeto Unificado: novatlantis)
# Organização GitHub: https://github.com/LATAM-PS-CE-Team
# Projeto GCP Oficial: novatlantis (Project Number: 1054221034062)
#
# O que este script provisiona no projeto 'novatlantis':
#   1. Habilita as APIs essenciais (IAM, STS, IAM Credentials, Cloud Build, Run, AlloyDB...)
#   2. Cria o Bucket GCS de Estado Remoto do Terraform:
#      - gs://novatlantis-tfstate (com prefixos isolados iac/dev e iac/prod)
#   3. Cria a Service Account dedicada de CI/CD:
#      - novatlantis-cicd-deployer@novatlantis.iam.gserviceaccount.com
#   4. Configura o Workload Identity Federation (WIF) no projeto novatlantis:
#      - Pool: github-latam-ps-ce-pool
#      - Provider OIDC: github-oidc-provider (issuer: https://token.actions.githubusercontent.com)
#      - Vincula os 3 repositórios da org 'LATAM-PS-CE-Team' à SA novatlantis-cicd-deployer
# ==============================================================================

set -euo pipefail

export PATH="/google/data/ro/teams/cloud-sdk:/usr/lib/google-cloud-sdk/bin:${HOME}/.local/Homebrew/bin:${PATH}"

GCP_ACCOUNT="${GCP_ACCOUNT:-pedrocalixto@gcp.altostrat.com}"
REGION="${GCP_REGION:-us-central1}"
GITHUB_ORG="${GITHUB_ORG:-LATAM-PS-CE-Team}"

PROJECT_ID="novatlantis"
TF_STATE_BUCKET="novatlantis-tfstate"
CICD_SA_NAME="novatlantis-cicd-deployer"
CICD_SA_EMAIL="${CICD_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL_ID="github-latam-ps-ce-pool"
WIF_PROVIDER_ID="github-oidc-provider"

log_info() {
  printf "\033[1;34m[NOVATLANTIS-BOOTSTRAP]\033[0m %s\n" "$1"
}

log_ok() {
  printf "\033[1;32m[OK]\033[0m %s\n" "$1"
}

gcloud config set account "${GCP_ACCOUNT}" --quiet

echo ""
echo "=============================================================================="
log_info "INICIANDO BOOTSTRAP NO PROJETO GCP: ${PROJECT_ID} (${REGION})"
echo "=============================================================================="

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
log_ok "Projeto ${PROJECT_ID} identificado (Project Number: ${PROJECT_NUMBER})."

log_info "1. Habilitando APIs essenciais em ${PROJECT_ID}..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
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

log_info "2. Provisionando Bucket de Estado Remoto do Terraform (gs://${TF_STATE_BUCKET})..."
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
log_ok "Bucket gs://${TF_STATE_BUCKET} ativo com Object Versioning e State Locking (prefixos iac/dev e iac/prod)."

log_info "3. Provisionando Service Account dedicada (${CICD_SA_EMAIL})..."
if ! gcloud iam service-accounts describe "${CICD_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${CICD_SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Novatlantis CI/CD & Terraform GitOps Deployer (${PROJECT_ID})"
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
    --condition=None \
    --quiet >/dev/null
done

CB_DEFAULT_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for BUILDER_SA in "${CB_DEFAULT_SA}" "${COMPUTE_DEFAULT_SA}"; do
  for ROLE in "${CICD_ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${BUILDER_SA}" \
      --role="${ROLE}" \
      --condition=None \
      --quiet >/dev/null 2>&1 || true
  done
done
log_ok "Permissões IAM atribuídas a ${CICD_SA_EMAIL} e Cloud Build SA."

log_info "4. Configurando Workload Identity Federation (WIF) para ${GITHUB_ORG} em ${PROJECT_ID}..."
if ! gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" --location="global" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="GitHub Actions Pool (${GITHUB_ORG})"
elif [ "$(gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" --location="global" --project="${PROJECT_ID}" --format="value(state)")" = "DELETED" ]; then
  gcloud iam workload-identity-pools undelete "${WIF_POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location="global"
fi

if ! gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --location="global" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --display-name="GitHub Actions OIDC Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'"
elif [ "$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" --workload-identity-pool="${WIF_POOL_ID}" --location="global" --project="${PROJECT_ID}" --format="value(state)")" = "DELETED" ]; then
  gcloud iam workload-identity-pools providers undelete "${WIF_PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WIF_POOL_ID}"
fi

gcloud iam service-accounts add-iam-policy-binding "${CICD_SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository_owner/${GITHUB_ORG}" \
  --quiet >/dev/null

WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
log_ok "WIF Provider ativo em ${PROJECT_ID}: ${WIF_PROVIDER_FULL}"
