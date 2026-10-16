# 🚀 Guia de instalação e Uso

Guia de instalação, uso e resolução de problemas do **AD Health Check Toolkit**.

---

## 📑 Índice

1. [Requisitos](#1-requisitos)
2. [Instalação](#2-instalação)
3. [Uso](#3-uso)
4. [Interpretando resultados](#4-interpretando-resultados)
5. [Troubleshooting](#5-troubleshooting)

---

## 1. Requisitos

### 🖥️ Sistema operacional

- **Windows Server 2016, 2019, 2022 ou 2025**.
- A ferramenta deve ser executada **de dentro de um Domain Controller**. Não é suportada execução de workstation.
- Console: **Windows Terminal** recomendado. Também funciona em `conhost.exe` (com fallback automático para ASCII).

### ⚡ PowerShell

- **PowerShell 7.0 ou superior** (obrigatório).
- O `Invoke-ADHealthCheck.ps1` detecta a versão e, se estiver em PowerShell 5.1, oferece instalação automática via `winget` ou MSI da Microsoft. Após instalar, ele relança a si mesmo em `pwsh.exe`.
- Para impedir a instalação automática (ambientes restritos): `-SkipAutoInstall`.

### 🧩 Módulos e ferramentas

| Dependência | Obrigatória | Uso |
|---|---|---|
| `ActiveDirectory` (RSAT-AD-PowerShell) | **Sim** | Descoberta, replicação, FSMO, topologia |
| `DnsServer` (RSAT-DNS-Server) | Recomendado | Verificações estruturadas de DNS |
| `dcdiag.exe` (RSAT-AD-Tools) | Recomendado | Testes DCDiag e `dcdiag /test:dns` |
| `repadmin.exe` (RSAT-AD-Tools) | Recomendado | Evidência adicional de replicação |
| `dnscmd.exe` (RSAT-DNS-Server) | Opcional | Não usado por padrão |
| `w32tm.exe` (built-in) | Sim | Sincronização de horário |

A ferramenta detecta automaticamente o que está disponível. Se algo faltar, o módulo dependente reporta `UNKNOWN` com o motivo documentado, **sem interromper o restante da execução**.
No menu interativo, tem uma opção **[5]** dedicada a verificar dependências e pré-requisitos.

### 🔑 Privilégios

- Leitura em **AD DS** (objetos, configuração, partições).
- Leitura em **DNS Server** (zonas, registros).
- Leitura em **Windows Event Log** (Directory Service, DNS Server, DFS Replication, System).
- `Security` log: **opt-in** via `-IncludeSecurityLog` (ver `SECURITY.md`).

---

## 2. Instalação

### 2.1 Clonar o repositório

```powershell
git clone https://github.com/<user>/ad-health-check-toolkit.git
cd ad-health-check-toolkit
```

---

## 3. Uso

### 3.1 Modo interativo (TUI)

Executado sem parâmetros ou com `-Interactive`:

```powershell
.\Invoke-ADHealthCheck.ps1
```

**Fluxo da TUI:**

- Banner + painel de ambiente com versão, PowerShell, domínio detectado, DCs identificados e estado das dependências.
- **Menu principal:**

```text
[1] Auditoria completa (8 categorias padrão).
[2] Selecionar auditorias (checkbox das 11 categorias).
[3] Auditoria profunda (inclui DCDiag, Topology, EventLogs, GroupPolicy).
[4] Auditoria de um DC específico (aparece apenas se houver 2+ DCs).
[5] Verificar dependências e pré-requisitos.
[0] Sair.
```

- Progresso em tempo real durante a execução, com status por categoria.
- Resumo executivo com score, contadores e lista de itens que requerem atenção.
- **Menu pós-execução:**

```text
[1] Abrir o HTML gerado.
[2] Exportar (HTML, JSON, CSV ou todos).
[3] Executar outra auditoria.
[0] Voltar ao menu principal.
```

### 3.2 Modo clássico (não-interativo)

```powershell
# Auditoria completa do domínio corrente
.\Invoke-ADHealthCheck.ps1 -PassThru

# Apenas categorias específicas
.\Invoke-ADHealthCheck.ps1 -Checks Connectivity,Services,DNS

# Um DC específico
.\Invoke-ADHealthCheck.ps1 -DomainController "DC01.empresa.local"

# Domínio remoto
.\Invoke-ADHealthCheck.ps1 -Domain "empresa.local"

# Auditoria profunda
.\Invoke-ADHealthCheck.ps1 -IncludeDcdiag -IncludeTopology -IncludeEventLogs -IncludeGroupPolicy

# Exportar apenas HTML
.\Invoke-ADHealthCheck.ps1 -ReportFormat HTML

# Sem gerar relatório (apenas coleta)
.\Invoke-ADHealthCheck.ps1 -NoReport -PassThru

# Diretório de saída customizado
.\Invoke-ADHealthCheck.ps1 -OutputPath "C:\ADReports"
```

### 3.3 Referência de parâmetros

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---|---|
| `-Domain` | string | domínio corrente | FQDN do domínio a avaliar |
| `-DomainController` | string[] | todos os DCs | FQDNs de DCs específicos |
| `-OutputPath` | string | `Reports/<timestamp>` | Diretório de saída |
| `-Checks` | string[] | categorias padrão | Categorias a executar |
| `-EventLookbackDays` | int (1-365) | 7 | Período de análise dos logs |
| `-IncludeEventLogs` | switch | off | Habilita coleta de eventos |
| `-IncludeSecurityLog` | switch | off | Habilita coleta do Security log (ver `SECURITY.md`) |
| `-IncludeDnsDetails` | switch | off | Detalhes extras de DNS |
| `-IncludeDcdiag` | switch | off | Executa testes DCDiag |
| `-IncludeTopology` | switch | off | Habilita análise de topologia |
| `-IncludeGroupPolicy` | switch | off | Habilita verificações de GPO |
| `-SkipPing` | switch | off | Pula teste ICMP |
| `-PassThru` | switch | off | Emite o resultado consolidado |
| `-Credential` | PSCredential | corrente | Credencial para operações remotas |
| `-SkipAutoInstall` | switch | off | Não instala PowerShell 7 automaticamente |
| `-ThrottleLimit` | int (1-50) | 5 | Paralelismo máximo |
| `-NoReport` | switch | off | Não gerar relatórios |
| `-ReportFormat` | string[] | `HTML, JSON, CSV` | Formatos a gerar |
| `-Interactive` | switch | off | Força modo TUI |

### 3.4 Categorias disponíveis

```powershell
Connectivity         # ICMP, TCP, DNS, acesso administrativo
Services             # Serviços essenciais por DC
DNS                  # Zonas, SOA, SRV, dcdiag /test:dns
Replication          # Get-ADReplication* + repadmin /replsummary
SysvolNetlogon       # SYSVOL, NETLOGON, DFSR
FSMO                 # Papéis de domínio e floresta
TimeSynchronization  # w32tm
DCDiag               # 13 testes dcdiag /test:X (opt-in)
EventLogs            # Logs de eventos significativos (opt-in)
Topology             # Sites, subnets, site links, KCC, ISTG (opt-in)
GroupPolicy          # AD ↔ SYSVOL consistency (opt-in)
```

### 3.5 Saídas

Cada execução gera em `Reports/<timestamp>/`:

| Arquivo | Descrição |
|---|---|
| `ADHC-Report-<timestamp>.html` | Relatório interativo (self-contained) |
| `ADHC-Results-<timestamp>.json` | Dados estruturados completos |
| `ADHC-Results-<timestamp>.csv` | Tabela achatada |
| `ADHC-<timestamp>.log` | Log técnico da execução |

> Para desabilitar a geração de relatórios: `-NoReport`. Para limitar a formatos: `-ReportFormat HTML`.

---

## 4. Interpretando resultados

### 4.1 Status

| Status | Significado |
|---|---|
| `PASS` | Verificação concluída sem problemas |
| `INFO` | Informação relevante; nenhuma ação necessária |
| `WARNING` | Condição que merece investigação |
| `FAIL` | Falha confirmada |
| `UNKNOWN` | Não foi possível determinar o resultado |

### 4.2 Severidade

| Severidade | Interpretação |
|---|---|
| `Critical` | Impacto imediato na autenticação, replicação ou disponibilidade |
| `High` | Impacto significativo que deve ser corrigido com prioridade |
| `Medium` | Impacto moderado; corrigir quando possível |
| `Low` | Impacto pequeno; corrigir em janela de manutenção |
| `Informational` | Sem impacto; informação apenas |

### 4.3 Score de saúde

O score é calculado a partir dos resultados:

- **Base:** 100 pontos.
- **Deduções:** `Critical` = −15, `High` = −8, `Medium` = −3, `Low` = −1, `Informational` = 0.
- `UNKNOWN` deduz metade do peso da severidade correspondente.
- `PASS` e `INFO` nunca deduzem.
- **Faixas:** 95-100 Healthy, 80-94 Good, 60-79 Attention, 40-59 Degraded, 0-39 Critical.

> O relatório HTML lista quais verificações mais deduziram para o score — a métrica é **auditável**.

### 4.4 UNKNOWN não é falha

Um `UNKNOWN` significa que a ferramenta não conseguiu determinar o resultado — por falta de módulo, permissão, tempo limite, ou saída não reconhecida. **Não é um problema do domínio.** Cada `UNKNOWN` traz no `Evidence` o motivo.

---

## 5. Troubleshooting

### 5.1 "PowerShell 7 not found. Attempting installation..."

Mensagem normal na primeira execução em um host com apenas PS 5.1. A instalação tenta `winget` e, se falhar, baixa o MSI oficial da Microsoft.

Em ambiente sem internet ou com `winget` bloqueado, instale o PowerShell 7 manualmente:

- **Download:** https://aka.ms/powershell
- **MSI:** `PowerShell-7.x.x-win-x64.msi`

### 5.2 Categorias mostrando UNKNOWN

Verifique a saída de **[5] Verificar dependências e pré-requisitos**. A causa mais comum é módulo RSAT ausente.

**Soluções:**

```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
Import-Module ActiveDirectory
```

### 5.3 "Category X failed to execute"

A categoria travou com exceção não tratada. O resultado é registrado como `SYS-X` com `Status=UNKNOWN`. Verifique o log técnico (`Reports/<timestamp>/ADHC-<timestamp>.log`) para o stacktrace.

### 5.4 Relatório HTML não abre

O HTML é auto-contido (sem dependências externas). Se não abrir:

- Verifique se o arquivo existe e tem tamanho > 0.
- Abra manualmente com um navegador (`Start-Process arquivo.html`).
- Verifique se a extensão é `.html` e não `.txt`.

### 5.5 "Access denied" em verificações remotas

Em domínios com múltiplos DCs, o toolkit usa **WinRM** para avaliar DCs remotos. Se o WinRM estiver desabilitado:

- As verificações remotas caem para **CIM over DCOM**.
- Se ambos falharem, o DC é marcado como `UNREACHABLE` e as demais categorias degradam para `UNKNOWN` para aquele DC.

**Verificar WinRM:**

```powershell
Test-WSMan -ComputerName DC01.empresa.local
```

### 5.6 Caracteres quebrados no console (Unicode)

O toolkit detecta suporte a Unicode automaticamente. Se sua saída mostrar caracteres como `?` ou `□`:

- Use **Windows Terminal** (suporta VT/Unicode).
- Ou rode com `[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)` no início da sessão.

> A ferramenta cai para **ASCII automaticamente** quando detecta terminal incompatível.

### 5.7 DCDiag retorna verdicts inconclusivos

Alguns testes do `dcdiag` retornam vereditos "não passou" mesmo em ambientes saudáveis (ex.: `SystemLog` em DC único sem eventos relevantes). Esses casos aparecem como `WARNING/Medium` com `IsInconclusive=$true` — **não é problema do domínio**, é limitação do próprio `dcdiag`.

### 5.8 Erro de encoding em evidências (repadmin, dcdiag)

O toolkit lê a saída de `repadmin.exe` e `dcdiag.exe` como **CP-850** (encoding OEM do Windows pt-BR) explicitamente. Se aparecerem `?` no lugar de acentos no bloco `Evidence.Raw` do HTML:

- Verifique que a versão do toolkit é **≥ 0.1.0**.
- Se persistir, abra issue com o campo `Evidence.Raw` completo.

### 5.9 Score abaixo de 100 em ambiente "saudável"

O score é **realista**. Um domínio com pequenos warnings legítimos (eventos de log recorrentes, DNS com registros duplicados, etc.) terá score menor que 100. Consulte a seção **"Itens que requerem atenção"** no resumo para ver o que deduziu pontos.
