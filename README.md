# OnDebate

1:1 키보드 토론 커뮤니티 MVP입니다.

## 현재 기능

- 토론 메인·상세·작성 화면
- Google·Kakao 로그인 화면
- Supabase 데이터베이스 스키마와 권한 규칙
- Supabase에 토론을 생성하고, 메인 목록·상세에서 불러오는 연결 코드

## Supabase 설정

1. `supabase-schema.sql` 실행
2. `supabase-functions.sql` 실행
3. Google·Kakao OAuth 공급자 활성화

`supabase.js`에는 공개 가능한 Publishable key만 들어 있습니다. 서비스 역할 키나 OAuth Client Secret은 저장소에 넣지 않습니다.

