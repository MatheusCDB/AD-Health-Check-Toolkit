# AD Health Check Toolkit

> Diagnóstico, auditoria e avaliação preventiva da saúde do Active Directory Domain Services (AD DS) — 100% read-only.

![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%20Server%202016%2B-lightgrey)
![Active Directory](https://img.shields.io/badge/Active%20Directory-DS-success)
![License](https://img.shields.io/badge/License-MIT-green)

**Stack:** PowerShell 7+ · Active Directory DS · DNS Server · DFSR · Group Policy · HTML/CSS/JS

Uma ferramenta em PowerShell 7 para administradores de sistemas, analistas de infraestrutura e profissionais de suporte N2/N3 que precisam avaliar a saúde de um domínio Active Directory sem executar nenhuma operação destrutiva.
```
█████╗ ██████╗ ██╗ ██╗ ██████╗
██╔══██╗██╔══██╗██║ ██║██╔════╝
███████║██║ ██║███████║██║
██╔══██║██║ ██║██╔══██║██║
██║ ██║██████╔╝██║ ██║╚██████╗
╚═╝ ╚═╝╚═════╝ ╚═╝ ╚═╝ ╚═════╝
```
AD HEALTH CHECK TOOLKIT
Active Directory health assessment
PowerShell | Active Directory | DNS | Replication

---

## Visão geral

O toolkit avalia de forma estruturada e independente:

- Controladores de domínio (descoberta, site, sistema operacional, papel).
- Serviços essenciais do Windows Server e do AD DS.
- Conectividade (ICMP, portas TCP, resolução DNS, acesso administrativo).
- Replicação do Active Directory (`Get-ADReplication*` + parser de `repadmin`).
- DNS integrado ao AD (zonas, SOA, SRV, registros órfãos, dcdiag-based).
- SYSVOL e NETLOGON (compartilhamentos, caminhos UNC, DFSR).
- Papéis FSMO (domínio e floresta).
- Topologia e sites (subnets, site links, KCC, ISTG).
- Sincronização de horário (`w32tm`).
- Eventos relevantes do Windows (Directory Service, DNS, DFSR, System).
- Políticas de Grupo (consistência AD ↔ SYSVOL).

Cada verificação retorna um objeto estruturado com **evidência**, **impacto potencial**, **causas possíveis**, **investigação recomendada** e **comandos sugeridos** — mas **nenhum comando é executado automaticamente**.

---

## Recursos

- **Interface interativa (TUI)** com banner, menu, seleção de auditorias, progresso em tempo real, resumo executivo e exportação.
- **Modo clássico (não-interativo)** para automação e CI.
- **Relatório HTML self-contained** — abre com duplo clique, sem internet, com filtros e detalhes expansíveis.
- **Exportação JSON e CSV** opcional.
- **Parsers localizados** em pt-BR e en-US para `repadmin`, `dcdiag` e `w32tm`.
- **Fallback ASCII** para terminais sem suporte a Unicode.
- **Zero dependências externas** — apenas PowerShell 7, RSAT e binários nativos do Windows.

---

## Requisitos

- Windows Server 2016 / 2019 / 2022 / 2025 (executado de dentro de um DC).
- **PowerShell 7 ou superior** (o script detecta e oferece a instalação automática).
- RSAT-AD-PowerShell, RSAT-AD-Tools, RSAT-DNS-Server (recomendado).
- Privilégios de leitura em AD DS, DNS e logs de eventos.

Veja [docs/INSTALLATION.md](docs/INSTALLATION.md) para instruções detalhadas.

---

## Início rápido

```powershell
# Clone o repositório
git clone https://github.com/<user>/ad-health-check-toolkit.git
cd ad-health-check-toolkit

# Modo interativo (TUI)
.\Invoke-ADHealthCheck.ps1

# Modo clássico (não-interativo)
.\Invoke-ADHealthCheck.ps1 -Domain "empresa.local" -Checks DNS,Replication -OutputPath "C:\Reports"

# Auditoria profunda (inclui DCDiag, Topology, EventLogs, GPO)
.\Invoke-ADHealthCheck.ps1 -IncludeDcdiag -IncludeTopology -IncludeEventLogs -IncludeGroupPolicy

Modo interativo
Ao executar sem parâmetros, o toolkit abre a interface interativa:

text
+-----------------------------------------------------------+
|                  AD HEALTH CHECK TOOLKIT                  |
+-----------------------------------------------------------+
|  [1] Auditoria completa do Active Directory               |
|  [2] Selecionar auditorias                                |
|  [3] Auditoria profunda (inclui DCDiag, Topology, ...)    |
|  [5] Verificar dependencias e pre-requisitos              |
|  [0] Sair                                                 |
+-----------------------------------------------------------+

Consulte docs/USAGE.md para a lista completa de parâmetros.
```

---

##Estrutura do projeto
```
ad-health-check-toolkit/
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
Consulte docs/ARCHITECTURE.md para o design completo.

---

##Documentação

Documento	Descrição
docs/INSTALLATION.md	Como instalar e preparar o ambiente
docs/USAGE.md	Todos os parâmetros, modos e exemplos
docs/CHECKS.md	Catálogo completo das verificações
docs/ARCHITECTURE.md	Design modular e fluxo de execução
docs/SECURITY.md	Política read-only e dados coletados
docs/TROUBLESHOOTING.md	Erros comuns e como agir
docs/LIMITATIONS.md	Limitações conhecidas

---

##Segurança

O toolkit é 100% read-only por design. Ele não:
- Cria, modifica ou remove objetos do Active Directory.
- Cria, modifica ou remove registros DNS.
- Reinicia serviços.
- Executa correções automáticas.
- Armazena credenciais.

Os comandos sugeridos no relatório são orientação para o analista, nunca executados pelo toolkit.
Consulte docs/SECURITY.md para a política completa.

---

##Licença
MIT © Matheus S Santos
Projeto desenvolvido como portfólio técnico e ferramenta de uso profissional em ambientes Microsoft Windows Server / Active Directory.

