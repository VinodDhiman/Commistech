/* =============================================
   COMMIS TECH - Main JavaScript
   Theme Toggle, Navigation, Animations
   ============================================= */

// ─── Theme Management ───────────────────────
const ThemeManager = (() => {
  const STORAGE_KEY = 'commistech-theme';
  // FIX H1: only allow known-good values from localStorage
  const VALID_THEMES = ['light', 'dark'];
  const html = document.documentElement;

  function getPreferred() {
    const saved = localStorage.getItem(STORAGE_KEY);
    // Validate against allowlist before using
    if (saved && VALID_THEMES.includes(saved)) return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function apply(theme) {
    // Only apply a validated theme value
    if (!VALID_THEMES.includes(theme)) return;
    html.setAttribute('data-theme', theme);
    localStorage.setItem(STORAGE_KEY, theme);
    document.querySelectorAll('.theme-toggle').forEach(btn => {
      btn.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`);
    });
  }

  function toggle() {
    const current = html.getAttribute('data-theme') || 'light';
    apply(current === 'dark' ? 'light' : 'dark');
  }

  function init() {
    apply(getPreferred());
    document.querySelectorAll('.theme-toggle').forEach(btn => {
      btn.addEventListener('click', toggle);
    });

    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
      if (!localStorage.getItem(STORAGE_KEY)) {
        apply(e.matches ? 'dark' : 'light');
      }
    });
  }

  return { init, toggle };
})();

// ─── Navigation ──────────────────────────────
const Navigation = (() => {
  function init() {
    const navbar = document.getElementById('navbar');
    const menuToggle = document.querySelector('.menu-toggle');
    const navMobile = document.querySelector('.nav-mobile');

    if (navbar) {
      const onScroll = () => {
        navbar.classList.toggle('scrolled', window.scrollY > 20);
      };
      window.addEventListener('scroll', onScroll, { passive: true });
      onScroll();
    }

    if (menuToggle && navMobile) {
      menuToggle.addEventListener('click', () => {
        const isOpen = navMobile.classList.toggle('open');
        menuToggle.classList.toggle('active', isOpen);
        menuToggle.setAttribute('aria-expanded', String(isOpen));
        document.body.style.overflow = isOpen ? 'hidden' : '';
      });

      navMobile.querySelectorAll('a').forEach(link => {
        link.addEventListener('click', () => {
          navMobile.classList.remove('open');
          menuToggle.classList.remove('active');
          menuToggle.setAttribute('aria-expanded', 'false');
          document.body.style.overflow = '';
        });
      });

      document.addEventListener('click', (e) => {
        if (!navbar?.contains(e.target) && !navMobile.contains(e.target)) {
          navMobile.classList.remove('open');
          menuToggle.classList.remove('active');
          menuToggle.setAttribute('aria-expanded', 'false');
          document.body.style.overflow = '';
        }
      });
    }

    // Active nav link
    const currentPath = window.location.pathname.split('/').pop() || 'index.html';
    document.querySelectorAll('.nav-links a, .nav-mobile-links a').forEach(link => {
      const href = link.getAttribute('href') || '';
      if (href === currentPath || href.endsWith(currentPath) ||
          (currentPath === 'index.html' && (href === './' || href === '#' || href === ''))) {
        link.classList.add('active');
      }
    });
  }

  return { init };
})();

// ─── Scroll Reveal Animations ─────────────────
const ScrollReveal = (() => {
  function init() {
    const elements = document.querySelectorAll('.reveal');
    if (!elements.length) return;

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -40px 0px' });

    elements.forEach(el => observer.observe(el));
  }

  return { init };
})();

// ─── Counter Animation ────────────────────────
const CounterAnimation = (() => {
  function animateCounter(el) {
    const target = parseInt(el.dataset.target || el.textContent, 10);
    const suffix = el.dataset.suffix || '';
    const duration = 1800;
    const start = performance.now();

    const update = (now) => {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(eased * target);
      // FIX: use textContent — never innerHTML for counter display
      el.textContent = current.toLocaleString() + suffix;
      if (progress < 1) requestAnimationFrame(update);
    };

    requestAnimationFrame(update);
  }

  function init() {
    const counters = document.querySelectorAll('.stat-number[data-target]');
    if (!counters.length) return;

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });

    counters.forEach(counter => observer.observe(counter));
  }

  return { init };
})();

// ─── Form Validation ──────────────────────────
// FIX H3: validate all required fields and email format before "submit"
function validateContactForm(form) {
  const errors = [];

  // FIX M2: honeypot bot check — bots fill hidden fields; humans leave them blank
  const honeypot = form.querySelector('[name="_hp_url"]');
  if (honeypot && honeypot.value.trim() !== '') {
    // Silently reject bot submissions without revealing the check
    return ['_bot_'];
  }

  const get = (id) => (form.querySelector(`#${id}`)?.value || '').trim();

  if (!get('first-name')) errors.push('First name is required.');
  if (!get('last-name')) errors.push('Last name is required.');

  const email = get('email');
  if (!email) {
    errors.push('Email address is required.');
  } else if (!/^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/.test(email)) {
    errors.push('Please enter a valid email address.');
  }

  if (!get('message')) errors.push('Message is required.');

  return errors.length === 0 ? true : errors;
}

function showFormErrors(form, errors) {
  // Remove previous error banner if any
  form.querySelector('.form-error-banner')?.remove();

  const banner = document.createElement('div');
  banner.className = 'form-error-banner';
  banner.setAttribute('role', 'alert');
  banner.style.cssText = [
    'background:rgba(239,68,68,0.08)',
    'border:1px solid rgba(239,68,68,0.3)',
    'border-radius:10px',
    'padding:1rem 1.25rem',
    'margin-bottom:1.25rem',
    'color:#DC2626',
    'font-size:0.88rem',
  ].join(';');

  const ul = document.createElement('ul');
  ul.style.cssText = 'margin:0; padding-left:1.25rem; line-height:1.8;';
  errors.forEach(msg => {
    const li = document.createElement('li');
    li.textContent = msg;   // textContent — never innerHTML for user-visible strings
    ul.appendChild(li);
  });
  banner.appendChild(ul);
  form.prepend(banner);
  banner.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

// ─── Contact Form ──────────────────────────────
const ContactForm = (() => {
  function init() {
    const form = document.getElementById('contact-form');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      // Remove old error banner
      form.querySelector('.form-error-banner')?.remove();

      // FIX H3: validate before doing anything
      const result = validateContactForm(form);
      if (result !== true) {
        // Bot check — fail silently so bots don't know they were caught
        if (result[0] === '_bot_') return;
        showFormErrors(form, result);
        return;
      }

      const btn = form.querySelector('[type="submit"]');

      // FIX H2: clone the button's child nodes via DOM API instead of
      // saving/restoring raw innerHTML (avoids XSS-via-innerHTML-restore)
      const originalChildren = Array.from(btn.childNodes).map(n => n.cloneNode(true));

      btn.disabled = true;
      // Use textContent — plain text, no HTML parsing
      btn.textContent = 'Sending…';

      // Placeholder: replace with real fetch() to your backend/API
      await new Promise(r => setTimeout(r, 1500));

      btn.textContent = '✓ Message Sent!';
      btn.style.background = 'linear-gradient(135deg, #22C55E, #16A34A)';

      setTimeout(() => {
        btn.style.background = '';
        btn.disabled = false;
        // Restore original children safely from the pre-cloned DOM nodes
        btn.replaceChildren(...originalChildren);
        form.reset();
      }, 3000);
    });
  }

  return { init };
})();

// ─── Smooth anchor scrolling ──────────────────
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const href = anchor.getAttribute('href');

      // FIX H4: validate href is a safe, simple ID selector before using it
      // Bare "#" or empty — preventDefault so the browser doesn't jump to top, then bail
      if (!href || href === '#') { e.preventDefault(); return; }
      // Reject anything that isn't #<valid-CSS-ident> — prevents CSS selector injection
      if (!/^#[a-zA-Z][a-zA-Z0-9_-]*$/.test(href)) return;

      // Use getElementById instead of querySelector to completely avoid
      // CSS selector injection — getElementById only accepts the raw ID string
      const target = document.getElementById(href.slice(1));
      if (target) {
        e.preventDefault();
        const offset = 80;
        const top = target.getBoundingClientRect().top + window.scrollY - offset;
        window.scrollTo({ top, behavior: 'smooth' });
      }
    });
  });
}

// ─── Initialize ───────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  ThemeManager.init();
  Navigation.init();
  ScrollReveal.init();
  CounterAnimation.init();
  ContactForm.init();
  initSmoothScroll();

  // Staggered reveal delays for grid children
  document.querySelectorAll('.services-grid, .featured-grid, .stats-grid, .blog-grid, .detail-grid').forEach(grid => {
    grid.querySelectorAll(':scope > *').forEach((child, i) => {
      child.classList.add('reveal');
      if (i < 6) child.classList.add(`reveal-delay-${i + 1}`);
    });
  });
});
