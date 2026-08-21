# Resend SMTP 연결 메모

1. Resend에서 계정을 만들고 발신 도메인을 추가한다. 실제 서비스 전에는 구매한 도메인의 DNS에 Resend가 안내하는 SPF·DKIM 레코드를 등록한다.
2. Resend의 SMTP credentials에서 SMTP 사용자명과 비밀번호를 만든다.
3. Supabase Dashboard → Authentication → SMTP Settings에서 Custom SMTP를 켠 뒤 다음 값을 넣는다.
   - Host: `smtp.resend.com`
   - Port: `465`
   - User: Resend가 발급한 SMTP 사용자명
   - Password: Resend가 발급한 SMTP 비밀번호
   - Sender email: 인증한 도메인의 발신 주소 (예: `no-reply@내도메인`)
4. Authentication → Email Templates → Confirm signup 템플릿 본문에 `{{ .Token }}`을 넣어 6자리 코드를 발송하도록 저장한다.
5. Authentication → URL Configuration의 Redirect URLs에 `https://ondebate.pages.dev/**`를 추가한다.

Resend SMTP 비밀번호는 절대 웹사이트 파일이나 GitHub에 넣지 않는다.

