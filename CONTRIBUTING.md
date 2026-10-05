# Guia de Contribuição — `novatlantis-iac`

## Fluxo de Trabalho

1. Crie uma branch a partir de `dev` e faça suas alterações nos módulos em `modules/` ou `environments/`.
2. Abra um Pull Request para `dev`. O workflow executará `terraform fmt -check`, `terraform validate` e `terraform plan` via Cloud Build.
3. Após o merge em `dev`, o pipeline aplica automaticamente as mudanças em `environments/dev`.
4. Para promover para produção, abra um Pull Request de `dev` para `main` (requer aprovação de `@pedrocalixto`).
