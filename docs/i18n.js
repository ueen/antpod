// antpod.eu: shared language handling (the share page /open has its own copy).
//
// Load this in <head>: it picks the language before the body renders, from
// the same `lang` cookie the share page sets, else the browser language.
// English lives in the HTML. Two ways to translate:
//   • Elements with data-lang="xx" show only in that language (rich content
//     such as the guide). Give the non-English ones `hidden`, so the page
//     still reads right without JavaScript.
//   • data-i18n="key" (innerHTML), data-i18n-src / -title / -content="key"
//     (attributes), looked up in window.I18N = { de: {…}, fr: {…}, es: {…} },
//     applied by AntpodI18n.apply() at the end of <body>.
// <select id="lang-select" onchange="setLang(this.value)"> switches.
(function () {
  var SUPPORTED = ['en', 'de', 'es', 'fr'];
  var ATTRS = ['src', 'title', 'content'];
  var originals = new Map();

  function cookieLang() {
    var m = document.cookie.match(/(?:^|;)\s*lang=([^;]*)/);
    var c = m && decodeURIComponent(m[1]);
    return SUPPORTED.indexOf(c) >= 0 ? c : null;
  }

  function browserLang() {
    var list = navigator.languages || [navigator.language || 'en'];
    for (var i = 0; i < list.length; i++) {
      var code = String(list[i]).split('-')[0].toLowerCase();
      if (SUPPORTED.indexOf(code) >= 0) return code;
    }
    return 'en';
  }

  // The English original of an element's content or attribute, kept from
  // before the first translation so switching back to English works.
  function original(el, prop) {
    var o = originals.get(el);
    if (!o) { o = {}; originals.set(el, o); }
    if (!(prop in o)) o[prop] = prop === 'html' ? el.innerHTML : el.getAttribute(prop);
    return o[prop];
  }

  var lang = cookieLang() || browserLang();
  document.documentElement.lang = lang;

  // data-lang blocks: CSS keyed on <html lang>, so the right one shows from
  // the first paint, `hidden` or not.
  var css = SUPPORTED.map(function (l) {
    return 'html[lang="' + l + '"] [data-lang="' + l + '"]{display:block!important}' +
           'html:not([lang="' + l + '"]) [data-lang="' + l + '"]{display:none!important}';
  }).join('');
  var style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  function apply(code) {
    if (code) lang = code;
    var t = (window.I18N || {})[lang] || {};
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var en = original(el, 'html');
      var v = t[el.getAttribute('data-i18n')];
      el.innerHTML = v != null ? v : en;
    });
    ATTRS.forEach(function (attr) {
      document.querySelectorAll('[data-i18n-' + attr + ']').forEach(function (el) {
        var en = original(el, attr);
        var v = t[el.getAttribute('data-i18n-' + attr)];
        el.setAttribute(attr, v != null ? v : en);
      });
    });
    var sel = document.getElementById('lang-select');
    if (sel) sel.value = lang;
  }

  window.setLang = function (code) {
    if (SUPPORTED.indexOf(code) < 0) return;
    document.cookie = 'lang=' + code + ';max-age=31536000;path=/;SameSite=Lax';
    apply(code);
  };

  window.AntpodI18n = { apply: function () { apply(); }, get lang() { return lang; } };
})();
