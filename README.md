# 🩺 AD Health Check Toolkit

**Diagnóstico, auditoria e avaliação preventiva da saúde do Active Directory Domain Services (AD DS) — 100% read-only.**

`PowerShell 7+` · `Active Directory DS` · `DNS Server` · `DFSR` · `Group Policy` · `HTML/CSS/JS`

---

Uma ferramenta em **PowerShell 7** para administradores de sistemas, analistas de infraestrutura e profissionais de suporte **N2/N3** que precisam avaliar a saúde de um domínio Active Directory **sem executar nenhuma operação destrutiva**.

```text
█████╗ ██████╗ ██╗ ██╗ ██████╗
██╔══██╗██╔══██╗██║ ██║██╔════╝
███████║██║ ██║███████║██║
██╔══██║██║ ██║██╔══██║██║
██║ ██║██████╔╝██║ ██║╚██████╗
╚═╝ ╚═╝╚═════╝ ╚═╝ ╚═╝ ╚═════╝
```

**AD HEALTH CHECK TOOLKIT** — *Active Directory health assessment*
`PowerShell | Active Directory | DNS | Replication`

---

## 🔎 Visão geral

O toolkit avalia de forma **estruturada e independente**:

- 🖥️ **Controladores de domínio** — descoberta, site, sistema operacional, papel
- ⚙️ **Serviços essenciais** do Windows Server e do AD DS
- 🌐 **Conectividade** — ICMP, portas TCP, resolução DNS, acesso administrativo
- 🔄 **Replicação do Active Directory** — `Get-ADReplication*` + parser de `repadmin`
- 📡 **DNS integrado ao AD** — zonas, SOA, SRV, registros órfãos, `dcdiag`-based
- 📂 **SYSVOL e NETLOGON** — compartilhamentos, caminhos UNC, DFSR
- 👑 **Papéis FSMO** — domínio e floresta
- 🗺️ **Topologia e sites** — subnets, site links, KCC, ISTG
- ⏰ **Sincronização de horário** — `w32tm`
- 📋 **Eventos relevantes do Windows** — Directory Service, DNS, DFSR, System
- 🧩 **Políticas de Grupo** — consistência AD ↔ SYSVOL

> Cada verificação retorna um objeto estruturado com **evidência**, **impacto potencial**, **causas possíveis**, **investigação recomendada** e **comandos sugeridos** — mas **nenhum comando é executado automaticamente**.

---

## ✨ Recursos

- 🖥️ **Interface interativa (TUI)** com banner, menu, seleção de auditorias, progresso em tempo real, resumo executivo e exportação
- 🤖 **Modo clássico (não-interativo)** para automação e CI
- 📄 **Relatório HTML self-contained** — abre com duplo clique, sem internet, com filtros e detalhes expansíveis
- 📦 **Exportação JSON e CSV** opcional
- 🌎 **Parsers localizados** em `pt-BR` e `en-US` para `repadmin`, `dcdiag` e `w32tm`
- 🔤 **Fallback ASCII** para terminais sem suporte a Unicode
- 🧩 **Zero dependências externas** — apenas PowerShell 7, RSAT e binários nativos do Windows

---

## ✅ Requisitos

- Windows Server **2016 / 2019 / 2022 / 2025** (executado de dentro de um DC)
- **PowerShell 7** ou superior (o script detecta e oferece a instalação automática)
- `RSAT-AD-PowerShell`, `RSAT-AD-Tools`, `RSAT-DNS-Server` *(recomendado)*
- Privilégios de **leitura** em AD DS, DNS e logs de eventos

> Veja [`docs/getting-started.md`](docs/getting-started.md) para instruções detalhadas.

---

## 🚀 Início rápido

```powershell
# Clone o repositório
git clone https://github.com/MatheusCDB/AD-Health-Check-Toolkit.git
cd AD-Health-Check-Toolkit

# Modo interativo (TUI)
.\Invoke-ADHealthCheck.ps1

# Modo clássico (não-interativo)
.\Invoke-ADHealthCheck.ps1 -Domain "empresa.local" -Checks DNS,Replication -OutputPath "C:\Reports"

# Auditoria profunda (inclui DCDiag, Topology, EventLogs, GPO)
.\Invoke-ADHealthCheck.ps1 -IncludeDcdiag -IncludeTopology -IncludeEventLogs -IncludeGroupPolicy
```

---

## 🖥️ Modo interativo

Ao executar sem parâmetros, o toolkit abre a interface interativa:

```text
+-----------------------------------------------------------+
|                  AD HEALTH CHECK TOOLKIT                  |
+-----------------------------------------------------------+
|  [1] Auditoria completa do Active Directory               |
|  [2] Selecionar auditorias                                |
|  [3] Auditoria profunda (inclui DCDiag, Topology, ...)    |
|  [5] Verificar dependencias e pre-requisitos              |
|  [0] Sair                                                 |
+-----------------------------------------------------------+
```

> Consulte [`docs/getting-started.md`](docs/getting-started.md) para a lista completa de parâmetros e exemplos.

---

## 📁 Estrutura do projeto

```text
AD-Health-Check-Toolkit/
├── Invoke-ADHealthCheck.ps1   # Entry point
├── Core/                      # Result model, logging, severity, remoting
├── Modules/                   # Diagnostic categories + orchestrator
├── UI/                        # Interactive TUI
├── Config/                    # Defaults, catalog, severity rules (versioned)
├── Reports/                   # Generated reports (gitignored)
├── docs/                      # Documentation
├── Tests/                     # Unit tests (planned)
└── Examples/                  # Usage examples
```

> Consulte [`docs/reference.md`](docs/reference.md) para o design completo e o catálogo de verificações.

---

## 📚 Documentação

| Documento | Descrição |
|---|---|
| [`Docs/getting-started.md`](Docs/GETTING-STARTED.md) | Instalação, uso, referência de parâmetros e troubleshooting |
| [`Docs/reference.md`](Docs/GETTING-STARTED.md) | Catálogo completo de verificações, arquitetura e limitações |
| [`Docs/security.md`](Docs/SECURITY.md) | Política read-only e dados coletados |

---

## 🔐 Segurança

O toolkit é **100% read-only by design**. Ele **não**:

- ❌ Cria, modifica ou remove objetos do Active Directory
- ❌ Cria, modifica ou remove registros DNS
- ❌ Reinicia serviços
- ❌ Executa correções automáticas
- ❌ Armazena credenciais

> Os comandos sugeridos no relatório são **orientação para o analista**, nunca executados pelo toolkit. Consulte [`Docs/security.md`](Docs/SECURITY.md) para a política completa.

---

## 📜 Licença

**MIT** © Matheus S Santos

> Projeto desenvolvido como **portfólio técnico** e ferramenta de uso profissional em ambientes **Microsoft Windows Server / Active Directory**.
