# `LATAM-PS-CE-Team/novatlantis-iac` — Infraestrutura como Código (Terraform & GitOps)

Repositório oficial de **Infraestrutura como Código (*IaC*)** da **República Digital de Novatlantis** (`novatlantis.gov.cloud`), mantido pelo time [`LATAM-PS-CE-Team`](https://github.com/LATAM-PS-CE-Team).

Substitui os antigos scripts imperativos de shell por módulos **Terraform** declarativos, idempotentes e auditados via **GitOps no Google Cloud Build**, utilizando estado remoto centralizado e travado (*State Locking*) no bucket `gs://novatlantis-tfstate`.

## 1. Regra de Branches e Ambientes (`dev` e `prod`)

Existem apenas **duas branches permanentes** no repositório:

| Branch Alvo do PR | Ambiente Terraform | Estado Remoto (GCS) | Regra de Aprovação e Merge |
| :--- | :--- | :--- | :--- |
| **`dev`** | **`environments/dev`** (`dev`) | `gs://novatlantis-tfstate/iac/dev` | **Sem entraves (0 aprovações exigidas):** Qualquer colaborador abre PR para `dev`, valida o `terraform plan` e faz o merge por conta própria, disparando `terraform apply` em `dev`. |
| **`main`** | **`environments/prod`** (`prod`) | `gs://novatlantis-tfstate/iac/prod` | **Aprovação obrigatória de `@pedrocalixto`:** Qualquer colaborador pode abrir PR promovendo `dev` $\rightarrow$ `main`, mas o merge exige aprovação explícita de **`@pedrocalixto`** antes de disparar `terraform apply` em `prod`. |

## 2. Estrutura de Diretórios

```text
novatlantis-iac/
├── bootstrap/
│   └── bootstrap-cicd-foundation.sh    # Inicialização única do bucket tfstate e Service Account do Cloud Build
├── modules/
│   ├── networking/                     # VPC novatlantis-vpc, Subnet us-central1 e Private Services Access (PSA)
│   ├── database-alloydb/               # Cluster AlloyDB for PostgreSQL 15 e instância primária
│   ├── security-iam-secrets/           # Artifact Registry, Secret Manager e Workload Identity SA
│   ├── cloud-run-services/             # 8 serviços Cloud Run (novatlantis-dev-* e novatlantis-prod-*)
│   ├── edge-lb-armor/                  # Cloud Armor WAF (OWASP Top 10), SSL Gerenciado e Serverless NEGs
│   └── cicd-triggers/                  # Gatilhos Cloud Build dos 3 repositórios (App, IaC e Data Platform)
├── environments/
│   ├── dev/                            # Ambiente DEV  (branch dev)  -> gs://novatlantis-tfstate/iac/dev
│   └── prod/                           # Ambiente PROD (branch main) -> gs://novatlantis-tfstate/iac/prod
└── cloudbuild/
    ├── cloudbuild-tf-plan.yaml         # Roda em todo Pull Request (fmt + validate + plan dev/prod)
    └── cloudbuild-tf-apply.yaml        # Roda no merge em dev (aplica dev) ou main (aplica prod)
```
