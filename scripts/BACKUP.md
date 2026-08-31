# Supabase 수동 백업

1. Docker Desktop을 실행하고, 프로젝트 폴더에서 `npm install supabase --save-dev`를 실행합니다.
2. Supabase Dashboard의 **Connect**에서 **Session pooler** 연결 문자열을 복사합니다.
3. PowerShell에서 다음을 실행합니다.

```powershell
cd C:\Users\pc\Documents\Codex\2026-08-20\new-chat\ondebate
.\scripts\backup-supabase.ps1
```

연결 문자열에 `[YOUR-PASSWORD]`가 있으면 스크립트가 데이터베이스 비밀번호를 별도로 묻습니다. 비밀번호와 연결 문자열은 파일에 저장되지 않습니다.

성공하면 `backups\YYYY-MM-DD_HHMMSS` 폴더에 아래 세 파일이 생깁니다.

- `roles.sql`: 역할 정보
- `schema.sql`: 테이블·함수·정책 구조
- `data.sql`: 서비스 데이터

`backups` 폴더는 Git에서 제외되어 GitHub에 업로드되지 않습니다. 이 폴더를 암호화된 개인 저장소 또는 신뢰할 수 있는 개인 클라우드에 별도 보관하세요.

