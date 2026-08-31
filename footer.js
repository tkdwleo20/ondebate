(() => {
  if (document.querySelector('.site-footer')) return;
  const footer = document.createElement('footer');
  footer.className = 'site-footer';
  footer.innerHTML = `
    <div class="site-footer__inner">
      <span class="site-footer__brand">OnDebate</span>
      <nav aria-label="정책 안내">
        <a href="terms.html">이용약관</a>
        <a href="privacy.html">개인정보처리방침</a>
      </nav>
      <span class="site-footer__contact">문의 <a href="mailto:support@ondebate.co.kr">support@ondebate.co.kr</a></span>
      <span class="site-footer__business">사업자 정보는 추후 업데이트됩니다.</span>
    </div>`;
  const style = document.createElement('style');
  style.textContent = `
    .site-footer{margin-top:auto;border-top:1px solid #e5e5e5;background:#fff;color:#858585;font:12px/1.7 "Noto Sans KR",sans-serif}
    .site-footer__inner{width:min(1120px,calc(100% - 40px));margin:0 auto;padding:20px 0 24px;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
    .site-footer__brand{color:#555;font-weight:700}
    .site-footer nav{display:flex;gap:10px}
    .site-footer a{color:#666;text-decoration:none}.site-footer a:hover{text-decoration:underline}
    .site-footer__contact{margin-left:auto}.site-footer__business{color:#aaa}
    @media(max-width:650px){.site-footer__inner{width:calc(100% - 28px);padding:17px 0 21px;gap:7px 10px}.site-footer__contact{margin-left:0;width:100%}.site-footer__business{width:100%}}
  `;
  document.head.append(style);
  document.body.append(footer);
})();

