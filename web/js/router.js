/**
 * History API router. Routes: / (board), /ramp/:id (detail), /tide /water
 * /wind (stat screens). The server serves index.html for all of these
 * (HTML5 static fallback), so deep links and reloads work.
 */

export function createRouter({ routes, container }) {
  let current = null; // { view, params }

  function match(pathname) {
    const rampMatch = pathname.match(/^\/ramp\/(\d+)\/?$/);
    if (rampMatch) return { view: routes.detail, params: { id: +rampMatch[1] } };
    if (/^\/(tide|water|wind)\/?$/.test(pathname)) {
      return { view: routes.stat, params: { kind: pathname.replaceAll('/', '') } };
    }
    return { view: routes.board, params: {} };
  }

  function render(pathname, { restoreScroll = null, moveFocus = true } = {}) {
    if (current?.view?.unmount) current.view.unmount();
    const { view, params } = match(pathname);
    current = { view, params };
    container.innerHTML = '';
    view.mount(container, params);
    if (restoreScroll != null) {
      window.scrollTo(0, restoreScroll);
    } else {
      window.scrollTo(0, 0);
      if (moveFocus) {
        // Move focus to the new view's heading for keyboard/screen-reader users.
        const heading = container.querySelector('h1');
        if (heading) {
          heading.setAttribute('tabindex', '-1');
          heading.focus({ preventScroll: true });
        }
      }
    }
  }

  function navigate(pathname) {
    if (pathname === location.pathname) return;
    history.replaceState({ scrollY: window.scrollY }, '', location.pathname + location.search);
    history.pushState({}, '', pathname);
    render(pathname);
  }

  function start() {
    history.scrollRestoration = 'manual';

    document.addEventListener('click', (event) => {
      if (event.defaultPrevented || event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const anchor = event.target.closest('a[href]');
      if (!anchor || anchor.origin !== location.origin) return;
      if (anchor.hasAttribute('download') || anchor.target === '_blank') return;
      if (anchor.getAttribute('href').startsWith('#')) return;
      event.preventDefault();
      navigate(anchor.pathname);
    });

    window.addEventListener('popstate', (event) => {
      render(location.pathname, { restoreScroll: event.state?.scrollY ?? null });
    });

    // Initial render: no focus move — a fresh page load should not start
    // with a focus ring on the headline.
    render(location.pathname, { restoreScroll: window.scrollY || null, moveFocus: false });
  }

  return { start, navigate, get current() { return current; } };
}
