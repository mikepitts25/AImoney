/* ============================================
   AI Income Blueprint - Main JavaScript
   Vanilla JS, no dependencies
   ============================================ */

document.addEventListener('DOMContentLoaded', function () {

  // ---- Mobile Navigation Toggle ----
  const hamburger = document.getElementById('hamburger');
  const mobileNav = document.getElementById('mobile-nav');
  if (hamburger && mobileNav) {
    hamburger.addEventListener('click', function () {
      mobileNav.classList.toggle('open');
      hamburger.setAttribute('aria-expanded',
        mobileNav.classList.contains('open'));
    });
    // Close mobile nav when a link is clicked
    mobileNav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        mobileNav.classList.remove('open');
        hamburger.setAttribute('aria-expanded', 'false');
      });
    });
  }

  // ---- Sticky Nav Background on Scroll ----
  const nav = document.getElementById('main-nav');
  if (nav) {
    window.addEventListener('scroll', function () {
      if (window.scrollY > 50) {
        nav.classList.add('scrolled');
      } else {
        nav.classList.remove('scrolled');
      }
    }, { passive: true });
  }

  // ---- FAQ Accordion ----
  document.querySelectorAll('.faq-item').forEach(function (item) {
    var btn = item.querySelector('.faq-question');
    var answer = item.querySelector('.faq-answer');
    if (btn && answer) {
      btn.addEventListener('click', function () {
        var isOpen = item.classList.contains('active');
        // Close all
        document.querySelectorAll('.faq-item').forEach(function (i) {
          i.classList.remove('active');
          var a = i.querySelector('.faq-answer');
          if (a) a.classList.remove('open');
        });
        // Toggle current
        if (!isOpen) {
          item.classList.add('active');
          answer.classList.add('open');
        }
      });
    }
  });

  // ---- TOC Accordion (Sales Page) ----
  document.querySelectorAll('.toc-item').forEach(function (item) {
    var toggle = item.querySelector('.toc-toggle');
    var content = item.querySelector('.toc-content');
    if (toggle && content) {
      toggle.addEventListener('click', function () {
        var isOpen = item.classList.contains('active');
        item.classList.toggle('active');
        content.classList.toggle('open');
      });
    }
  });

  // ---- Smooth Scroll for Anchor Links ----
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  // ---- Announcement Bar Dismiss ----
  var dismissBtn = document.getElementById('dismiss-announcement');
  var announcementBar = document.getElementById('announcement-bar');
  if (dismissBtn && announcementBar) {
    if (sessionStorage.getItem('announcement-dismissed') === 'true') {
      announcementBar.style.display = 'none';
    }
    dismissBtn.addEventListener('click', function () {
      announcementBar.style.display = 'none';
      sessionStorage.setItem('announcement-dismissed', 'true');
    });
  }

  // ---- Copy to Clipboard for Prompt Blocks ----
  document.querySelectorAll('.copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var block = btn.closest('.prompt-block');
      var code = block.querySelector('code') || block;
      var text = code.textContent || code.innerText;
      navigator.clipboard.writeText(text.trim()).then(function () {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(function () {
          btn.textContent = 'Copy';
          btn.classList.remove('copied');
        }, 2000);
      });
    });
  });

  // ---- Scroll Progress Bar (Guide Page) ----
  var progressBar = document.getElementById('progress-bar');
  if (progressBar) {
    window.addEventListener('scroll', function () {
      var scrollTop = window.scrollY;
      var docHeight = document.documentElement.scrollHeight - window.innerHeight;
      var scrollPercent = docHeight > 0 ? (scrollTop / docHeight) * 100 : 0;
      progressBar.style.width = scrollPercent + '%';
    }, { passive: true });
  }

  // ---- Guide Sidebar TOC Active State (IntersectionObserver) ----
  var tocLinks = document.querySelectorAll('.toc-link');
  if (tocLinks.length > 0) {
    var sections = [];
    tocLinks.forEach(function (link) {
      var href = link.getAttribute('href');
      if (href && href.startsWith('#')) {
        var section = document.querySelector(href);
        if (section) sections.push(section);
      }
    });

    if (sections.length > 0) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            tocLinks.forEach(function (l) { l.classList.remove('active'); });
            var activeLink = document.querySelector(
              '.toc-link[href="#' + entry.target.id + '"]'
            );
            if (activeLink) activeLink.classList.add('active');
          }
        });
      }, {
        rootMargin: '-80px 0px -60% 0px',
        threshold: 0
      });

      sections.forEach(function (section) { observer.observe(section); });
    }
  }

  // ---- Guide Mobile TOC Toggle ----
  var mobileTocBtn = document.getElementById('mobile-toc-toggle');
  var mobileTocMenu = document.getElementById('mobile-toc-menu');
  if (mobileTocBtn && mobileTocMenu) {
    mobileTocBtn.addEventListener('click', function () {
      mobileTocMenu.classList.toggle('hidden');
    });
    mobileTocMenu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        mobileTocMenu.classList.add('hidden');
      });
    });
  }

  // ---- Fade-in Animation on Scroll ----
  var animatedElements = document.querySelectorAll('.animate-on-scroll');
  if (animatedElements.length > 0 && 'IntersectionObserver' in window) {
    var animObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('animate-fade-in-up');
          animObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1 });

    animatedElements.forEach(function (el) { animObserver.observe(el); });
  }

});
