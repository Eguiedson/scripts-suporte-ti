<#
.SYNOPSIS
  Gera um relatório HTML com o inventário da máquina: sistema, hardware, discos, rede e programas instalados.
.EXAMPLE
  .\inventario.ps1
  .\inventario.ps1 -Pasta C:\Inventarios
.NOTES
  Só lê informações; não altera nada na máquina. Funciona no Windows PowerShell 5.1 e no PowerShell 7.
#>
param(
    # Onde salvar o relatório. Padrão: a pasta Documentos do usuário.
    [string]$Pasta = [Environment]::GetFolderPath('MyDocuments')
)
$ErrorActionPreference = 'Stop'

$so    = Get-CimInstance Win32_OperatingSystem
$pc    = Get-CimInstance Win32_ComputerSystem
$bios  = Get-CimInstance Win32_BIOS
$cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
$discos = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
$redes = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True'

# Programas instalados ficam no registro (64 e 32 bits). Win32_Product é evitado de propósito:
# consultar essa classe dispara a verificação de todos os pacotes MSI e é muito lenta.
# HKCU pega o que foi instalado só para o usuário (VS Code, Teams, Zoom e outros).
$chaves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$errosRegistro = $null
$programas = Get-ItemProperty $chaves -ErrorAction SilentlyContinue -ErrorVariable errosRegistro |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    Sort-Object DisplayName -Unique |
    Select-Object DisplayName, DisplayVersion, Publisher

function Esc([object]$t) { [Net.WebUtility]::HtmlEncode([string]$t) }
function Linha($rotulo, $valor) { "<tr><th>$(Esc $rotulo)</th><td>$(Esc $valor)</td></tr>" }

$ligadoHa = (Get-Date) - $so.LastBootUpTime
$geral = @(
    Linha 'Computador' $env:COMPUTERNAME
    Linha 'Usuário' "$env:USERDOMAIN\$env:USERNAME"
    Linha 'Fabricante / modelo' "$($pc.Manufacturer) $($pc.Model)"
    Linha 'Número de série' $bios.SerialNumber
    Linha 'Sistema' "$($so.Caption) ($($so.OSArchitecture)), versão $($so.Version)"
    Linha 'Processador' $cpu.Name.Trim()
    Linha 'Memória RAM' ('{0:N1} GB' -f ($pc.TotalPhysicalMemory / 1GB))
    Linha 'Ligado há' ('{0} dias e {1} h' -f $ligadoHa.Days, $ligadoHa.Hours)
) -join ''

$linhasDisco = foreach ($d in $discos) {
    $livre = if ($d.Size) { $d.FreeSpace / $d.Size * 100 } else { 0 }
    $classe = if ($livre -lt 15) { ' class="alerta"' } else { '' }
    "<tr$classe><td>$($d.DeviceID)</td><td>{0:N0} GB</td><td>{1:N0} GB</td><td>{2:N0}%</td></tr>" -f ($d.Size / 1GB), ($d.FreeSpace / 1GB), $livre
}
$linhasRede = foreach ($r in $redes) {
    "<tr><td>$(Esc $r.Description)</td><td>$(Esc ($r.IPAddress -join ', '))</td><td>$(Esc $r.MACAddress)</td><td>$(Esc ($r.DefaultIPGateway -join ', '))</td></tr>"
}
$linhasProg = foreach ($p in $programas) {
    "<tr><td>$(Esc $p.DisplayName)</td><td>$(Esc $p.DisplayVersion)</td><td>$(Esc $p.Publisher)</td></tr>"
}

$html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Inventário $env:COMPUTERNAME</title>
<style>
body{font:14px/1.5 'Segoe UI',sans-serif;margin:24px;color:#1b2330}
h1{margin:0}p{color:#5a6576}table{border-collapse:collapse;margin:8px 0 24px;min-width:420px}
th,td{border:1px solid #e1e6ed;padding:6px 10px;text-align:left}th{background:#f4f6f9}
tr.alerta td{background:#fde8e8}
</style></head><body>
<h1>Inventário de $env:COMPUTERNAME</h1>
<p>Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
<h2>Geral</h2><table>$geral</table>
<h2>Discos</h2><table><tr><th>Unidade</th><th>Tamanho</th><th>Livre</th><th>% livre</th></tr>$($linhasDisco -join '')</table>
<h2>Rede</h2><table><tr><th>Adaptador</th><th>IP</th><th>MAC</th><th>Gateway</th></tr>$($linhasRede -join '')</table>
<h2>Programas instalados ($(@($programas).Count))</h2>$(if (@($errosRegistro).Count) { "<p>$(@($errosRegistro).Count) registro(s) de programa não puderam ser lidos e ficaram fora da lista.</p>" })<table><tr><th>Nome</th><th>Versão</th><th>Fabricante</th></tr>$($linhasProg -join '')</table>
</body></html>
"@

New-Item -ItemType Directory -Force $Pasta | Out-Null
$arquivo = Join-Path $Pasta ("inventario_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HHmm'))
[IO.File]::WriteAllText($arquivo, $html, [Text.UTF8Encoding]::new($false))
"Relatório salvo em $arquivo"
