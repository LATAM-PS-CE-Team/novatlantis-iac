# Guia de Contribuição — `LATAM-PS-CE-Team/novatlantis-iac`

## Passo a Passo para Alterar a Infraestrutura

1. **Clonar o repositório e mudar para a branch `dev`:**
   ```bash
   git clone https://github.com/LATAM-PS-CE-Team/novatlantis-iac.git
   cd novatlantis-iac
   git checkout dev
   git pull origin dev
   ```
2. **Criar uma branch local a partir da `dev`:**
   ```bash
   git checkout -b feat/nova-regra-cloud-armor
   ```
3. **Editar os módulos Terraform e formatar o código:**
   ```bash
   terraform fmt -recursive
   git add .
   git commit -m "feat(waf): adiciona regra de rate limiting para API 311"
   git push -u origin feat/nova-regra-cloud-armor
   ```
4. **Aplicar no Ambiente `dev` (Sem entraves — Branch `dev`):**
   - Abra um Pull Request da sua branch contra a branch **`dev`**.
   - O Cloud Build executará `cloudbuild-tf-plan.yaml`.
   - Assim que o check ficar verde, **você mesmo pode fazer o Merge na `dev`** (sem precisar esperar aprovação). O Cloud Build aplicará automaticamente no ambiente **`dev`** (`environments/dev`).
5. **Promover para o Ambiente `prod` (Com aprovação de `@pedrocalixto` — Branch `main`):**
   - Abra um Pull Request da branch **`dev`** para a branch **`main`**.
   - O GitHub exigirá a revisão de **`@pedrocalixto`**. Após a aprovação e merge na branch `main`, o Cloud Build aplicará as mudanças em **`prod`** (`environments/prod`).
