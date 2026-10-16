Set-StrictMode -Version Latest

#region --- Embedded HTML template ---
#
# The HTML template is embedded here on purpose.
# Keeping it as a separate file (Templates/Report.template.html) caused
# repeated copy/paste mistakes where the .ps1 and the .html got swapped.
# The trade-off (less elegant source vs. fewer operational errors) was
# decided in favor of reliability.
#
# The template uses {{TOKEN}} placeholders replaced at generation time.
# It must remain a single here-string so Set-Content writes exactly one file.
#
function Get-ADHCHtmlTemplate {
    [CmdletBinding()]
    param()
    @'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}}</title>
<style>
    :root {
        --bg: #f5f6f8;
        --card: #ffffff;
        --border: #e0e3e8;
        --text: #1f2430;
        --muted: #6b7280;
        --pass: #2e7d32;
        --info: #1565c0;
        --warn: #f9a825;
        --fail: #c62828;
        --unknown: #6b7280;
    }
    * { box-sizing: border-box; }
    body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        background: var(--bg);
        color: var(--text);
        line-height: 1.45;
    }
    .wrap { max-width: 1200px; margin: 0 auto; padding: 24px 20px 60px; }
    header {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 10px;
        padding: 22px 24px;
        margin-bottom: 20px;
    }
    header h1 { margin: 0 0 6px; font-size: 22px; }
    header .meta { color: var(--muted); font-size: 14px; }
    header .meta span { margin-right: 18px; white-space: nowrap; }
    .summary {
        display: grid;
        grid-template-columns: 220px 1fr;
        gap: 20px;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 10px;
        padding: 22px 24px;
        margin-bottom: 20px;
    }
    .score-box { text-align: center; }
    .score-value {
        font-size: 56px;
        font-weight: 700;
        line-height: 1;
    }
    .score-band {
        font-size: 14px;
        letter-spacing: 1px;
        text-transform: uppercase;
        margin-top: 6px;
    }
    .score-caption { color: var(--muted); font-size: 12px; margin-top: 8px; }
    .counters {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
        gap: 12px;
    }
    .counter {
        background: var(--bg);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 12px 14px;
        text-align: center;
    }
    .counter .value { font-size: 24px; font-weight: 600; }
    .counter .label { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
    .counter.pass .value { color: var(--pass); }
    .counter.info .value { color: var(--info); }
    .counter.warn .value { color: var(--warn); }
    .counter.fail .value { color: var(--fail); }
    .counter.unknown .value { color: var(--unknown); }

    .controls {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 10px;
        padding: 14px 18px;
        margin-bottom: 20px;
        display: flex;
        flex-wrap: wrap;
        gap: 10px 14px;
        align-items: center;
    }
    .controls label { font-size: 13px; color: var(--muted); }
    .controls select, .controls input[type="search"] {
        font: inherit;
        padding: 6px 8px;
        border: 1px solid var(--border);
        border-radius: 6px;
        background: #fff;
        color: var(--text);
        min-width: 160px;
    }

    .category {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 10px;
        margin-bottom: 14px;
        overflow: hidden;
    }
    .category > summary {
        cursor: pointer;
        padding: 14px 18px;
        font-weight: 600;
        font-size: 15px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        list-style: none;
    }
    .category > summary::-webkit-details-marker { display: none; }
    .category > summary::before {
        content: "\25B8";
        display: inline-block;
        margin-right: 8px;
        transition: transform .12s ease;
        color: var(--muted);
    }
    .category[open] > summary::before { transform: rotate(90deg); }
    .category .summary-stats { color: var(--muted); font-weight: 400; font-size: 13px; }
    .category .content { padding: 0 18px 18px; }

    .pill {
        display: inline-block;
        padding: 2px 8px;
        border-radius: 999px;
        font-size: 11px;
        font-weight: 600;
        letter-spacing: .4px;
        text-transform: uppercase;
        color: #fff;
    }
    .pill.PASS    { background: var(--pass); }
    .pill.INFO    { background: var(--info); }
    .pill.WARNING { background: var(--warn); }
    .pill.FAIL    { background: var(--fail); }
    .pill.UNKNOWN { background: var(--unknown); }

    .sev {
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: .4px;
        color: var(--muted);
    }

    details.check-detail {
        background: #fafbfc;
        border: 1px solid var(--border);
        border-radius: 6px;
        margin: 6px 0;
        padding: 0 12px;
    }
    details.check-detail > summary {
        cursor: pointer;
        padding: 8px 0;
        font-weight: 500;
        list-style: none;
    }
    details.check-detail > summary::-webkit-details-marker { display: none; }
    details.check-detail > summary::before {
        content: "\25B8";
        display: inline-block;
        margin-right: 6px;
        color: var(--muted);
        transition: transform .12s ease;
    }
    details.check-detail[open] > summary::before { transform: rotate(90deg); }
    details.check-detail .body { padding: 0 0 12px 20px; font-size: 13px; }
    details.check-detail .body dl { margin: 0; }
    details.check-detail .body dt {
        font-weight: 600;
        margin-top: 8px;
        color: var(--muted);
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: .4px;
    }
    details.check-detail .body dd { margin: 2px 0 0; }
    pre.cmd {
        background: #1f2430;
        color: #e6e8ec;
        padding: 8px 10px;
        border-radius: 6px;
        overflow-x: auto;
        font-size: 12px;
        margin: 4px 0;
        white-space: pre-wrap;
        word-break: break-word;
    }

    footer {
        margin-top: 28px;
        padding: 16px 20px;
        text-align: center;
        color: var(--muted);
        font-size: 13px;
    }
    footer .author { color: var(--text); font-weight: 600; }

    .no-results { text-align: center; color: var(--muted); padding: 30px 0; }
</style>
</head>
<body>
<div class="wrap">

<header>
    <h1>{{TOOL_NAME}} <small style="font-weight:400;color:#6b7280;font-size:14px;">v{{TOOL_VERSION}}</small></h1>
    <div class="meta">
        <span><strong>Dom&iacute;nio:</strong> {{DOMAIN}}</span>
        <span><strong>DC avaliado:</strong> {{DC_EVALUATED}}</span>
        <span><strong>Host:</strong> {{HOST}}</span>
        <span><strong>Usu&aacute;rio:</strong> {{USER}}</span>
        <span><strong>In&iacute;cio:</strong> {{STARTED_AT}}</span>
        <span><strong>Dura&ccedil;&atilde;o:</strong> {{DURATION}}</span>
        <span><strong>PS:</strong> {{PS_VERSION}}</span>
    </div>
    <p style="margin:14px 0 0;color:#4b5563;font-size:14px;line-height:1.5;">
        Este relat&oacute;rio resume a avalia&ccedil;&atilde;o de sa&uacute;de do Active Directory Domain Services (AD DS),
        cobrindo servi&ccedil;os essenciais, replica&ccedil;&atilde;o, DNS, SYSVOL, FSMO, sincroniza&ccedil;&atilde;o de hor&aacute;rio
        e demais depend&ecirc;ncias do dom&iacute;nio. Apresenta uma pontua&ccedil;&atilde;o geral de sa&uacute;de,
        classifica&ccedil;&otilde;es por severidade e evid&ecirc;ncias t&eacute;cnicas para apoio &agrave; investiga&ccedil;&atilde;o.
    </p>
</header>

<section class="summary">
    <div class="score-box">
        <div class="score-value" style="color: {{SCORE_COLOR}}">{{SCORE}}</div>
        <div class="score-band" style="color: {{SCORE_COLOR}}">{{SCORE_BAND}}</div>
        <div class="score-caption">Base {{BASE_SCORE}} &middot; dedu&ccedil;&atilde;o {{TOTAL_DEDUCTION}}</div>
    </div>
    <div class="counters">
        <div class="counter"><div class="value">{{COUNT_TOTAL}}</div><div class="label">Total</div></div>
        <div class="counter pass"><div class="value">{{COUNT_PASS}}</div><div class="label">PASS</div></div>
        <div class="counter info"><div class="value">{{COUNT_INFO}}</div><div class="label">INFO</div></div>
        <div class="counter warn"><div class="value">{{COUNT_WARN}}</div><div class="label">WARN</div></div>
        <div class="counter fail"><div class="value">{{COUNT_FAIL}}</div><div class="label">FAIL</div></div>
        <div class="counter unknown"><div class="value">{{COUNT_UNKNOWN}}</div><div class="label">UNKNOWN</div></div>
    </div>
</section>

<section class="controls">
    <label>Buscar:
        <input type="search" id="f-text" placeholder="CheckId, t&iacute;tulo, categoria...">
    </label>
    <label>DC:
        <select id="f-dc">
            <option value="">Todos</option>
        </select>
    </label>
    <label>Categoria:
        <select id="f-category">
            <option value="">Todas</option>
        </select>
    </label>
    <label>Status:
        <select id="f-status">
            <option value="">Todos</option>
        </select>
    </label>
    <label>Severidade:
        <select id="f-severity">
            <option value="">Todas</option>
        </select>
    </label>
    <span id="f-count" style="color:#6b7280;font-size:13px;margin-left:auto;"></span>
</section>

<div id="categories"></div>

<div id="no-results" class="no-results" style="display:none;">Nenhum check corresponde aos filtros.</div>

<footer>
    <div>Relat&oacute;rio gerado em {{GENERATED_AT}}</div>
    <div class="author" style="margin-top:6px;">Desenvolvido por Matheus S Santos</div>
</footer>

</div>

<script>
(function () {
    "use strict";

    // Embedded data injected by the ReportGenerator.
    var DATA = {{DATA_JSON}};

    var categoriesRoot = document.getElementById('categories');
    var noResults      = document.getElementById('no-results');
    var fText          = document.getElementById('f-text');
    var fDc            = document.getElementById('f-dc');
    var fCat           = document.getElementById('f-category');
    var fStatus        = document.getElementById('f-status');
    var fSev           = document.getElementById('f-severity');
    var fCount         = document.getElementById('f-count');

    function escapeHtml(s) {
        if (s === null || s === undefined) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function fmtList(arr) {
        if (!arr || !arr.length) return '';
        var out = '<ul style="margin:4px 0 0;padding-left:18px;">';
        for (var i = 0; i < arr.length; i++) out += '<li>' + escapeHtml(arr[i]) + '</li>';
        out += '</ul>';
        return out;
    }

    function fmtCommands(arr) {
        if (!arr || !arr.length) return '';
        var out = '';
        for (var i = 0; i < arr.length; i++) {
            out += '<pre class="cmd">' + escapeHtml(arr[i]) + '</pre>';
        }
        return out;
    }

    function fmtEvidence(ev) {
        if (!ev) return '';
        return '<pre class="cmd">' + escapeHtml(JSON.stringify(ev, null, 2)) + '</pre>';
    }

    function statusClass(s) {
        return 'pill ' + String(s || 'UNKNOWN').toUpperCase();
    }

    // Populate filter options from data.
    var dcs = {}, cats = {}, statuses = {}, sevs = {};
    DATA.forEach(function (r) {
        if (r.DomainController) dcs[r.DomainController] = true;
        if (r.Category)         cats[r.Category] = true;
        if (r.Status)           statuses[r.Status] = true;
        if (r.Severity)         sevs[r.Severity] = true;
    });
    Object.keys(dcs).sort().forEach(function (v) {
        var o = document.createElement('option'); o.value = v; o.textContent = v; fDc.appendChild(o);
    });
    Object.keys(cats).sort().forEach(function (v) {
        var o = document.createElement('option'); o.value = v; o.textContent = v; fCat.appendChild(o);
    });
    Object.keys(statuses).sort().forEach(function (v) {
        var o = document.createElement('option'); o.value = v; o.textContent = v; fStatus.appendChild(o);
    });
    Object.keys(sevs).sort().forEach(function (v) {
        var o = document.createElement('option'); o.value = v; o.textContent = v; fSev.appendChild(o);
    });

    function buildRow(r) {
        var detailId = 'detail-' + (r.CheckId + '-' + (r.DomainController || 'domain')).replace(/[^A-Za-z0-9\-_.]/g, '_');
        var html = '';
        html += '<details class="check-detail" id="' + detailId + '">';
        html += '<summary>';
        html += '<span class="' + statusClass(r.Status) + '">' + escapeHtml(r.Status) + '</span> ';
        html += '<span style="margin-left:6px;">' + escapeHtml(r.CheckId) + '</span> ';
        html += '<span style="color:#6b7280;font-weight:400;margin-left:6px;">' + escapeHtml(r.Title || '') + '</span>';
        html += '<span style="float:right;"><span class="sev">' + escapeHtml(r.Severity || '') + '</span></span>';
        html += '</summary>';
        html += '<div class="body">';
        html += '<dl>';
        if (r.DomainController) html += '<dt>Controlador</dt><dd>' + escapeHtml(r.DomainController) + '</dd>';
        if (r.Description)      html += '<dt>Descri&ccedil;&atilde;o</dt><dd>' + escapeHtml(r.Description) + '</dd>';
        if (r.PotentialImpact)  html += '<dt>Impacto potencial</dt><dd>' + escapeHtml(r.PotentialImpact) + '</dd>';
        if (r.PossibleCauses && r.PossibleCauses.length)                     html += '<dt>Causas poss&iacute;veis</dt><dd>' + fmtList(r.PossibleCauses) + '</dd>';
        if (r.RecommendedInvestigation && r.RecommendedInvestigation.length) html += '<dt>Investiga&ccedil;&atilde;o recomendada</dt><dd>' + fmtList(r.RecommendedInvestigation) + '</dd>';
        if (r.SuggestedCommands && r.SuggestedCommands.length)               html += '<dt>Comandos sugeridos</dt><dd>' + fmtCommands(r.SuggestedCommands) + '</dd>';
        if (r.Evidence && Object.keys(r.Evidence).length)                    html += '<dt>Evid&ecirc;ncia</dt><dd>' + fmtEvidence(r.Evidence) + '</dd>';
        if (r.DetectedAt) html += '<dt>Detectado em</dt><dd>' + escapeHtml(r.DetectedAt) + '</dd>';
        if (r.ToolUsed)   html += '<dt>Ferramenta</dt><dd>' + escapeHtml(r.ToolUsed) + '</dd>';
        html += '</dl>';
        html += '</div>';
        html += '</details>';
        return html;
    }

    function render() {
        var text = (fText.value || '').toLowerCase();
        var dc   = fDc.value;
        var cat  = fCat.value;
        var st   = fStatus.value;
        var sv   = fSev.value;

        var filtered = DATA.filter(function (r) {
            if (dc && r.DomainController !== dc) return false;
            if (cat && r.Category !== cat) return false;
            if (st && r.Status !== st) return false;
            if (sv && r.Severity !== sv) return false;
            if (text) {
                var hay = ((r.CheckId||'') + ' ' + (r.Title||'') + ' ' + (r.Category||'') + ' ' + (r.DomainController||'')).toLowerCase();
                if (hay.indexOf(text) < 0) return false;
            }
            return true;
        });

        fCount.textContent = filtered.length + ' de ' + DATA.length + ' checks';

        var byCat = {};
        filtered.forEach(function (r) {
            var k = r.Category || 'Uncategorized';
            if (!byCat[k]) byCat[k] = [];
            byCat[k].push(r);
        });

        var html = '';
        var catNames = Object.keys(byCat).sort();
        catNames.forEach(function (cname) {
            var items = byCat[cname];
            var counts = { PASS:0, INFO:0, WARNING:0, FAIL:0, UNKNOWN:0 };
            items.forEach(function (r) { if (counts[r.Status] !== undefined) counts[r.Status]++; });
            var statsText = [];
            ['PASS','INFO','WARNING','FAIL','UNKNOWN'].forEach(function (k) {
                if (counts[k]) statsText.push(k + ': ' + counts[k]);
            });

            html += '<details class="category" open>';
            html += '<summary><span>' + escapeHtml(cname) + '</span>';
            html += '<span class="summary-stats">' + escapeHtml(statsText.join(' \u00b7 ')) + '</span></summary>';
            html += '<div class="content">';
            items.forEach(function (r) { html += buildRow(r); });
            html += '</div></details>';
        });

        categoriesRoot.innerHTML = html;
        noResults.style.display = filtered.length ? 'none' : 'block';
    }

    [fText, fDc, fCat, fStatus, fSev].forEach(function (el) {
        el.addEventListener('input', render);
        el.addEventListener('change', render);
    });

    render();
})();
</script>
</body>
</html>
'@
}
#endregion

#region --- Helpers ---

function ConvertTo-ADHCCsvRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $rows = foreach ($r in @($Results)) {
        if ($null -eq $r) { continue }
        $durMs = 0
        if ($r.Duration) { $durMs = [int]$r.Duration.TotalMilliseconds }
        [PSCustomObject]@{
            CheckId                  = $r.CheckId
            Category                 = $r.Category
            Domain                   = $r.Domain
            DomainController         = $r.DomainController
            ComputerName             = $r.ComputerName
            Status                   = $r.Status
            Severity                 = $r.Severity
            Title                    = $r.Title
            Description              = $r.Description
            PotentialImpact          = $r.PotentialImpact
            PossibleCauses           = ($r.PossibleCauses -join ' | ')
            RecommendedInvestigation = ($r.RecommendedInvestigation -join ' | ')
            SuggestedCommands        = ($r.SuggestedCommands -join ' | ')
            ErrorCode                = $r.ErrorCode
            IsInconclusive           = $r.IsInconclusive
            WasSkipped               = $r.WasSkipped
            SkipReason               = $r.SkipReason
            ToolUsed                 = $r.ToolUsed
            DetectedAt               = $r.DetectedAt
            DurationMs               = $durMs
            ModuleVersion            = $r.ModuleVersion
            EvidenceJson             = ($r.Evidence | ConvertTo-Json -Depth 8 -Compress)
        }
    }
    ,@($rows)
}

function ConvertTo-ADHCJsonData {
    <#
    .SYNOPSIS
        Serializes results to a JSON array (or '[]' if empty) with defensive
        escaping so the payload is safe to embed inside a <script> block.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $arr = @($Results)
    if ($arr.Count -eq 0) { return '[]' }

    $json = $arr | ConvertTo-Json -Depth 12
    if ($null -eq $json) { return '[]' }
    # ConvertTo-Json on a 1-element array unwraps it; wrap to keep an array literal.
    $json = [string]$json
    if (-not $json.TrimStart().StartsWith('[')) { $json = "[$json]" }

    # Prevent "</script>" inside strings from terminating the script block early.
    $json = $json.Replace('</', '<\/')
    return $json
}

#endregion

#region --- Main entry point ---

function New-ADHCReport {
    <#
    .SYNOPSIS
        Generates HTML, JSON and CSV reports from a consolidated result.
    .OUTPUTS
        Object with paths to the generated files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Consolidated,
        [Parameter(Mandatory)][psobject]$Score,
        [Parameter(Mandatory)][string]$OutputPath,
        [string[]]$Formats = @('HTML','JSON','CSV')
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $defaults = Get-ADHCDefaults
    $rep      = $defaults.Reporting
    $ts       = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $baseName = "ADHC-Results-$ts"
    $htmlName = "ADHC-Report-$ts.html"
    $jsonName = "$baseName.json"
    $csvName  = "$baseName.csv"

    $results = @($Consolidated.Results)

    # -------- Counters --------
    $counts = @{ PASS=0; INFO=0; WARNING=0; FAIL=0; UNKNOWN=0 }
    foreach ($r in $results) {
        if ($r -and $counts.ContainsKey($r.Status)) { $counts[$r.Status]++ }
    }
    $total = $results.Count

    # -------- CSV --------
    $csvPath = $null
    if ($Formats -contains 'CSV') {
        $csvPath = Join-Path $OutputPath $csvName
        $rows = ConvertTo-ADHCCsvRows -Results $results
        if ($rows.Count -gt 0) {
            $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        } else {
            @([PSCustomObject]@{
                CheckId=''; Category=''; Domain=''; DomainController=''; ComputerName=''
                Status=''; Severity=''; Title=''; Description=''; PotentialImpact=''
                PossibleCauses=''; RecommendedInvestigation=''; SuggestedCommands=''
                ErrorCode=''; IsInconclusive=''; WasSkipped=''; SkipReason=''; ToolUsed=''
                DetectedAt=''; DurationMs=''; ModuleVersion=''; EvidenceJson=''
            }) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        }
    }

    # -------- JSON --------
    $jsonPath = $null
    if ($Formats -contains 'JSON') {
        $jsonPath = Join-Path $OutputPath $jsonName
        $jsonObject = [PSCustomObject]@{
            Metadata       = $Consolidated.Metadata
            Discovery      = [PSCustomObject]@{
                Domain            = $Consolidated.Discovery.Domain
                DomainControllers = $Consolidated.Discovery.DomainControllers
                FSMO              = $Consolidated.Discovery.FSMO
                Forest            = $Consolidated.Discovery.Forest
                Sites             = $Consolidated.Discovery.Sites
            }
            Score          = $Score
            Summary        = $counts
            TotalChecks    = $total
            Results        = $results
        }
        $jsonObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }

    # -------- HTML --------
    $htmlPath = $null
    if ($Formats -contains 'HTML') {
        $htmlPath = Join-Path $OutputPath $htmlName

        $template = Get-ADHCHtmlTemplate
        $meta     = $Consolidated.Metadata

        $started  = ''
        if ($meta.StartedAt)  { $started  = ([datetime]$meta.StartedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')  }
        $durText  = ''
        if ($meta.StartedAt -and $meta.FinishedAt) {
            $d = [datetime]$meta.FinishedAt - [datetime]$meta.StartedAt
            $durText = ('{0:N1}s' -f $d.TotalSeconds)
        }

        $dcList = @($results | Where-Object { $_.DomainController } |
                    Select-Object -ExpandProperty DomainController -Unique)
        if ($dcList.Count -eq 0) { $dcEvaluated = 'Domain-wide' } else { $dcEvaluated = ($dcList -join ', ') }

        $dataJson = ConvertTo-ADHCJsonData -Results $results

        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

        $replacements = [ordered]@{
            '{{TITLE}}'           = & $enc "$($rep.ToolName) - $($Consolidated.Discovery.Domain)"
            '{{TOOL_NAME}}'       = & $enc $rep.ToolName
            '{{TOOL_VERSION}}'    = & $enc $rep.Version
            '{{DOMAIN}}'          = & $enc $Consolidated.Discovery.Domain
            '{{DC_EVALUATED}}'    = & $enc $dcEvaluated
            '{{HOST}}'            = & $enc $meta.Host
            '{{USER}}'            = & $enc $meta.User
            '{{STARTED_AT}}'      = & $enc $started
            '{{DURATION}}'        = & $enc $durText
            '{{PS_VERSION}}'      = & $enc $meta.PSVersion
            '{{SCORE}}'           = & $enc ([string]$Score.Score)
            '{{SCORE_BAND}}'      = & $enc $Score.BandLabel
            '{{SCORE_COLOR}}'     = & $enc $Score.BandColor
            '{{BASE_SCORE}}'      = & $enc ([string]$Score.BaseScore)
            '{{TOTAL_DEDUCTION}}' = & $enc ([string]$Score.TotalDeduction)
            '{{COUNT_TOTAL}}'     = & $enc ([string]$total)
            '{{COUNT_PASS}}'      = & $enc ([string]$counts.PASS)
            '{{COUNT_INFO}}'      = & $enc ([string]$counts.INFO)
            '{{COUNT_WARN}}'      = & $enc ([string]$counts.WARNING)
            '{{COUNT_FAIL}}'      = & $enc ([string]$counts.FAIL)
            '{{COUNT_UNKNOWN}}'   = & $enc ([string]$counts.UNKNOWN)
            '{{GENERATED_AT}}'    = & $enc ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
            '{{DATA_JSON}}'       = $dataJson   # Already escaped and JSON-safe.
        }

        # Use literal replacement (String.Replace), never -replace.
        foreach ($k in $replacements.Keys) {
            $template = $template.Replace($k, [string]$replacements[$k])
        }

        # Write as UTF-8 without BOM so the <meta charset="utf-8"> is sufficient.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($htmlPath, $template, $utf8NoBom)
    }

    [PSCustomObject]@{
        PSTypeName = 'ADHC.ReportPaths'
        Html       = $htmlPath
        Json       = $jsonPath
        Csv        = $csvPath
        OutputPath = $OutputPath
    }
}

#endregion