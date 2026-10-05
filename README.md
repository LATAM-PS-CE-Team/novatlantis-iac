# `LATAM-PS-CE-Team/novatlantis-iac` — Infraestrutura como Código (Terraform & GitOps Keyless WIF)

Repositório oficial de **Infraestrutura como Código (*IaC*)** da **República Digital de Novatlantis** (`gov.novatlantis.cloud` e `dev.gov.novatlantis.cloud`), mantido pelo time [`LATAM-PS-CE-Team`](https://github.com/LATAM-PS-CE-Team).

Provisiona e gerencia declarativamente via **Terraform** e **GitHub Actions (Keyless WIF + Cloud Build)** os ambientes **`dev`** e **`prod`** dentro do projeto GCP unificado **`novatlantis` (`1054221034062`)**, com isolamento lógico completo por prefixo (`novatlantis-dev-*` vs `novatlantis-prod-*`), VPCs separadas e chaves de estado distintas no bucket `gs://novatlantis-tfstate`:

- **Ambiente `dev` (`environments/dev`)**: Projeto GCP **`novatlantis`**, Estado Remoto `gs://novatlantis-tfstate/iac/dev`, VPC `10.10.0.0/20`, IP Global `136.81.6.22` (`*.dev.gov.novatlantis.cloud`).
- **Ambiente `prod` (`environments/prod`)**: Projeto GCP **`novatlantis`**, Estado Remoto `gs://novatlantis-tfstate/iac/prod`, VPC `10.20.0.0/20`, IP Global `136.81.9.16` (`*.gov.novatlantis.cloud`).

## 1. Regra de Branches, Isolamento no Projeto `novatlantis` e Ambientes (`dev` e `prod`)

Existem apenas **duas branches permanentes** no repositório:

| Branch Alvo | Projeto GCP | Ambiente Terraform | Estado Remoto (GCS) | Domínio Oficial & IP Anycast | Regra de Aprovação e Merge |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`dev`** | **`novatlantis`** (`1054221034062`) | **`environments/dev`** (`novatlantis-dev-*`) | `gs://novatlantis-tfstate/iac/dev` | `dev.gov.novatlantis.cloud` (`136.81.6.22`) | **Sem entraves (0 aprovações exigidas):** Qualquer colaborador abre PR para `dev`, valida o `terraform plan` e faz o merge por conta própria, disparando `terraform apply` em `environments/dev`. |
| **`main`** | **`novatlantis`** (`1054221034062`) | **`environments/prod`** (`novatlantis-prod-*`) | `gs://novatlantis-tfstate/iac/prod` | `gov.novatlantis.cloud` (`136.81.9.16`) | **Aprovação obrigatória de `@pedrocalixto`:** Qualquer colaborador pode abrir PR promovendo `dev` $\rightarrow$ `main`, mas o merge exige aprovação explícita de **`@pedrocalixto`** antes de disparar `terraform apply` em `environments/prod`. |

## 2. Estrutura de Diretórios

```text
novatlantis-iac/
├── .github/workflows/
│   └── cicd.yml                        # Pipeline GitOps Keyless WIF (OIDC) -> Google Cloud Build
├── bootstrap/
│   └── bootstrap-cicd-foundation.sh    # Inicialização Day-0 do bucket gs://novatlantis-tfstate, SAs e Pool WIF no projeto novatlantis
├── modules/
│   ├── networking/                     # VPCs isoladas (novatlantis-dev-vpc 10.10.0.0/20 e novatlantis-prod-vpc 10.20.0.0/20) e PSA
│   ├── database-alloydb/               # Cluster AlloyDB for PostgreSQL 15 e instância primária
│   ├── security-iam-secrets/           # Artifact Registry, Secret Manager e Workload Identity SA
│   ├── cloud-run-services/             # 9 microsserviços Cloud Run por ambiente (18 serviços no total)
│   └── edge-lb-armor/                  # Global Load Balancers, Cloud Armor WAF (OWASP Top 10), SSL Gerenciado (14 SANs por ambiente) e Serverless NEGs
├── environments/
│   ├── dev/                            # Ambiente DEV  (branch dev  -> prefixo iac/dev  -> novatlantis-dev-*)
│   └── prod/                           # Ambiente PROD (branch main -> prefixo iac/prod -> novatlantis-prod-*)
└── cloudbuild/
    ├── cloudbuild-tf-plan.yaml         # Roda em todo Pull Request (fmt + validate + plan do ambiente alvo)
    └── cloudbuild-tf-apply.yaml        # Roda no merge em dev (aplica environments/dev) ou main (aplica environments/prod)
```
