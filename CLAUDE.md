# wazuh-aws-siem

Lab de SIEM usando **Wazuh** hospedado na AWS, em formato **all-in-one** (manager + indexer + dashboard na mesma instância EC2). Projeto de estudo/portfólio — parte da iniciativa **VV Cloud Security**.

## Contexto do projeto

- **Objetivo**: laboratório de SIEM com Wazuh para estudo de detecção, correlação de eventos e integração futura com ferramentas de segurança da AWS (CloudTrail, GuardDuty).
- **Topologia**: EC2 única (all-in-one), sem cluster, sem HA.
- **Conta AWS**: standalone free tier, separada das organizations `vav`/`jbdsa` — nunca deve ser unida a uma Organization (perderia o Free Plan).
- **Provisionamento atual**: manual, via console AWS + terminal (SSH/PowerShell). **Não há Terraform neste projeto ainda** — todo o setup até aqui foi feito passo a passo, com foco em entender cada componente antes de automatizar.
- **Abordagem de aprendizado**: hands-on primeiro (console/CLI), automação depois. Prioridade em entender o "porquê" de cada passo, não só copiar comandos.

## Estado atual da infraestrutura

| Componente | Valor |
|---|---|
| Instância EC2 | `Wazuh-Server`, Ubuntu, `m7i-flex.large` (2 vCPU / 8GB RAM) |
| Volume EBS (root) | 50GB (expandido de 8GB original — ver Troubleshooting) |
| Security Group | `wazuh-sg` — portas 443, 22, 1514, 1515, todas restritas a IPs específicos (nunca `0.0.0.0/0`) |
| Elastic IP | Alocado e associado à instância |
| Domínio | `vv-wazuh.duckdns.org` (DuckDNS, gratuito, apontando ao Elastic IP) |
| Certificado TLS | Let's Encrypt via certbot, válido até 12/11/2026, renovação automática |
| Wazuh | v4.14.7, instalação all-in-one |
| Agents registrados | 1 (Windows pessoal, status Active) |

## Convenções adotadas

- **Chaves SSH**: `ed25519`, um par por máquina (nunca reutilizar/copiar chave privada entre computadores). Organizadas em `C:\Users\vitas\.ssh\Wazuh-Server\`. Alias configurado em `~/.ssh/config` (host `Wazuh-Server`).
- **Acesso SSH**: restrito por IP público (`/32`) no Security Group. EC2 Instance Connect (browser) usado apenas no bootstrap inicial, antes de haver chave configurada — removido do SG depois.
- **Manager address para agents**: usar o domínio DuckDNS (`vv-wazuh.duckdns.org`), nunca o IP direto — mantém os agents funcionando mesmo se o Elastic IP mudar no futuro.
- **Credenciais**: armazenadas no KeePass (chaves SSH, senhas do dashboard). Nunca deixadas só no output do terminal.
- **Documentação**: OneNote (conceitos/hardening), Word (processos passo a passo), Markdown (registro técnico do projeto, como este e o `wazuh-deployment.md`).

## Avisos de segurança (aplicados até aqui)

- Wazuh Dashboard (porta 443) **nunca exposto para `0.0.0.0/0`** — restrito ao IP público de cada máquina usada no projeto.
- Portas 1514 (streaming de eventos) e 1515 (enrollment de agents) também restritas por IP, não abertas ao mundo.
- SSH (porta 22) restrito por IP; chave pública/privada em vez de senha.
- Elastic IP mantido sempre associado à instância rodando, para evitar cobrança por IP ocioso.
- Senha padrão do dashboard (`admin`) gerada na instalação — recuperável via `wazuh-install-files.tar` caso não tenha sido salva na hora.

## Débitos técnicos / pontos de atenção conhecidos

- **Sem Terraform / IaC ainda**: toda a infra foi criada manualmente no console. Se o projeto evoluir para IaC, os recursos precisarão ser importados (`terraform import`) ou recriados do zero via código — decisão em aberto.
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
openssl s_client -connect localhost:443 -servername vv-wazuh.duckdns.org 2>/dev/null | openssl x509 -noout -issuer
```

**Seu IP público atual (para atualizar regras do SG)**
```
curl https://checkip.amazonaws.com
```

## Próximos passos

- [ ] Integração AWS: GuardDuty + CloudTrail → S3 → módulo `aws-s3` do Wazuh (requer IAM Role dedicada com leitura restrita aos buckets)
- [ ] Segundo agent, em instância Linux separada, para simular múltiplas plataformas monitoradas
- [ ] Regras de alerta customizadas no dashboard
- [ ] Avaliar migração para Terraform (IaC) uma vez que a arquitetura manual estiver validada e estável
- [ ] AWS Budgets / billing alarm, já que a conta é free tier

## Ferramentas e skills usadas até aqui

- **AWS Console** (EC2, Security Groups, Volumes, Elastic IPs)
- **SSH** (`ed25519`, `~/.ssh/config`)
- **PowerShell** (Windows, instalação do agent)
- **DuckDNS** (DNS dinâmico gratuito)
- **certbot** (Let's Encrypt, modo standalone)
- **KeePass** (armazenamento de credenciais)
