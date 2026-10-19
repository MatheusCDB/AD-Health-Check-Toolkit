  # Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Automated Pester unit tests for the parsers and the scoring engine.
- Multi-DC DFSR backlog analysis for SYSVOL.
- Optional client-side GPO processing diagnostics.
- HTML report: downloadable PDF export.

---

## [0.1.0] - 2026-10-15

First public release.

### Added
- **Core**
  - Modular architecture with `Core/`, `Modules/`, `Config/`, `UI/` and `Reports/`.
  - Structured `CheckResult` model with stable fields (CheckId, Category, Status, Severity, Evidence, ...).
  - Versioned severity rules in `Config/SeverityRules.psd1`.
  - Versioned check catalog in `Config/CheckCatalog.psd1`.
  - Centralized defaults (timeouts, ports, thresholds) in `Config/Defaults.psd1`.

- **Diagnostic categories** (~93 checks)
  - `Connectivity` — ICMP, TCP ports, DNS resolution, admin access.
  - `Services` — essential Windows/AD DS services per DC.
  - `DNS` — zone existence, AD-integration, SOA, SRV records, dcdiag-based evidence.
  - `Replication` — `Get-ADReplication*` cmdlets plus `repadmin /replsummary` parser.
  - `FSMO` — domain and forest role placement checks.
  - `SYSVOL` — shares, UNC paths, DFSR state.
  - `TimeSynchronization` — `w32tm /query/*` with pt-BR and en-US parsers.
  - `DCDiag` — 13 individual `dcdiag /test:X` runs (opt-in).
  - `EventLogs` — Directory Service, DNS, DFSR and System logs with ID whitelisting.
  - `Topology` — sites, subnets, site links, KCC connections, ISTG (opt-in).
  - `GroupPolicy` — AD ↔ SYSVOL consistency, orphan detection (opt-in).

- **Localized parsers** (pt-BR and en-US)
  - `repadmin /replsummary`
  - `dcdiag /test:dns`
  - `dcdiag /test:X` (13 tests)
  - `w32tm /query /status`, `/configuration`, `/peers`, `/stripchart`
  - CP-850 aware decoding for OEM console output.

- **Interactive TUI**
  - Banner with automatic Unicode / ASCII fallback.
  - Main menu with audit, selection, single-DC, prerequisites and exit.
  - Checkbox-style selection of audit categories.
  - Real-time progress without fabricated percentages.
  - Executive summary with real numbers and severity-sorted attention list.
  - Export menu (HTML / JSON / CSV).

- **Report generation**
  - Self-contained HTML report (no CDN, no internet dependency).
  - Filters by DC, category, status and severity.
  - Expandable evidence blocks and suggested commands.
  - JSON export with full structured data.
  - CSV export with flattened rows.

- **Operational safety**
  - 100% read-only diagnostics. No AD object is created, modified or removed.
  - No DNS record is created, modified or removed.
  - No service is restarted.
  - No credential is ever stored.
  - No automated remediation is attempted.

### Known limitations
- IPv6 / AAAA checks are intentionally disabled.
- Security log collection requires explicit `-IncludeSecurityLog` and reads a curated subset of event IDs.
- Multi-DC DFSR backlog analysis is not yet implemented.
- `dcdiag /test:SystemLog` may return inconclusive in single-DC domains.

[Unreleased]: https://github.com/<user>/ad-health-check-toolkit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<user>/ad-health-check-toolkit/releases/tag/v0.1.0
