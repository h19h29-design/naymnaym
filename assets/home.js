/* Progressive enhancement only: all text, real screenshots and store links
   remain available without JavaScript. No analytics or data collection. */
(() => {
  'use strict';
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  // Mobile navigation: Escape, outside click and section navigation close it.
  const header = $('[data-header]');
  const toggle = $('.menu-toggle');
  const nav = $('#navigation');
  const setMenu = (open, restoreFocus = false) => {
    if (!header || !toggle) return;
    header.classList.toggle('menu-open', open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? '메뉴 닫기' : '메뉴 열기');
    if (restoreFocus) toggle.focus();
  };
  toggle?.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
  nav?.addEventListener('click', event => {
    if (event.target.closest('a')) setMenu(false);
  });
  document.addEventListener('click', event => {
    if (header && !header.contains(event.target)) setMenu(false);
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && toggle?.getAttribute('aria-expanded') === 'true') setMenu(false, true);
  });

  // Accessible manual-activation screenshot tabs. Content is never auto-rotated.
  const tabs = $$('.showcase-tab');
  const selectTab = (tab, focus = false) => {
    tabs.forEach(item => {
      const active = item === tab;
      item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      const panel = document.getElementById(item.getAttribute('aria-controls'));
      if (panel) panel.hidden = !active;
    });
    if (focus) tab.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {
      let next = null;
      if (event.key === 'ArrowRight') next = tabs[(index + 1) % tabs.length];
      if (event.key === 'ArrowLeft') next = tabs[(index - 1 + tabs.length) % tabs.length];
      if (event.key === 'Home') next = tabs[0];
      if (event.key === 'End') next = tabs[tabs.length - 1];
      if (next) { event.preventDefault(); selectTab(next, true); }
    });
  });
  if (tabs.length) selectTab(tabs.find(tab => tab.getAttribute('aria-selected') === 'true') || tabs[0]);

  // Full-size actual screenshot viewer. Anchor is a direct PNG fallback.
  const dialog = $('.image-dialog');
  const shots = $$('[data-zoom]');
  let currentShot = 0;
  let opener = null;
  const displayShot = index => {
    currentShot = (index + shots.length) % shots.length;
    const source = shots[currentShot];
    const image = $('.dialog-image', dialog);
    image.src = source.getAttribute('href');
    image.alt = $('img', source)?.alt || source.dataset.title || '실제 앱 화면';
    $('#dialog-title').textContent = source.dataset.title;
    $('.dialog-counter', dialog).textContent = `${currentShot + 1} / ${shots.length}`;
  };
  if (dialog && typeof dialog.showModal === 'function') {
    shots.forEach((shot, index) => shot.addEventListener('click', event => {
      event.preventDefault();
      opener = shot;
      displayShot(index);
      dialog.showModal();
      document.body.classList.add('dialog-open');
    }));
    $('.dialog-close', dialog).addEventListener('click', () => dialog.close());
    $('.dialog-prev', dialog).addEventListener('click', () => displayShot(currentShot - 1));
    $('.dialog-next', dialog).addEventListener('click', () => displayShot(currentShot + 1));
    dialog.addEventListener('click', event => {
      if (event.target === dialog) dialog.close();
    });
    dialog.addEventListener('keydown', event => {
      if (event.key === 'ArrowRight') { event.preventDefault(); displayShot(currentShot + 1); }
      if (event.key === 'ArrowLeft') { event.preventDefault(); displayShot(currentShot - 1); }
    });
    dialog.addEventListener('close', () => {
      document.body.classList.remove('dialog-open');
      opener?.focus({ preventScroll: true });
    });
  }

  // Mobile CTA: keep a per-zone map because IntersectionObserver callbacks
  // contain only changed entries, not the visibility of every observed zone.
  const sticky = $('.mobile-sticky');
  const hero = $('[data-hero]');
  const mobile = window.matchMedia('(max-width: 640px)');
  if (sticky && hero && 'IntersectionObserver' in window) {
    let heroVisible = true;
    const visibility = new Map();
    const renderSticky = () => {
      sticky.hidden = !mobile.matches || heroVisible || [...visibility.values()].some(Boolean);
    };
    const heroObserver = new IntersectionObserver(entries => {
      heroVisible = entries[0].isIntersecting;
      renderSticky();
    });
    heroObserver.observe(hero);
    const zoneObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => visibility.set(entry.target, entry.isIntersecting));
      renderSticky();
    });
    $$('[data-hide-sticky]').forEach(zone => {
      visibility.set(zone, false);
      zoneObserver.observe(zone);
    });
    if (mobile.addEventListener) mobile.addEventListener('change', renderSticky);
    renderSticky();
  }
  document.documentElement.classList.add('js');
})();
