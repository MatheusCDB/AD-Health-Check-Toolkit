# Security

Política de segurança e dados coletados do AD Health Check Toolkit.

---

## Princípio fundamental

O AD Health Check Toolkit é **100% read-only**. Ele diagnostica, coleta evidências e reporta — **nunca corrige, altera ou remove nada**.

Essa é uma **invariante de projeto**. Qualquer contribuição que quebre essa garantia é rejeitada.

---

## O que o toolkit NUNCA faz

O toolkit **não executa automaticamente**:

- Criação, modificação ou remoção de **objetos do Active Directory**.
- Criação, modificação ou remoção de **registros DNS**.
- Criação, modificação ou remoção de **GPOs**.
- Alteração de **topologia de replicação** (sites, site links, conexões KCC).
- Transferência ou seizure de **papéis FSMO**.
- Reinicialização, parada ou início de **serviços**.
- Sincronização forçada de replicação (`repadmin /syncall`, `Sync-ADObject`).
- Limpeza de **metadados** de DCs.
- Recuperação autoritativa ou não-autoritativa de **SYSVOL**.
- Alterações em **registro** do Windows.
- **Exclusão** de arquivos ou objetos.
- **Execução** de comandos sugeridos no relatório.

Todos os `SuggestedCommands` apresentados no relatório HTML são **orientação para o analista**, nunca executados pelo toolkit.

---

## Verificação de código

A invariante read-only é verificada por um script de grep que roda antes de cada release:

```powershell
Get-ChildItem .\Modules\*.ps1, .\Invoke-ADHealthCheck.ps1, .\UI\*.ps1 | ForEach-Object {
    $hits = Select-String -Path $_.FullName `
        -Pattern '\b(Set-AD[A-Z]|Remove-AD[A-Z]|New-AD[A-Z]|Move-AD[A-Z]|Restart-Service|Stop-Service|Start-Service|Set-Service|Sync-ADObject|Invoke-ADReplication|Remove-ADObject|Add-ADGroupMember|Remove-ADGroupMember|Set-ItemProperty\s+-Path\s+.*AD|Set-ADObject|Set-ADDomain|Set-ADForest)' `
        -AllMatches
    if ($hits) {
        "=== $($_.Name) ==="
        $hits | ForEach-Object { "  Linha $($_.LineNumber): $($_.Line.Trim())" }
    }
}
```
O que o toolkit NÃO coleta
Senhas, hashes, tickets Kerberos.

Conteúdo de políticas (apenas existência e consistência AD ↔ SYSVOL).

Conteúdo de arquivos em SYSVOL ou NETLOGON (apenas nomes quando aplicável).

Mensagens completas de eventos sensíveis — apenas resumos.

Credenciais de qualquer tipo.

Dados pessoais identificáveis além do que aparece em logs de eventos.

## Privilégios necessários
Operação	Privilégio necessário
Discovery, DNS, FSMO, Topologia	Leitura em AD DS
Serviços	Leitura local (e Read em DCs remotos via WinRM/CIM)
Replicação	Leitura em AD DS
SYSVOL	Leitura em shares UNC
Event Logs	Leitura em logs de eventos
Security log	Leitura no log Security (requer elevação + audit policy)
A ferramenta não solicita privilégios elevados por padrão. Verificações que exigiriam isso são emitidas como UNKNOWN com o motivo documentado.
