# sync.ps1 - runs sync.sh from PowerShell.
#
# All the logic lives in sync.sh; this file only locates Git Bash and hands the
# work over, so there is no second implementation to keep in step.
#
#   .\sync.ps1                    Push only
#   .\sync.ps1 --check            Push + dry run
#   .\sync.ps1 --run              Push + apply site.yml
#   .\sync.ps1 --run --tags gpu   Extra arguments are passed to ansible-playbook
#   .\sync.ps1 --watch --check    Push + dry run automatically on every change
#   .\sync.ps1 --bootstrap        First-time setup
#
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $MyInvocation.MyCommand.Definition

$candidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)

$bash = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { $bash = $c; break }
}
if (-not $bash) {
    $found = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($found) { $bash = $found.Source }
}
if (-not $bash) {
    throw "Git Bash (bash.exe) not found. Install Git for Windows, or run sync.sh directly inside Git Bash."
}

# C:\Users\x\repo  ->  /c/Users/x/repo
$posix = '/' + $repo.Substring(0, 1).ToLower() + $repo.Substring(2).Replace('\', '/')

# Quote each argument so values containing spaces survive.
$quoted = @()
foreach ($a in $args) {
    $quoted += "'" + ($a -replace "'", "'\''") + "'"
}
$argLine = $quoted -join ' '

& $bash -lc "cd '$posix' && ./sync.sh $argLine"
exit $LASTEXITCODE
