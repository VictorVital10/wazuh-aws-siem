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
| Agents registrados | 2 (Windows pessoal + `Linux-Agent` via Terraform, ambos Active) |
| Instância EC2 (Linux Agent) | `linux_agent`, `t3.micro` — provisionada via Terraform |
| Security Group (Linux Agent) | `agents_sg` — porta 22 restrita a IP específico, egress liberado — via Terraform |
| Regras de alerta customizadas | 1 (`local_rules.xml`, SID `100002` — ver seção dedicada abaixo) |

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

## Regras de alerta customizadas (detecção)

- **Localização**: `/var/ossec/etc/rules/local_rules.xml` no Wazuh Server. Nunca editar regras nativas em `/var/ossec/ruleset/rules/` (são sobrescritas em updates).
- **Convenção de SID**: regras customizadas começam em `100000+` (faixa reservada, evita conflito com o ruleset oficial).
- **Fluxo de trabalho adotado** para criar/validar uma regra nova (repetir para as próximas):
  1. Identificar o evento que se quer detectar e a regra nativa correspondente (nunca assumir o SID de cabeça — confirmar sempre via `grep` no `/var/ossec/ruleset/rules/`).
  2. Escrever a regra em `local_rules.xml` com `id` na faixa `100000+`.
  3. Validar sintaxe sem reiniciar nada: `sudo /var/ossec/bin/wazuh-analysisd -t`.
  4. Reiniciar o manager: `sudo systemctl restart wazuh-manager`.
  5. Testar a decodificação/regra com `sudo /var/ossec/bin/wazuh-logtest` (útil para regras simples; **não confiável para correlação com `frequency`/`timeframe`**, pois cada linha digitada é tratada como sessão isolada, sem acumular estado).
  6. Validar de ponta a ponta com tráfego real, conferindo `sudo tail -f /var/ossec/logs/alerts/alerts.json`.

### Regra implementada: SID 100002 — login bem-sucedido após múltiplas falhas de chave SSH

```xml
<group name="local,syslog,sshd,">
  <rule id="100002" level="12" frequency="3" timeframe="180">
    <if_sid>5715</if_sid>
    <if_matched_sid>5762</if_matched_sid>
    <same_source_ip />
    <description>sshd: successful login after multiple failed attempts from same source</description>
  </rule>
</group>
```

- **Lógica**: dispara quando um login SSH bem-sucedido (`5715`) acontece dentro de 180s após 3+ ocorrências de reset de conexão por falha de chave (`5762`), vindas do mesmo IP de origem.
- **Por que `5762` e não outro SID de "authentication failed"** — este foi o ponto de maior aprendizado do processo, documentado para não repetir o erro:
  - O ambiente usa **somente autenticação por chave pública** (sem senha habilitada). Isso significa que os SIDs "clássicos" de força bruta por senha (`5716` genérico, `5760` para `Failed password|Failed keyboard|authentication error`) **não se aplicam** — eles nunca disparam nesse setup, porque o cliente SSH nem chega a tentar senha.
  - O log real gerado por uma tentativa com chave inválida é: `Connection reset by authenticating user <user> <ip> port <porta> [preauth]` — mensagem completamente diferente de "Failed password".
  - Esse padrão bate com o SID **`5762`** (`sshd: connection reset`, level 4), confirmado via `wazuh-logtest` contra um log real coletado com `journalctl -u ssh`.
  - **Lição**: sempre confirmar o SID contra um log real do próprio ambiente (via `wazuh-logtest`), nunca assumir pela descrição/documentação — o mesmo "tipo" de evento (auth failed) pode ter SIDs completamente diferentes dependendo do método de autenticação usado (senha vs. chave) e da mensagem exata gerada pelo `sshd`.
- **Teste de validação realizado** (via SSH real, não só `wazuh-logtest`):
  1. 3 tentativas de conexão com uma chave `ed25519` gerada só para teste (não cadastrada no agent) → 3 alertas `5762` no manager.
  2. 1 conexão bem-sucedida com a chave real (`wazuh-server.pub`, a mesma usada pelo Terraform em `public_key_path`) dentro da janela de 180s.
  3. Resultado: alerta `100002` disparado, `level: 12`, com `previous_output` mostrando as falhas anteriores como contexto — confirmando a correlação funcionando ponta a ponta.
- **Pendências/ideias para próximas regras** (não implementadas ainda):
  - Regra de força bruta "pura" (só as falhas, sem exigir sucesso em seguida) — usar o mesmo SID base `5762` com `frequency`/`timeframe`/`same_source_ip`, sem o `if_sid=5715`.
  - Investigar o alerta `510` (`rootcheck` — "Trojaned version of file detected" em `/usr/bin/md5sum`) que apareceu durante os testes — provável falso positivo do scan nativo de integridade, mas ainda não investigado a fundo.

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
- [x] Instalar e registrar o Wazuh agent na instância Linux provisionada — agent `Linux-Agent` ativo, enrollment via DuckDNS
- [x] Primeira regra de alerta customizada (SID `100002` — login após múltiplas falhas de chave SSH), validada com tráfego real — ver seção dedicada acima
- [ ] Regra de força bruta "pura" (só falhas repetidas, sem exigir sucesso) — variação mais simples da 100002, mesmo SID base (`5762`)
- [ ] Investigar alerta `510` (rootcheck — possível falso positivo em `/usr/bin/md5sum`)
- [ ] Mais regras de alerta customizadas conforme necessidade (ex: mudança em arquivos críticos via `syscheck`)
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
