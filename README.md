# Wazuh AWS SIEM

Laboratório de SIEM (Security Information and Event Management) usando **Wazuh**, hospedado na **AWS**, em formato **all-in-one** (manager + indexer + dashboard na mesma instância EC2).

Projeto de estudo/portfólio, parte da iniciativa **VV Cloud Security**.

## Objetivo

Construir um ambiente prático de SIEM para estudar:

- Detecção e correlação de eventos de segurança
- Gestão de agents e coleta de logs
- Hardening de infraestrutura na AWS
- Integração futura com serviços de segurança da AWS (CloudTrail, GuardDuty)

## Arquitetura

Topologia **all-in-one**: uma única instância EC2 rodando manager, indexer e dashboard do Wazuh — sem cluster, sem alta disponibilidade. Escolha deliberada para focar em aprendizado, não em produção.

| Componente | Detalhe |
|---|---|
| Instância EC2 | Ubuntu, `m7i-flex.large` (2 vCPU / 8GB RAM) |
| Volume EBS (root) | 50GB |
| Security Group | Portas 443, 22, 1514, 1515 — restritas a IPs específicos, nunca `0.0.0.0/0` |
| Elastic IP | Associado à instância |
| Domínio | DuckDNS (DNS dinâmico gratuito) apontando ao Elastic IP |
| TLS | Certificado Let's Encrypt via certbot, renovação automática |
| Wazuh | v4.14.7 |

## Provisionamento

Todo o setup atual foi feito **manualmente**, via console AWS + terminal (SSH/PowerShell) — sem Terraform/IaC neste projeto ainda. A abordagem escolhida foi hands-on primeiro (entender cada componente passo a passo), automação depois.

## Segurança aplicada

- Dashboard do Wazuh (porta 443) nunca exposto para a internet — acesso restrito por IP.
- Portas de streaming de eventos (1514) e enrollment de agents (1515) também restritas por IP.
- Acesso SSH via chave `ed25519`, um par por máquina, sem autenticação por senha.
- Elastic IP mantido sempre associado à instância ativa, evitando cobrança por IP ocioso.
- Credenciais armazenadas em gerenciador de senhas, nunca deixadas apenas no output do terminal.
- Conta AWS standalone (free tier), isolada de outras Organizations.

## Débitos técnicos conhecidos

- Sem Terraform/IaC — infraestrutura criada manualmente no console.
- Sem budget/billing alarm configurado formalmente.
- Volume EBS root inicial (8GB) mostrou-se insuficiente para a instalação all-in-one do Wazuh; recomendado provisionar 30-50GB desde a criação da instância.

## Próximos passos

- [ ] Integração AWS: GuardDuty + CloudTrail → S3 → módulo `aws-s3` do Wazuh
- [ ] Segundo agent, em instância Linux separada, para simular múltiplas plataformas monitoradas
- [ ] Regras de alerta customizadas no dashboard
- [ ] Avaliar migração para Terraform (IaC) uma vez que a arquitetura manual esteja validada
- [ ] Configurar AWS Budgets / billing alarm

---

Projeto de estudo pessoal — não recomendado para uso em produção sem revisão adicional de hardening e alta disponibilidade.
