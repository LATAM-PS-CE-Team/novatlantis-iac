# novatlantis-iac

Infraestrutura como Código (Terraform) da plataforma **Novatlantis** no Google Cloud (projeto `novatlantis` / `1054221034062`).

## Ambientes

Os ambientes `dev` e `prod` coexistem no mesmo projeto Google Cloud com estado remoto, VPCs e serviços isolados por prefixo:

| Branch | Diretório | Prefixo | State (`gs://novatlantis-tfstate`) | VPC | IP Global | Domínio |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `dev` | `environments/dev` | `novatlantis-dev-*` | `iac/dev` | `10.10.0.0/20` | `136.81.6.22` | `*.dev.gov.novatlantis.cloud` |
| `main` | `environments/prod` | `novatlantis-prod-*` | `iac/prod` | `10.20.0.0/20` | `136.81.9.16` | `*.gov.novatlantis.cloud` |

## Estrutura

```text
novatlantis-iac/
├── .github/workflows/cicd.yml       # Dispara Cloud Build via Workload Identity Federation
├── bootstrap/                       # Script de configuração inicial de state, SAs e WIF
├── cloudbuild/
│   ├── cloudbuild-tf-plan.yaml      # Validação e terraform plan em Pull Requests
│   └── cloudbuild-tf-apply.yaml     # terraform apply em merges nas branches dev e main
├── environments/
│   ├── dev/                         # Configuração do ambiente dev
│   └── prod/                        # Configuração do ambiente prod
└── modules/
    ├── networking/                  # VPC, sub-redes e Private Service Access
    ├── database-alloydb/            # Cluster e instância primária AlloyDB
    ├── security-iam-secrets/        # Artifact Registry, Secret Manager e Service Accounts
    ├── cloud-run-services/          # Serviços Cloud Run
    └── edge-lb-armor/               # Application Load Balancer global, certificados SSL e Cloud Armor
```
