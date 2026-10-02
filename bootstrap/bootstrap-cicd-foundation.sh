#!/usr/bin/env bash
# ==============================================================================
# REPÚBLICA DIGITAL DE NOVATLANTIS — BOOTSTRAP DAY-0 (SA + WIF + TFSTATE BUCKET)
# Organização GitHub: https://github.com/LATAM-PS-CE-Team
# Projeto GCP: novatlantis (1054221034062)
# Conta Operadora: pedrocalixto@gcp.altostrat.com
#
# O que este script provisiona no projeto GCP 'novatlantis':
#   1. Habilita as APIs essenciais (IAM, STS, IAM Credentials, Cloud Build, Run, AlloyDB...)
#   2. Cria o Bucket GCS de Estado Remoto do Terraform (gs://novatlantis-tfstate)
#   3. Cria a Service Account dedicada (novatlantis-cicd-deployer@novatlantis.iam.gserviceaccount.com)
#      e atribui todas as roles de provisionamento no projeto
#   4. Configura o Workload Identity Federation (WIF):
#      - Pool: github-latam-ps-ce-pool
#      - Provider OIDC: github-oidc-provider (issuer: https://token.actions.githubusercontent.com)
#      - Restrição de segurança (Attribute Condition): aceita APENAS repositórios da
#        organização GitHub 'LATAM-PS-CE-Team'
#      - Vincula (roles/iam.workloadIdentityUser) os 3 repositórios (novatlantis-app,
#        novatlantis-iac e novatlantis-data-platform) à SA novatlantis-cicd-deployer
# ==============================================================================

set -euo pipefail

export PATH="/google/data/ro/teams/cloud-sdk:/usr/lib/google-cloud-sdk/bin:${HOME}/.local/Homebrew/bin:${PATH}"

GCP_ACCOUNT="${GCP_ACCOUNT:-pedrocalixto@gcp.altostrat.com}"
PROJECT_ID="${GCP_PROJECT_ID:-novatlantis}"
REGION="${GCP_REGION:-us-central1}"
GITHUB_ORG="${GITHUB_ORG:-LATAM-PS-CE-Team}"

TF_STATE_BUCKET="${TF_STATE_BUCKET_NAME:-${PROJECT_ID}-tfstate}"
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

log_info "1. Configurando conta (${GCP_ACCOUNT}) e projeto Google Cloud: ${PROJECT_ID} (${REGION})..."
gcloud config set account "${GCP_ACCOUNT}" --quiet
gcloud config set project "${PROJECT_ID}" --quiet

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
log_ok "Projeto ${PROJECT_ID} identificado (Project Number: ${PROJECT_NUMBER})."

log_info "2. Habilitando APIs essenciais para WIF, Terraform GitOps e Cloud Build..."
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

log_info "4. Provisionando Service Account dedicada (${CICD_SA_EMAIL})..."
if ! gcloud iam service-accounts describe "${CICD_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${CICD_SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Novatlantis CI/CD & Terraform GitOps Deployer (WIF + Cloud Build)"
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

log_info "5. Configurando Workload Identity Federation (WIF) para a org GitHub [${GITHUB_ORG}]..."
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
    --display-name="GitHub OIDC Provider (${GITHUB_ORG})" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
    --quiet
fi

# Vincula toda a organização LATAM-PS-CE-Team (os 3 repositórios) para autenticar na SA via WIF
gcloud iam service-accounts add-iam-policy-binding "${CICD_SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository_owner/${GITHUB_ORG}" \
  --quiet >/dev/null

WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
log_ok "WIF configurado com sucesso!"
echo ""
echo "=============================================================================="
echo " RESUMO DO BOOTSTRAP NO PROJETO GCP [${PROJECT_ID}]:"
echo "   - Service Account: ${CICD_SA_EMAIL}"
echo "   - WIF Provider:    ${WIF_PROVIDER_FULL}"
echo "   - TF State Bucket: gs://${TF_STATE_BUCKET}"
echo "=============================================================================="
