// Records the debate list a visitor used before opening a detail page.
// It runs independently from the shared auth script so browser caches cannot
// drop the list context on category, search, or popular pages.
document.addEventListener('click', event => {
  const clicked = event.target.closest?.('a[href^="debate-detail.html?id="]');
  const link = clicked || event.target.closest?.('article')?.querySelector('a[href^="debate-detail.html?id="]');
  if (!link) return;
  const page = location.pathname.split('/').pop() || 'index.html';
  const destination = new URL(link.href, location.href);
  if (destination.searchParams.has('from')) return;
  if (page === 'popular.html') destination.searchParams.set('from', link.closest('#daily') ? 'popular-daily' : 'popular-weekly');
  else if (page === 'category.html') { destination.searchParams.set('from', 'category'); destination.searchParams.set('category', new URLSearchParams(location.search).get('name') || ''); }
  else if (page === 'search.html') { destination.searchParams.set('from', 'search'); destination.searchParams.set('q', new URLSearchParams(location.search).get('q') || ''); }
  else return;
  link.href = destination.href;
  if (!clicked) { event.preventDefault(); event.stopImmediatePropagation(); location.href = destination.href; }
}, true);

