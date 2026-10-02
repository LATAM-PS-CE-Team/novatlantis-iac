#!/usr/bin/env bash
# ==============================================================================
# REPÚBLICA DIGITAL DE NOVATLANTIS — BOOTSTRAP DAY-0 (novatlantis-dev & novatlantis-prd)
# Organização GitHub: https://github.com/LATAM-PS-CE-Team
# Organização GCP Argolis: pedrocalixto.altostrat.com (248932941139)
# Projetos GCP:
#   - novatlantis-dev (Associado à branch 'dev' -> Ambiente DEV)
#   - novatlantis-prd (Associado à branch 'main' -> Ambiente PROD)
#
# O que este script provisiona em AMBOS os projetos ('novatlantis-dev' e 'novatlantis-prd'):
#   1. Habilita as APIs essenciais (IAM, STS, IAM Credentials, Cloud Build, Run, AlloyDB...)
#   2. Cria os Buckets GCS de Estado Remoto do Terraform:
#      - gs://novatlantis-dev-tfstate (no projeto novatlantis-dev)
#      - gs://novatlantis-prd-tfstate (no projeto novatlantis-prd)
#   3. Cria a Service Account dedicada em cada projeto:
#      - novatlantis-cicd-deployer@novatlantis-dev.iam.gserviceaccount.com
#      - novatlantis-cicd-deployer@novatlantis-prd.iam.gserviceaccount.com
#   4. Configura o Workload Identity Federation (WIF) em ambos os projetos:
#      - Pool: github-latam-ps-ce-pool
#      - Provider OIDC: github-oidc-provider (issuer: https://token.actions.githubusercontent.com)
#      - Vincula os 3 repositórios da org 'LATAM-PS-CE-Team' à SA novatlantis-cicd-deployer
# ==============================================================================

set -euo pipefail

export PATH="/google/data/ro/teams/cloud-sdk:/usr/lib/google-cloud-sdk/bin:${HOME}/.local/Homebrew/bin:${PATH}"

GCP_ACCOUNT="${GCP_ACCOUNT:-admin@pedrocalixto.altostrat.com}"
REGION="${GCP_REGION:-us-central1}"
GITHUB_ORG="${GITHUB_ORG:-LATAM-PS-CE-Team}"

PROJECTS=("novatlantis-dev" "novatlantis-prd")
CICD_SA_NAME="novatlantis-cicd-deployer"
WIF_POOL_ID="github-latam-ps-ce-pool"
WIF_PROVIDER_ID="github-oidc-provider"

log_info() {
  printf "\033[1;34m[NOVATLANTIS-BOOTSTRAP]\033[0m %s\n" "$1"
}

log_ok() {
  printf "\033[1;32m[OK]\033[0m %s\n" "$1"
}

gcloud config set account "${GCP_ACCOUNT}" --quiet

for PROJECT_ID in "${PROJECTS[@]}"; do
  TF_STATE_BUCKET="${PROJECT_ID}-tfstate"
  CICD_SA_EMAIL="${CICD_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

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
  log_ok "Bucket gs://${TF_STATE_BUCKET} ativo com Object Versioning e State Locking."

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
      --quiet >/dev/null
  done
  log_ok "Service Account ${CICD_SA_EMAIL} configurada com todas as permissões de provisionamento."

  log_info "4. Configurando Workload Identity Federation (WIF) em ${PROJECT_ID} para a org [${GITHUB_ORG}]..."
  if ! gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" --location="global" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --display-name="LATAM-PS-CE-Team GitHub Pool" \
      --description="Workload Identity Pool para os repositorios Novatlantis da org ${GITHUB_ORG}" \
      --quiet
  fi

  if ! gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location="global" \
    --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WIF_POOL_ID}" \
      --display-name="GitHub OIDC Provider" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
      --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
      --quiet
  fi

  gcloud iam service-accounts add-iam-policy-binding "${CICD_SA_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository_owner/${GITHUB_ORG}" \
    --quiet >/dev/null

  WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
  log_ok "Projeto ${PROJECT_ID} pronto! WIF Provider: ${WIF_PROVIDER_FULL}"
done
