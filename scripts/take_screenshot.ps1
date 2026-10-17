param(
    [string]$Path = ""
)

$base = "c:/Custom/MyGames/mjddp/screenshots"
$req  = "$base/.request"
$done = "$base/.done"

New-Item -ItemType Directory -Force -Path $base | Out-Null
Remove-Item $done -ErrorAction SilentlyContinue

# 写入自定义保存路径（空则用游戏内默认时间戳路径）
Set-Content -Path $req -Value $Path -NoNewline

$timeout = 15
$elapsed = 0
while (-not (Test-Path $done) -and $elapsed -lt $timeout) {
    Start-Sleep -Milliseconds 200
    $elapsed += 0.2
}

if (Test-Path $done) {
    Get-Content $done
} else {
    "TIMEOUT: screenshot not captured (is the game running?)"
}
