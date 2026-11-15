<#
.SYNOPSIS
  Limpa arquivos temporários antigos do usuário e do Windows para liberar espaço.
.DESCRIPTION
  Apaga apenas arquivos com mais de N dias (padrão 7) nas pastas temporárias. Arquivos em uso são pulados.
  Use -WhatIf para só ver o que seria apagado, sem apagar nada.
  A pasta C:\Windows\Temp só é limpa quando o script roda como administrador.
.EXAMPLE
  .\limpar-temporarios.ps1 -WhatIf
  .\limpar-temporarios.ps1 -Dias 14
#>
[CmdletBinding(SupportsShouldProcess)]
param([int]$Dias = 7)

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$pastas = @($env:TEMP)
if ($admin) { $pastas += "$env:windir\Temp" } else { Write-Host 'Sem privilégio de administrador: C:\Windows\Temp fica de fora.' -ForegroundColor Yellow }

$limite = (Get-Date).AddDays(-$Dias)
$liberado = 0; $apagados = 0; $pulados = 0
foreach ($pasta in $pastas) {
    if (-not (Test-Path $pasta)) { continue }
    $arquivos = Get-ChildItem $pasta -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limite }
    foreach ($a in $arquivos) {
        if ($PSCmdlet.ShouldProcess($a.FullName, 'Apagar')) {
            try {
                Remove-Item $a.FullName -Force -ErrorAction Stop
                $liberado += $a.Length; $apagados++
            } catch {
                $pulados++   # em uso por outro programa: fica para a próxima
            }
        } else {
            $liberado += $a.Length; $apagados++   # -WhatIf: conta o que seria apagado
        }
    }
}
$verbo = if ($WhatIfPreference) { 'seriam apagados' } else { 'apagados' }
'{0} arquivo(s) {1}, {2:N1} MB liberados. {3} em uso e pulados.' -f $apagados, $verbo, ($liberado / 1MB), $pulados
