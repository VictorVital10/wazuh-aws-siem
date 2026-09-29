# wazuh-aws-siem

SIEM com Wazuh na AWS, all-in-one (manager + indexer + dashboard numa única EC2). Projeto de estudo/portfólio.

Detalhes completos e histórico de decisões: `CLAUDE.md`. Log de deploy e troubleshooting: `WAZUH-DEPLOYMENT.md`.

## Arquitetura em duas contas

- **Conta B (Free Tier)**: Wazuh Server (EC2 all-in-one) e o agent Linux. Standalone, nunca unir a uma Organization.
- **Conta A (PAYG)**: GuardDuty, bucket S3 de findings e a chave KMS. Acesso da Conta B é cross-account via bucket policy, sem credenciais estáticas.
- Ambas em `us-east-2`.

## Estado atual (resumo)

- Wazuh Server: Ubuntu `m7i-flex.large`, EBS 50GB, v4.14.7. Elastic IP + DuckDNS + TLS (Let's Encrypt).
- Agent Linux (`linux_agent`, `t3.micro`) via Terraform; agent Windows manual. Ambos Active.
- Integrações AWS concluídas: CloudTrail (`vv-wazuh-cloudtrail-logs`) e GuardDuty (`vv-wazuh-guardduty-findingss`, cross-account), ambas via módulo `aws-s3` do Wazuh Manager.
- 1 regra de alerta customizada em produção (SID `100002`).

## Convenções

- Chaves SSH `ed25519`, uma por máquina, nunca reutilizada.
- Agents apontam para o manager via domínio DuckDNS, nunca IP direto.
- Nenhuma porta sensível (22, 443, 1514, 1515) exposta a `0.0.0.0/0` — sempre restrita por IP.
- Segredos (chaves, senhas, `.tfvars`) nunca no Git nem só no terminal — KeePass + `.gitignore`.
- Terraform em `terraform/`, provider `hashicorp/aws` v6.60.0, state local (sem backend remoto).

## Regras de alerta customizadas

- Local: `/var/ossec/etc/rules/local_rules.xml`. Nunca editar regras nativas em `/var/ossec/ruleset/rules/`.
- SID customizado sempre a partir de `100000`.
- Antes de usar um SID nativo numa regra, confirmar contra um log real com `wazuh-logtest` — nunca assumir pela descrição (mesmo "tipo" de evento pode ter SIDs diferentes dependendo do método usado, ex.: auth por chave vs. senha).
- Fluxo: escrever a regra → validar sintaxe (`wazuh-analysisd -t`) → `systemctl restart wazuh-manager` → testar com `wazuh-logtest` → validar de ponta a ponta com tráfego real (`tail -f alerts.json`).

## Provisionamento

- **Wazuh Server**: manual, via console AWS + terminal (SSH/PowerShell).
- **Agent Linux**: via Terraform — único recurso do projeto em IaC até agora.

## Comandos úteis

```
ssh Wazuh-Server
sudo /var/ossec/bin/wazuh-control status
sudo tail -f /var/ossec/logs/alerts/alerts.json
curl https://checkip.amazonaws.com   # IP público atual, para atualizar o SG
```

## Commit convention

`<tipo>: descrição no imperativo`, minúsculo, sem ponto final. Tipos usados: `feat`, `fix`, `docs`, `security`, `chore`.
