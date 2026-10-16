# 📖 Reference

Catálogo de verificações, arquitetura e limitações do **AD Health Check Toolkit**.

---

## 📑 Índice

1. [Catálogo de verificações](#1-catálogo-de-verificações)
2. [Arquitetura](#2-arquitetura)
3. [Limitações conhecidas](#3-limitações-conhecidas)

---

## 1. Catálogo de verificações

A ferramenta executa **~93 verificações** em **11 categorias**. Cada verificação retorna um objeto estruturado com `CheckId`, `Status`, `Severity`, `Evidence`, `PotentialImpact`, `PossibleCauses`, `RecommendedInvestigation` e `SuggestedCommands`.

### 1.1 Connectivity

**Fonte:** sockets TCP, `Resolve-DnsName`, ICMP, WinRM/CIM.

| CheckId | O que verifica | Severidade base |
|---|---|---|
| `CONN-DNS-FWD` | Resolve o FQDN do próprio DC | Critical |
| `CONN-DNS-REV` | Resolve reverso (PTR) do IPv4 do DC | Informational |
| `CONN-ICMP` | Envia echo ICMP ao DC | Informational |
| `CONN-TCP-53` | Porta DNS | High |
| `CONN-TCP-88` | Porta Kerberos | High |
| `CONN-TCP-389` | Porta LDAP | High |
| `CONN-TCP-636` | Porta LDAPS | High |
| `CONN-TCP-445` | Porta SMB | High |
| `CONN-TCP-135` | Porta RPC Endpoint Mapper | High |
| `CONN-TCP-5985` | Porta WinRM HTTP | High |
| `CONN-TCP-5986` | Porta WinRM HTTPS (opcional → INFO se fechada) | Informational |
| `CONN-ADMIN` | Acesso administrativo via WinRM/CIM | Medium |
| `CONN-REACH` | Resumo de alcance do DC | Critical |

### 1.2 Services

**Fonte:** `Get-Service` local ou remoto.

| CheckId | O que verifica |
|---|---|
| `SVC-NTDS` | Serviço NTDS (AD DS) |
| `SVC-DNS` | Serviço DNS Server |
| `SVC-NETLOGON` | Serviço Netlogon |
| `SVC-DFSR` | Serviço DFS Replication |
| `SVC-W32TIME` | Serviço Windows Time |
| `SVC-KDC` | Serviço Kerberos Key Distribution Center |
| `SVC-LANMANSERVER` | Serviço Server (SMB) |

### 1.3 DNS

**Fonte:** `Get-DnsServerZone`, `Get-DnsServerResourceRecord`, `Resolve-DnsName`, `dcdiag /test:dns /v`.

| CheckId | O que verifica | Severidade base |
|---|---|---|
| `DNS-ZONE-EXISTS` | Zona do domínio existe no DC | High |
| `DNS-ZONE-AD` | Zona é AD-integrated | High |
| `DNS-ZONE-SOA` | SOA primário aponta para DC conhecido | Medium |
| `DNS-SRV-LDAP` | Registro SRV `_ldap._tcp.dc._msdcs` | High |
| `DNS-SRV-KERB` | Registro SRV `_kerberos._tcp` | Critical |
| `DNS-SRV-PDC` | Registro SRV `_ldap._tcp.pdc._msdcs` | High |
| `DNS-SRV-GC` | Registro SRV `_gc._tcp` | Medium |
| `DNS-MULTI-A` | Múltiplos A para o mesmo DC (multi-NIC) | Informational |
| `DNS-REVERSE-MISSING-<ip>` | Sem PTR para um IP do DC | Informational |
| `DNS-DCDIAG-PARSE` | Parser reconheceu `dcdiag /test:dns` | Informational |
| `DNS-DCDIAG` | Veredito agregado do `dcdiag /test:dns` | High |
| `DNS-ZONE-QUERY` | Falha ao enumerar zonas | Medium |

### 1.4 Replication

**Fonte:** `Get-ADReplicationFailure`, `Get-ADReplicationPartnerMetadata`, `Get-ADReplicationSiteLink`, `repadmin /replsummary`.

| CheckId | O que verifica |
|---|---|
| `REPL-CMDLET-AVAILABLE` | Cmdlets `Get-ADReplication*` disponíveis |
| `REPL-FAILURE` | Parceiros em falha do DC local (`-Scope Server`) |
| `REPL-LAST-SUCCESS-<partner>` | Tempo desde a última replicação OK por parceiro |
| `REPL-PARTNER-COUNT` | Nº de parceiros vs. DCs esperados |
| `REPL-SITE-LINK` | Site links (cost, frequency, transport) |
| `REPL-REPADMIN-PARSE` | Parser reconheceu `repadmin /replsummary` |
| `REPL-REPADMIN-SUMMARY` | Veredito agregado do `repadmin /replsummary` |

### 1.5 FSMO

**Fonte:** `Get-ADDomain`, `Get-ADForest`.

| CheckId | O que verifica |
|---|---|
| `FSMO-DOMAIN-ROLES` | PDC, RID, Infrastructure em DCs acessíveis |
| `FSMO-FOREST-ROLES` | Schema Master, Domain Naming em DCs acessíveis |
| `FSMO-INFRASTRUCTURE-GC` | Infrastructure Master não é GC (exceto se todos forem) |

### 1.6 SYSVOL / NETLOGON

**Fonte:** `Get-SmbShare`, `Test-Path` em UNC, `Get-Service DFSR`.

| CheckId | O que verifica |
|---|---|
| `SYSVOL-SHARE-SYSVOL` | Share SYSVOL existe |
| `SYSVOL-SHARE-NETLOGON` | Share NETLOGON existe |
| `SYSVOL-PATH-DOMAIN` | `\\DC\SYSVOL\<domain>` acessível |
| `SYSVOL-PATH-POLICIES` | `\\DC\SYSVOL\<domain>\Policies` acessível |
| `SYSVOL-DFSR-STATE` | DFSR rodando e FRS ausente |
| `NETLOGON-SHARE-CONTENT` | NETLOGON contém arquivos (INFO) |
| `SYSVOL-DFSR-BACKLOG` | (multi-DC) backlog de replicação |

### 1.7 TimeSynchronization

**Fonte:** `Get-Service`, `w32tm /query /status`, `/configuration`, `/peers`, `/stripchart`.

| CheckId | O que verifica |
|---|---|
| `TIME-W32TIME-SERVICE` | Serviço W32Time rodando |
| `TIME-CONFIG-TYPE` | `Type` é `NT5DS` ou `NTP` |
| `TIME-PDC-EXPECTATION` | PDC usa NTP; não-PDC usa NT5DS |
| `TIME-SOURCE` | Fonte não é Local CMOS Clock |
| `TIME-STRATUM` | Stratum < 16 |
| `TIME-LAST-SYNC` | Última sincronização < 24h |
| `TIME-PEERS` | Peers ativos |
| `TIME-OFFSET` | Offset < 5s contra a fonte |
| `TIME-W32TM-PARSE` | Parser reconheceu `w32tm` |

### 1.8 DCDiag *(opt-in)*

**Fonte:** 13 invocações individuais de `dcdiag /test:X`.

Cada teste vira um check:

`DCDIAG-CONNECTIVITY`, `DCDIAG-ADVERTISING`, `DCDIAG-SERVICES`, `DCDIAG-REPLICATIONS`, `DCDIAG-SYSVOLCHECK`, `DCDIAG-NETLOGONS`, `DCDIAG-FSMOCHECK`, `DCDIAG-KNOWSOFROLEHOLDERS`, `DCDIAG-MACHINEACCOUNT`, `DCDIAG-SYSTEMLOG`, `DCDIAG-TOPOLOGY`, `DCDIAG-VERIFYREFERENCES`, `DCDIAG-LOCATORCHECK`.

Mais `DCDIAG-PARSE` (cobertura do parser).

### 1.9 EventLogs *(opt-in)*

**Fonte:** `Get-WinEvent` com filtro por IDs significativos e período.

| CheckId | Log | IDs significativos |
|---|---|---|
| `EVT-DIRECTORY-SERVICE` | Directory Service | 1083, 1084, 1311, 1388, ... |
| `EVT-DNS-SERVER` | DNS Server | 4010, 4013, 4015, ... |
| `EVT-DFS-REPLICATION` | DFS Replication | 4004, 4012, 4602, ... |
| `EVT-SYSTEM` | System | 5719, 5783, 1128, ... |
| `EVT-SECURITY` | Security *(opt-in)* | 4625, 4740, 4771, 4776 |

> IDs na whitelist (`AcceptableIds` em `Defaults.psd1`) são registrados mas **nunca elevam severidade**.

### 1.10 Topology *(opt-in)*

**Fonte:** `Get-ADReplicationSite`, `Get-ADReplicationSubnet`, `Get-ADReplicationSiteLink`, `Get-ADReplicationConnection`, `Get-ADObject`.

| CheckId | O que verifica |
|---|---|
| `TOPO-SITES` | Pelo menos 1 site configurado |
| `TOPO-SUBNETS` | Subnets mapeadas (INFO em single-site, WARNING em multi-site) |
| `TOPO-SUBNET-ORPHAN` | Subnets sem site |
| `TOPO-DC-SITE-ASSIGNMENT` | Cada DC em site válido |
| `TOPO-SITE-LINKS` | Site links presentes |
| `TOPO-SITE-LINK-BRIDGES` | Site link bridges (INFO) |
| `TOPO-CONNECTIONS` | Objetos de conexão KCC |
| `TOPO-ISTG` | ISTG por site (INFO) |

### 1.11 GroupPolicy *(opt-in)*

**Fonte:** `Get-GPO`, `Get-ChildItem` em `\\DC\SYSVOL\<domain>\Policies`.

| CheckId | O que verifica |
|---|---|
| `GPO-MODULE` | Módulo `GroupPolicy` disponível |
| `GPO-SYSVOL-ACCESS` | Pasta `Policies` acessível em todos os DCs |
| `GPO-CNTFS-READY` | Pelo menos 1 GPO em SYSVOL |
| `GPO-COUNT-MATCH` | Comparação AD vs. SYSVOL (INFO) |
| `GPO-SYSVOL-ORPHAN` | Pastas em SYSVOL sem GPO correspondente |
| `GPO-AD-ORPHAN` | GPOs no AD sem pasta em SYSVOL (FAIL/High) |
| `GPO-DEFAULT-POLICIES` | `Default Domain Policy` e `Default Domain Controllers Policy` |
| `GPO-DFSR-BACKLOG` | Backlog DFSR (multi-DC) |
| `GPO-PARSE` | Cobertura dos checks |

---

## 2. Arquitetura

### 2.1 Visão geral

```text
┌─────────────────────────────────────────────────────────────┐
│              Invoke-ADHealthCheck.ps1 (entry point)         │
│  - Bootstrap PS7                                            │
│  - Load Core/Config                                         │
│  - Detecta modo: TUI (sem params) vs. clássico (com params) │
└────────────┬─────────────────────────────────┬──────────────┘
             │                                 │
     ┌───────▼─────────┐               ┌───────▼─────────┐
     │   UI/ (TUI)     │               │  Modo clássico  │
     │  Banner, menu,  │               │   Chama Invoke- │
     │  seleção, prog. │               │   ADHCAssessment│
     └───────┬─────────┘               └───────┬─────────┘
             │                                 │
             └──────────────┬──────────────────┘
                            │
                  ┌─────────▼──────────┐
                  │  Orchestrator.ps1  │
                  │  Invoke-ADHCAssess │
                  └─────────┬──────────┘
                            │
             ┌──────────────┼──────────────┐
             │              │              │
        ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
        │Modules/ │    │Modules/ │    │Modules/ │
        │Connectiv│    │  DNS    │    │ ... 11  │
        └─────────┘    └─────────┘    └─────────┘
```

### 2.2 Estrutura de diretórios

```text
ad-health-check-toolkit/
├── Invoke-ADHealthCheck.ps1        # Entry point
├── Core/                           # Result model, logging, severity, remoting
│   ├── Core.psd1 / Core.psm1
│   ├── ResultModel.ps1
│   ├── Logger.ps1
│   ├── CapabilityProbe.ps1
│   ├── Remoting.ps1
│   └── Severity.ps1
├── Modules/                        # Diagnóstico + orquestrador
│   ├── Discovery.ps1
│   ├── Orchestrator.ps1
│   ├── Connectivity.ps1
│   ├── Services.ps1
│   ├── DNS.ps1
│   ├── Replication.ps1
│   ├── FSMO.ps1
│   ├── SysvolNetlogon.ps1
│   ├── TimeSynchronization.ps1
│   ├── DCDiag.ps1
│   ├── EventLogs.ps1
│   ├── Topology.ps1
│   ├── GroupPolicy.ps1
│   ├── HealthScoring.ps1
│   └── ReportGenerator.ps1
├── UI/                             # Interface interativa
│   ├── UI.ps1
│   ├── UI.Console.ps1
│   ├── UI.Banner.ps1
│   ├── UI.MainMenu.ps1
│   ├── UI.CheckSelection.ps1
│   ├── UI.Progress.ps1
│   ├── UI.Summary.ps1
│   └── UI.ExportMenu.ps1
├── Config/                         # Configuração versionada
│   ├── Defaults.psd1
│   ├── CheckCatalog.psd1
│   └── SeverityRules.psd1
├── Reports/                        # Relatórios gerados (gitignored)
├── docs/                           # Documentação
├── Tests/                          # Testes (planejado)
└── Examples/                       # Exemplos de uso
```

### 2.3 Contrato de resultado

Toda verificação retorna um objeto `ADHC.CheckResult` com:

| Campo | Tipo | Descrição |
|---|---|---|
| `CheckId` | string | Identificador estável (ex.: `DNS-SRV-KERB`) |
| `Category` | string | Categoria (ex.: `DNS`) |
| `Domain` | string | FQDN do domínio |
| `DomainController` | string | FQDN do DC avaliado (vazio para checks de domínio) |
| `ComputerName` | string | Alvo real da verificação |
| `Status` | enum | `PASS` / `WARNING` / `FAIL` / `INFO` / `UNKNOWN` |
| `Severity` | enum | `Critical` / `High` / `Medium` / `Low` / `Informational` |
| `Title` | string | Título legível |
| `Description` | string | Descrição do que foi verificado |
| `Evidence` | hashtable | Dados estruturados + raw truncado |
| `PotentialImpact` | string | Impacto potencial |
| `PossibleCauses` | string[] | Hipóteses (não afirmações) |
| `RecommendedInvestigation` | string[] | Passos de investigação |
| `SuggestedCommands` | string[] | Comandos sugeridos (não executados) |
| `DetectedAt` | datetime | Momento da detecção (UTC) |
| `Duration` | timespan | Duração da verificação |
| `ErrorCode` | string | Código nativo |
| `IsInconclusive` | bool | `true` quando não foi possível determinar |
| `RequiresElevation` | bool | Metadado |
| `WasSkipped` | bool | Se não foi executado |
| `SkipReason` | string | Motivo do skip |
| `ModuleVersion` | string | Versão do módulo |
| `ToolUsed` | string | Ferramenta/cmdlet usada |

### 2.4 Fluxo de execução

1. **Bootstrap** — se PS 5.1, instala PS 7 e relança.
2. **Load** — importa `Core/`, carrega `Config/*.psd1`, dot-sourceia `Discovery.ps1`, `HealthScoring.ps1`, `ReportGenerator.ps1`, `Orchestrator.ps1`.
3. **Capability probe** — verifica módulos RSAT, `dcdiag`, `repadmin`, `w32tm`, elevação.
4. **Detecção de modo** — TUI se sem parâmetros ou `-Interactive`; senão clássico.
5. **Discovery** — enumera DCs, papéis FSMO, floresta, sites.
6. **Orquestração** — para cada categoria selecionada, dot-sourceia o módulo, chama `Invoke-ADHC<Category>` com `-Context`, captura exceções individualmente.
7. **Consolidação** — agrega resultados, recalcula alcançabilidade, aplica score.
8. **Relatório** — gera HTML, JSON, CSV em `Reports/<timestamp>/`.
9. **Sumário** — exibe resumo executivo (TUI: painel; clássico: texto).

### 2.5 Princípios de design

- 🔒 **Read-only por construção** — nenhum cmdlet destrutivo é executado.
- 🧱 **Isolamento de falha** — uma categoria que falha não interrompe as demais.
- 🎯 **Fonte estruturada primeiro** — cmdlets `Get-AD*`/`Get-Dns*` preferidos; ferramentas externas como evidência.
- 🌎 **Localização tratada** — parsers para pt-BR e en-US; texto não reconhecido vira `UNKNOWN`, nunca `PASS`.
- 📦 **Sem dependências externas** — só PowerShell 7, RSAT e binários nativos.
- ⚙️ **Configuração versionada** — severidade, catálogo e defaults em `.psd1`.
- 🧩 **Contrato único** — todo módulo retorna `CheckResult[]`.

---

## 3. Limitações conhecidas

### 3.1 Funcionais

- **IPv6 / AAAA** — verificações desabilitadas por padrão (`IgnoreIPv6 = $true`).
- **DNS reverso para IPs sem zona** — reportado como `INFO`, não como falha.
- **Security log** — coleta restrita a 4 IDs, opt-in duplo (`-IncludeEventLogs` + `-IncludeSecurityLog`).
- **DFSR backlog multi-DC** — implementado como stub (multi-DC), aguardando validação em ambiente com 2+ DCs.
- **GPO** — foco em infraestrutura (AD ↔ SYSVOL), não em análise de políticas específicas.

### 3.2 Técnicas

- **Parsing de ferramentas externas** — `repadmin`, `dcdiag` e `w32tm` produzem saída textual. Parsers são testados em pt-BR e en-US, mas builds futuras do Windows Server podem alterar o formato. Texto não reconhecido vira `UNKNOWN`.
- **Encoding de console** — ferramentas externas escrevem em CP-850 (OEM pt-BR). Lido explicitamente como CP-850 para preservar acentos.
- **Modo interativo em SSH/WinRM** — a TUI usa `[Console]::ReadKey` e reposicionamento de cursor. Funciona em Windows Terminal e `conhost`. Pode degradar em sessões SSH ou WinRM.
- **Paralelismo** — a orquestração é sequencial. `-ThrottleLimit` existe mas ainda não é usado extensivamente.

### 3.3 Cobertura não implementada

- **Testes unitários automatizados** — planejado para versões futuras. A versão 0.1.0 foi validada contra ambientes AD reais.
- **Análise de clientes** — a ferramenta avalia infraestrutura, não clientes.
- **GPO processing em endpoints** — não escopo.
- **Schema/Configuration partition forensics** — não escopo.

### 3.4 Ambientes com comportamento diferente

- **Domínios com 1 DC** — verificações multi-DC emitem `INFO` "single-DC domain; not applicable" em vez de `UNKNOWN`.
- **RODCs** — verificações não ajustam o comportamento para RODCs (a ferramenta foi validada em DCs completos).
- **Florestas multi-domínio** — `-Domain` avalia um domínio por vez.

---

## 🔗 Ver também

- [Getting Started](getting-started.md) — instalação, uso e troubleshooting.
- [Security](security.md) — política read-only e dados coletados.
