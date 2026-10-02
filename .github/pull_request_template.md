## Resumo da Alteração de Infraestrutura (`LATAM-PS-CE-Team/novatlantis-iac`)

Descreva quais recursos Terraform (VPC, AlloyDB, Cloud Run, Cloud Armor, Triggers) estão sendo criados ou alterados:
- 

## Branch e Ambiente Alvo deste Pull Request

- [ ] **Branch `dev` (Ambiente `dev`)** — Merge livre após `terraform plan` verde no Cloud Build (0 aprovações exigidas).
- [ ] **Branch `main` (Ambiente `prod`)** — Promoção para Produção (exige aprovação obrigatória de `@pedrocalixto`).

## Checklist GitOps

- [ ] Executei `terraform fmt -recursive` antes do commit.
- [ ] Verifiquei a saída do `terraform plan` no log do Google Cloud Build para garantir que nenhum recurso crítico será destruído indevidamente.
