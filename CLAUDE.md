# wazuh-aws-siem

Lab de SIEM usando **Wazuh** hospedado na AWS, em formato **all-in-one** (manager + indexer + dashboard na mesma instância EC2). Infraestrutura provisionada via **Terraform**. Projeto de estudo/lab, não produção.

## Contexto do projeto

- **Objetivo**: laboratório de SIEM com Wazuh para estudo de detecção, correlação de eventos e integração com ferramentas de segurança da AWS (CloudTrail, GuardDuty, Security Hub, etc).
- **Topologia**: EC2 única (all-in-one), sem cluster, sem HA. Simplicidade > robustez aqui.
- **Região**: `sa-east-1` (São Paulo). Não provisionar recursos em outras regiões sem necessidade explícita — evita custo de tráfego entre regiões e confusão de billing.
- **IaC**: Terraform é a fonte de verdade. Mudanças de infra devem passar pelo `.tf`, não devem ser feitas clicando no console (exceto exploração pontual, e mesmo assim replicar depois no código).
- **Budget mensal: US$ 8**. É um valor **muito apertado** para uma EC2 rodando 24/7 (mesmo um `t3.micro` em `sa-east-1` já consome boa parte disso só de compute). Ver seção de avisos abaixo.

## Convenções

- Estrutura Terraform sugerida: `envs/` ou raiz com `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`. Se crescer, separar em módulos (`modules/ec2-wazuh`, `modules/networking`, `modules/budget`).
- Backend de state: usar remoto (S3 + DynamoDB lock) assim que possível, mesmo em lab — evita perder state local. Nome do bucket deve ser único e identificável (`<algo>-wazuh-siem-tfstate`).
- Tags obrigatórias em todo recurso: `Project=wazuh-aws-siem`, `Environment=lab`, `ManagedBy=terraform`, `Owner=<seu nome/email>`. Facilita filtrar custo por tag no Cost Explorer.
- Nomenclatura de recursos: prefixo `wazuh-siem-` (ex: `wazuh-siem-ec2`, `wazuh-siem-sg`, `wazuh-siem-eip`).
- Nunca commitar: `.tfstate`, `.tfvars` com segredos, chaves `.pem`, credenciais AWS. Adicionar `.gitignore` cobrindo isso desde o primeiro commit.
- Variáveis sensíveis (senhas do Wazuh, tokens) via `TF_VAR_*` de ambiente ou AWS Secrets Manager/SSM Parameter Store — nunca hardcoded no `.tf`.

## Avisos de segurança

- **Budget de $8/mês é incompatível com EC2 rodando 24/7** na prática (t3.micro on-demand em sa-east-1 já ronda ~$7-9/mês só de compute, fora EBS, EIP ocioso, transferência de dados). Recomendo fortemente automatizar **start/stop programado** da instância (EventBridge Scheduler + Lambda, ou simplesmente parar manual fora do horário de estudo) para caber no orçamento.
- **AWS Budgets com alertas** deve ser criado via Terraform (`aws_budgets_budget`) com thresholds em 50%, 80% e 100% do valor de $8, notificando por e-mail/SNS. Não depender de configurar isso manualmente no console.
- **Nunca expor o Wazuh Dashboard (porta 443) direto para `0.0.0.0/0`**. Restringir Security Group ao seu IP público (`/32`) ou usar uma VPN/bastion. O mesmo vale para a porta 1514/1515 (agentes) e 55000 (API).
- **Evitar SSH aberto (porta 22) para a internet**. Preferir **AWS Systems Manager Session Manager** (não precisa de porta aberta, nem de par de chaves exposto, e ainda evita custo de EIP se não precisar de IP fixo separado do SSM).
- **Elastic IP não associado gera custo** — se alocar EIP, garantir que está sempre associado à instância, ou liberar quando a instância for parada por longos períodos.
- Root/admin da conta AWS deve ter MFA ativado. Usar um usuário/role IAM dedicado para o Terraform (least privilege), nunca a conta root.
- Wazuh gera senhas padrão na instalação (indexer, dashboard, API) — trocar todas antes de considerar o lab "pronto", mesmo sendo ambiente de estudo.
- Snapshots/AMIs e volumes EBS podem conter dados sensíveis de teste — não deixar públicos.
- Ativar **encryption at rest** no EBS da instância (`encrypted = true` no `aws_ebs_volume`/`root_block_device`) — não tem custo adicional relevante e é boa prática desde o início.

## Sugestões

- Considerar `t3.micro` ou `t3.small` com **burstable credits** e ver se ainda está no Free Tier (primeiros 12 meses de conta nova) — isso muda completamente a viabilidade do budget de $8.
- Usar **Spot Instance** para o lab se puder tolerar interrupções — reduz custo de compute significativamente, mas não é recomendado se for deixar o Wazuh rodando por longos períodos sem supervisão.
- Configurar **CloudWatch Billing Alarm** além do AWS Budgets, como camada extra de aviso.
- Documentar no README (não neste arquivo) os passos de instalação do Wazuh (script oficial `wazuh-install.sh` all-in-one) para reprodutibilidade.
- Testar o Terraform sempre com `terraform plan` antes de `apply`, e usar `terraform destroy` no fim de cada sessão de estudo se o objetivo for só reduzir custo (reprovisionar depois é rápido já que é IaC).
- Integrar fontes de log AWS gradualmente: primeiro CloudTrail → S3 → Wazuh (via módulo AWS do Wazuh), depois GuardDuty findings, depois Security Hub. Não tentar tudo de uma vez.

## Comandos do dia a dia

**Terraform**
```
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform destroy          # usar com cautela, sempre revisar o que será destruído
terraform state list
```

**AWS CLI (custo/billing)**
```
aws budgets describe-budgets --account-id <account-id>
aws ce get-cost-and-usage --time-period Start=2026-07-01,End=2026-07-31 --granularity MONTHLY --metrics "UnblendedCost"
```

**AWS Systems Manager (acesso à instância sem SSH exposto)**
```
aws ssm start-session --target <instance-id> --region sa-east-1
```

**Wazuh (dentro da instância)**
```
sudo /var/ossec/bin/wazuh-control status
sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard
sudo tail -f /var/ossec/logs/ossec.log
sudo /var/ossec/bin/manage_agents
sudo filebeat test output
```

## Ferramentas e skills necessárias

- **Terraform** (CLI) + provider `hashicorp/aws`.
- **AWS CLI v2** configurado com profile dedicado (não usar credenciais root).
- **tfsec** ou **checkov** — scan de segurança do código Terraform antes de aplicar (Security Groups abertos, EBS sem encryption, etc).
- **jq** — para parsear saída de `aws cli` e logs JSON do Wazuh.
- **Session Manager plugin** (AWS CLI) para `aws ssm start-session`.
- Skill `security-review` deste ambiente — rodar antes de aplicar mudanças de infra que envolvam Security Groups, IAM ou exposição de rede.
- Git para versionar o Terraform (repo ainda não inicializado nesta pasta — considerar `git init` cedo).
