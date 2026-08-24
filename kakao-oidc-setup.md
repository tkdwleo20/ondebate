# 카카오 로그인 설정 (이메일 권한 없이)

이 구현은 Supabase의 기본 Kakao OAuth 흐름을 사용하지 않는다. 카카오가 `account_email`을 자동 요청하는 문제를 피하기 위해, 카카오 OpenID Connect ID 토큰을 Supabase로 전달한다.

## 1. Kakao Developers

앱 → 카카오 로그인에서 **OpenID Connect 활성화**를 켠다.

앱 → 플랫폼 키 → REST API 키 화면에서 카카오 로그인 Redirect URI에 아래 주소를 추가한다.

`https://ondebate.pages.dev/kakao-callback.html`

동의항목은 `profile_nickname`, `profile_image`만 사용하고 `account_email`은 사용하지 않는다.

## 2. Supabase Edge Function

Supabase Dashboard → Edge Functions에서 `kakao-token` 함수를 새로 만들고 `supabase/functions/kakao-token/index.ts` 내용을 붙여 넣어 배포한다.

배포 설정에서 **Verify JWT**를 끈다. 이 함수는 로그인 전 사용자가 호출하므로 필요하다.

Supabase Dashboard → Edge Functions → Secrets에 다음 값을 추가한다.

| 이름 | 값 |
| --- | --- |
| `KAKAO_REST_API_KEY` | Kakao Developers의 REST API 키 |
| `KAKAO_CLIENT_SECRET` | Kakao 로그인 Client Secret |
| `SITE_URL` | `https://ondebate.pages.dev` |

Client Secret은 절대로 이 저장소나 사이트 파일에 넣지 않는다.

## 3. Supabase Auth Provider

Authentication → Providers → Kakao는 **Enabled** 상태로 유지한다. Client ID와 Client Secret도 기존과 같이 유지한다. `Allow users without an email`도 켜 둔다.

