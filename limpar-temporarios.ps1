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
$liberado = 0; $apagados = 0; $emUso = 0; $falhas = 0; $recusados = 0; $semAcesso = 0
foreach ($pasta in $pastas) {
    if (-not (Test-Path -LiteralPath $pasta)) { continue }
    # Subpastas sem permissão não interrompem a varredura, mas entram na contagem do resumo.
    $errosLeitura = $null
    $arquivos = Get-ChildItem -LiteralPath $pasta -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable errosLeitura |
        Where-Object { $_.LastWriteTime -lt $limite }
    $semAcesso += @($errosLeitura).Count
    foreach ($a in $arquivos) {
        if ($PSCmdlet.ShouldProcess($a.FullName, 'Apagar')) {
            try {
                # -LiteralPath: com -Path, colchetes no nome ("setup[1].tmp") viram curinga.
                Remove-Item -LiteralPath $a.FullName -Force -ErrorAction Stop
                $liberado += $a.Length; $apagados++
            } catch [System.IO.IOException] {
                $emUso++   # aberto por outro programa: fica para a próxima
            } catch {
                $falhas++
                Write-Warning "$($a.FullName): $($_.Exception.Message)"
            }
        } elseif ($WhatIfPreference) {
            $liberado += $a.Length; $apagados++   # -WhatIf: conta o que seria apagado
        } else {
            $recusados++   # -Confirm respondido com "Não"
        }
    }
}
$verbo = if ($WhatIfPreference) { 'seriam apagados' } else { 'apagados' }
'{0} arquivo(s) {1}, {2:N1} MB liberados.' -f $apagados, $verbo, ($liberado / 1MB)
if ($emUso) { "$emUso em uso e pulados." }
if ($recusados) { "$recusados não confirmados." }
if ($falhas) { "$falhas não apagados por erro (veja os avisos acima)." }
if ($semAcesso) { "$semAcesso pasta(s) ou arquivo(s) sem permissão de leitura, fora da contagem." }
