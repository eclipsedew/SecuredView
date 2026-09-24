/* SecuredView interface behaviour */
(function () {
  'use strict';

  var calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* mobile navigation */
  var burger = document.getElementById('burger');
  var mnav = document.getElementById('mnav');
  if (burger && mnav) {
    burger.addEventListener('click', function () {
      var open = mnav.classList.toggle('open');
      burger.setAttribute('aria-expanded', String(open));
    });
    mnav.addEventListener('click', function (e) {
      if (e.target.closest('a')) {
        mnav.classList.remove('open');
        burger.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* scroll reveal */
  var targets = document.querySelectorAll('.rv');
  if (calm || !('IntersectionObserver' in window)) {
    Array.prototype.forEach.call(targets, function (el) { el.classList.add('in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
    Array.prototype.forEach.call(targets, function (el) { io.observe(el); });
  }

  /* hero route trace: one orchestrated pass, then it rests */
  var trace = document.getElementById('trace');
  if (trace && !calm) {
    Array.prototype.forEach.call(trace.querySelectorAll('.leg'), function (leg) {
      leg.style.setProperty('--len', leg.getTotalLength().toFixed(1));
    });
    var status = trace.querySelector('.status');
    var word = status && status.querySelector('span');
    if (word) {
      word.textContent = 'Connecting';
      status.setAttribute('data-state', 'wait');
    }
    requestAnimationFrame(function () {
      trace.classList.add('anim');
      if (word) {
        window.setTimeout(function () {
          word.textContent = 'Connected';
          status.setAttribute('data-state', 'live');
        }, 1500);
      }
    });
  }

  /* footer year */
  var year = document.querySelectorAll('[data-year]');
  Array.prototype.forEach.call(year, function (el) {
    el.textContent = String(new Date().getFullYear());
  });
})();
