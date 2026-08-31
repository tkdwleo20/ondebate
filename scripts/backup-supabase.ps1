param(
  [string]$DatabaseUrl
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$backupRoot = Join-Path $projectRoot 'backups'

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  throw "Supabase CLI가 설치되어 있지 않습니다. 설치 후 다시 실행해 주세요: https://supabase.com/docs/guides/local-development/cli/getting-started"
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker Desktop이 설치되어 있지 않거나 실행 중이 아닙니다. 실행 후 다시 시도해 주세요."
}

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  $DatabaseUrl = Read-Host 'Supabase Connect 화면의 Session pooler 연결 문자열을 붙여 넣으세요'
}
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) { throw '연결 문자열이 필요합니다.' }

# Dashboard examples normally contain this placeholder. The password is never saved to disk.
if ($DatabaseUrl.Contains('[YOUR-PASSWORD]')) {
  $securePassword = Read-Host '데이터베이스 비밀번호' -AsSecureString
  $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
    $DatabaseUrl = $DatabaseUrl.Replace('[YOUR-PASSWORD]', [Uri]::EscapeDataString($plainPassword))
  } finally {
    if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
    $plainPassword = $null
  }
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$outputDir = Join-Path $backupRoot $stamp
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

try {
  Write-Host "백업을 시작합니다: $outputDir" -ForegroundColor Cyan
  & supabase db dump --db-url $DatabaseUrl -f (Join-Path $outputDir 'roles.sql') --role-only
  & supabase db dump --db-url $DatabaseUrl -f (Join-Path $outputDir 'schema.sql')
  & supabase db dump --db-url $DatabaseUrl -f (Join-Path $outputDir 'data.sql') --use-copy --data-only

  Get-ChildItem -LiteralPath $outputDir -File | Select-Object Name, Length
  Write-Host '백업이 완료되었습니다. backups 폴더는 Git에서 제외됩니다.' -ForegroundColor Green
} catch {
  Write-Error "백업 중 오류가 발생했습니다. 불완전한 폴더: $outputDir`n$($_.Exception.Message)"
  throw
}

