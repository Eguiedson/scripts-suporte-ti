<#
.SYNOPSIS
  Checagem rápida de saúde da máquina, para o primeiro atendimento de um chamado de lentidão ou travamento.
.DESCRIPTION
  Confere espaço em disco, uso de memória, tempo ligado sem reiniciar, serviços automáticos parados
  e erros recentes no log do sistema. Mostra OK, ATENÇÃO ou PROBLEMA em cada item.
  Só lê informações; não altera nada na máquina.
.EXAMPLE
  .\verificar-saude.ps1
  .\verificar-saude.ps1 -DiasSemReiniciar 3
#>
param(
    [int]$PercentualMinimoDisco = 15,
    [int]$DiasSemReiniciar = 7,
    [int]$HorasDeLog = 24,
    # Devolve os resultados como objetos, para exportar: .\verificar-saude.ps1 -PassThru | Export-Csv saude.csv
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$resultados = New-Object System.Collections.Generic.List[object]
function Registrar($item, $situacao, $detalhe) {
    $resultados.Add([pscustomobject]@{ Item = $item; Situacao = $situacao; Detalhe = $detalhe })
}

# Disco
foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    if (-not $d.Size) { continue }
    $livre = [math]::Round($d.FreeSpace / $d.Size * 100)
    $sit = if ($livre -lt $PercentualMinimoDisco) { 'PROBLEMA' } elseif ($livre -lt $PercentualMinimoDisco * 2) { 'ATENÇÃO' } else { 'OK' }
    Registrar "Disco $($d.DeviceID)" $sit ('{0}% livre ({1:N0} GB)' -f $livre, ($d.FreeSpace / 1GB))
}

# Memória
$so = Get-CimInstance Win32_OperatingSystem
$usoMem = [math]::Round((1 - $so.FreePhysicalMemory / $so.TotalVisibleMemorySize) * 100)
$sit = if ($usoMem -ge 90) { 'PROBLEMA' } elseif ($usoMem -ge 80) { 'ATENÇÃO' } else { 'OK' }
Registrar 'Memória' $sit "$usoMem% em uso"

# Tempo ligado: muita lentidão some com um reinício, e atualizações pendentes só entram depois dele.
$dias = ((Get-Date) - $so.LastBootUpTime).Days
$sit = if ($dias -ge $DiasSemReiniciar) { 'ATENÇÃO' } else { 'OK' }
Registrar 'Tempo ligado' $sit "$dias dia(s) sem reiniciar"

# Serviços automáticos que deveriam estar rodando e não estão.
# Alguns iniciam e param sozinhos por projeto (atualizadores, por exemplo); por isso é ATENÇÃO, não PROBLEMA.
$parados = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
    Where-Object { $_.Name -notmatch '^(gupdate|GoogleUpdater|edgeupdate|AppXSvc|MapsBroker|sppsvc|RemoteRegistry|TrustedInstaller|tiledatamodelsvc|WbioSrvc|clr_optimization)' }
if ($parados) {
    Registrar 'Serviços automáticos' 'ATENÇÃO' ("parados: " + (($parados | Select-Object -First 5 -ExpandProperty DisplayName) -join ', ') + $(if (@($parados).Count -gt 5) { ' e outros' }))
} else {
    Registrar 'Serviços automáticos' 'OK' 'todos rodando'
}

# Erros críticos e erros no log do sistema nas últimas horas.
try {
    $erros = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddHours(-$HorasDeLog) } -ErrorAction Stop
    $qtd = @($erros).Count
    $maisComum = $erros | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 1
    $sit = if ($qtd -ge 20) { 'ATENÇÃO' } else { 'OK' }
    Registrar "Log do sistema ($HorasDeLog h)" $sit "$qtd erro(s); mais frequente: $($maisComum.Name)"
} catch {
    # Get-WinEvent lança erro quando não há nenhum evento no filtro: isso é bom sinal.
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
        Registrar "Log do sistema ($HorasDeLog h)" 'OK' 'nenhum erro'
    } else {
        Registrar "Log do sistema ($HorasDeLog h)" 'ATENÇÃO' "não foi possível ler: $($_.Exception.Message)"
    }
}

$cores = @{ 'OK' = 'Green'; 'ATENÇÃO' = 'Yellow'; 'PROBLEMA' = 'Red' }
Write-Host "`nSaúde de $env:COMPUTERNAME em $(Get-Date -Format 'dd/MM/yyyy HH:mm')`n"
foreach ($r in $resultados) {
    Write-Host ('{0,-10}' -f $r.Situacao) -ForegroundColor $cores[$r.Situacao] -NoNewline
    Write-Host ('{0,-26} {1}' -f $r.Item, $r.Detalhe)
}
if ($PassThru) { $resultados }
