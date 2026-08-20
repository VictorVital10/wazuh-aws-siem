# wazuh-aws-siem

Lab de SIEM usando **Wazuh** hospedado na AWS, em formato **all-in-one** (manager + indexer + dashboard na mesma instância EC2). Projeto de estudo/portfólio — parte da iniciativa **VV Cloud Security**.

## Contexto do projeto

- **Objetivo**: laboratório de SIEM com Wazuh para estudo de detecção, correlação de eventos e integração futura com ferramentas de segurança da AWS (CloudTrail, GuardDuty).
- **Topologia**: EC2 única (all-in-one), sem cluster, sem HA.
- **Conta AWS**: standalone free tier, separada das organizations `vav`/`jbdsa` — nunca deve ser unida a uma Organization (perderia o Free Plan).
- **Provisionamento atual**: híbrido. O Wazuh Server (EC2 all-in-one, SG, EIP) continua manual, via console AWS + terminal (SSH/PowerShell). O agent Linux (segunda instância EC2 + SG dedicado) já é provisionado via **Terraform** — primeiro recurso do projeto migrado para IaC.
- **Abordagem de aprendizado**: hands-on primeiro (console/CLI), automação depois. Prioridade em entender o "porquê" de cada passo, não só copiar comandos. Terraform foi introduzido só depois que o fluxo manual do Wazuh Server já estava validado e estável — segue a mesma lógica: entender antes de automatizar.

## Estado atual da infraestrutura

| Componente | Valor |
|---|---|
| Instância EC2 | `Wazuh-Server`, Ubuntu, `m7i-flex.large` (2 vCPU / 8GB RAM) |
| Volume EBS (root) | 50GB (expandido de 8GB original — ver Troubleshooting) |
| Security Group | `wazuh-sg` — portas 443, 22, 1514, 1515, todas restritas a IPs específicos (nunca `0.0.0.0/0`) |
| Elastic IP | Alocado e associado à instância |
| Domínio | DuckDNS (gratuito, apontando ao Elastic IP) — nome real omitido por segurança |
| Certificado TLS | Let's Encrypt via certbot, válido até 12/11/2026, renovação automática |
| Wazuh | v4.14.7, instalação all-in-one |
| Agents registrados | 1 (Windows pessoal, status Active) |
| Instância EC2 (Linux Agent) | `linux_agent`, `t3.micro` — provisionada via Terraform |
| Security Group (Linux Agent) | `agents_sg` — porta 22 restrita a IP específico, egress liberado — via Terraform |

## Convenções adotadas

- **Chaves SSH**: `ed25519`, um par por máquina (nunca reutilizar/copiar chave privada entre computadores). Organizadas em `%USERPROFILE%\.ssh\Wazuh-Server\`. Alias configurado em `~/.ssh/config` (host `Wazuh-Server`).
- **Acesso SSH**: restrito por IP público (`/32`) no Security Group. EC2 Instance Connect (browser) usado apenas no bootstrap inicial, antes de haver chave configurada — removido do SG depois.
- **Manager address para agents**: usar o domínio DuckDNS, nunca o IP direto — mantém os agents funcionando mesmo se o Elastic IP mudar no futuro.
- **Credenciais**: armazenadas no KeePass (chaves SSH, senhas do dashboard). Nunca deixadas só no output do terminal.
- **Documentação**: OneNote (conceitos/hardening), Word (processos passo a passo), Markdown (registro técnico do projeto, como este e o `wazuh-deployment.md`).

## Avisos de segurança (aplicados até aqui)

- Wazuh Dashboard (porta 443) **nunca exposto para `0.0.0.0/0`** — restrito ao IP público de cada máquina usada no projeto.
- Portas 1514 (streaming de eventos) e 1515 (enrollment de agents) também restritas por IP, não abertas ao mundo.
- SSH (porta 22) restrito por IP; chave pública/privada em vez de senha.
- Elastic IP mantido sempre associado à instância rodando, para evitar cobrança por IP ocioso.
- Senha padrão do dashboard (`admin`) gerada na instalação — recuperável via `wazuh-install-files.tar` caso não tenha sido salva na hora.

## Terraform (agent Linux)

- **Localização**: `terraform/` na raiz do projeto.
- **Arquivos**: `providers.tf` (provider `hashicorp/aws` v6.60.0, autenticação via AWS CLI profile `Terraform`, região `us-east-2`), `variables.tf`, `main.tf`, `terraform.tfvars` (gitignored).
- **Recursos gerenciados**:
  - `aws_instance.linux_agent` — EC2 `t3.micro`, AMI Ubuntu (`var.instance_ami`).
  - `aws_security_group.agents_sg` — SG dedicado ao agent, separado do `wazuh-sg` do Wazuh Server.
  - `aws_vpc_security_group_ingress_rule.ssh_personal` — libera 22/tcp só para `var.personal_ip`.
  - `aws_vpc_security_group_egress_rule.allow_all_outbound` — egress liberado (`0.0.0.0/0`).
  - `aws_key_pair.wazuh_agent_key` — chave pública `ed25519` dedicada (path local em `terraform.tfvars`, via `var.public_key_path`).
- **Regra de ingress para IP profissional** (`ssh_professional`) está comentada em `main.tf` — ativar quando necessário, junto com a var `professional_ip` (hoje vazia em `terraform.tfvars`).
- **Segredos**: `terraform.tfvars`, `*.tfstate`/`*.tfstate.backup` e `.terraform/` já cobertos pelo `.gitignore`. `tfplan.out` foi adicionado ao `.gitignore` — o binário do plan embute os valores das variáveis (incluindo IP pessoal) e não estava coberto pelo padrão `*.tfplan`.
- **State**: local (`terraform.tfstate` na própria pasta `terraform/`), sem backend remoto — sem locking, risco de perda se o arquivo sumir.
- **Deploy**: `terraform apply` já executado com sucesso — instância e SG ativos na conta AWS do projeto.
- **Comandos úteis**:
  ```
  cd terraform
  terraform plan -out=tfplan.out
  terraform apply tfplan.out
  ```

## Débitos técnicos / pontos de atenção conhecidos

- **Wazuh Server ainda manual**: apenas o agent Linux está em Terraform até o momento. Se/quando o Server for migrado, os recursos existentes (EC2, SG `wazuh-sg`, EIP) precisarão ser importados (`terraform import`) ou recriados do zero via código — decisão em aberto.
- **Terraform state local, sem backend remoto** (ex: S3 + DynamoDB lock) — sem colaboração multi-máquina segura nem locking.
- **Sem budget/billing alarm configurado formalmente** — vale considerar AWS Budgets ou CloudWatch Billing Alarm, já que é conta free tier com limites.
- **Volume EBS root inicial (8GB) é insuficiente** para instalação all-in-one do Wazuh — causa disk full na instalação do wazuh-manager. Sempre provisionar 30-50GB desde a criação da instância.
- **Path de download do instalador**: `https://packages.wazuh.com/4.x/wazuh-install.sh` retornou `AccessDenied` em uma tentativa; o path versionado `https://packages.wazuh.com/4.14/wazuh-install.sh` funcionou de forma consistente. Preferir sempre a versão explícita.

## Troubleshooting documentado (resumo)

Detalhes completos em `wazuh-deployment.md`. Resumo rápido para referência rápida:

1. **Disco cheio na instalação do wazuh-manager** → expandir EBS (console) + `growpart`/`resize2fs` (SO) + limpar pacote quebrado (`dpkg --remove --force-remove-reinstreq`, `rm -rf /var/ossec`) + reinstalar com `wazuh-install.sh -a -o`.
2. **Certificado Let's Encrypt não aplicava** → edição do `opensearch_dashboards.yml` via `nano` não salvou; corrigido com `sed` direto no arquivo, seguido de `systemctl restart wazuh-dashboard`.
3. **Agent Windows: Error 1925 (privilégios insuficientes)** → `msiexec /q` falha silenciosamente se o PowerShell não estiver elevado ("Executar como administrador").
4. **Agent Windows preso em "Never connected"** → regra do SG para porta 1515 liberada primeiro (completa enrollment), depois 1514 (necessária para streaming de eventos passar a "Active").

## Comandos do dia a dia

**Conexão**
```
ssh Wazuh-Server
```

**Status dos serviços**
```
sudo /var/ossec/bin/wazuh-control status
sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard
```

**Logs**
```
sudo tail -f /var/ossec/logs/ossec.log
```

**Recuperar credenciais geradas na instalação**
```
sudo tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
```

**Verificar certificado ativo no dashboard**
```
openssl s_client -connect localhost:443 -servername <seu-dominio-duckdns> 2>/dev/null | openssl x509 -noout -issuer
```

**Seu IP público atual (para atualizar regras do SG)**
```
curl https://checkip.amazonaws.com
```

## Próximos passos

- [ ] Integração AWS: GuardDuty + CloudTrail → S3 → módulo `aws-s3` do Wazuh (requer IAM Role dedicada com leitura restrita aos buckets)
- [x] Segundo agent, em instância Linux separada, para simular múltiplas plataformas monitoradas — provisionado via Terraform (`terraform/`)
- [ ] Instalar e registrar o Wazuh agent na instância Linux provisionada (repetir o fluxo de enrollment: SG 1515 → 1514, `manager address` via DuckDNS)
- [ ] Regras de alerta customizadas no dashboard
- [ ] Migrar o Wazuh Server (EC2, `wazuh-sg`, EIP) para Terraform, usando o padrão do agent como base
- [ ] Configurar backend remoto para o Terraform state (S3 + DynamoDB lock)
- [ ] AWS Budgets / billing alarm, já que a conta é free tier

## Commit convention

Formato: `<tipo>: descrição no imperativo`.

- Tipos usados até aqui: `feat` (novo recurso/provisionamento), `security` (remoção de dados sensíveis, hardening), `docs` (documentação), `fix` (correção de bug), `chore` (manutenção sem impacto funcional).
- Descrição em minúsculas, no imperativo (ex: "provision", "remove", "add", não "provisioned"/"removed"/"added"), sem ponto final.
- Exemplos reais do histórico: `feat: provision linux agent via Terraform, EC2 + dedicated SG`, `security: remove exposed IPs, domain names, and files paths from .md file`.

## Ferramentas e skills usadas até aqui

- **AWS Console** (EC2, Security Groups, Volumes, Elastic IPs)
- **SSH** (`ed25519`, `~/.ssh/config`)
- **PowerShell** (Windows, instalação do agent)
- **DuckDNS** (DNS dinâmico gratuito)
- **certbot** (Let's Encrypt, modo standalone)
- **KeePass** (armazenamento de credenciais)
- **Terraform** (`hashicorp/aws` v6.60.0) — usado até aqui para provisionar o agent Linux (EC2 + SG dedicado + key pair)
