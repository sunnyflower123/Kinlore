/* ============================================================================
   Kinlore, the page. The bespoke half.

   The engine drives scroll; this file is the surface. Everything visible below
   the chrome computes from ONE model (`archive`, further down) rather than
   being drawn as a picture of a screen: the tallies, the tree, the proposal
   rows and the closing record all read the same object, so confirming a name in
   act 4 changes the count in act 1 because it changed the data, not because
   two places were updated by hand.

   Nothing here edits the engine. The peak reads --sc-p, which the engine
   publishes on each act element, exactly as the skill prescribes.
   ========================================================================== */
(function () {
  'use strict';

  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $  = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ---------------------------------------------------------------- model --
     A sample family. The transcript, its length and the place are real: the
     recording is samples/mokki-puhdas.m4a and the sentence is its transcript.
     The model's answer is canned, which the page says on its face. */
  /* The recording is Finnish, and so is the app. When the page is read in
     English every string it renders is translated, including this one, and the
     page says so beside the play button rather than letting the reader assume
     the app speaks English. */
  /* One sample per language, and both are synthetic. The Finnish one is
     samples/mokki-puhdas.m4a straight out of the repository; the English one
     was made by the same method scripts/make-synthetic-samples.py uses, at the
     same 150 words per minute and through the same 22.05 kHz mono WAV and AAC
     chain. The voice is Karen rather than the Grandma the Finnish samples use:
     Grandma is one of macOS's stylised character voices, and the clarity it
     costs is not worth the age it buys on a page somebody hears once.

       say -v "Karen" -r 150 -o en.aiff "<the sentence>"
       afconvert -f WAVE -d LEI16@22050 -c 1 en.aiff en.wav
       afconvert -f m4af -d aac -c 1 en.wav sample-cottage-en.m4a

     Both durations are read out of the files' own mvhd atoms rather than
     guessed, and they drive the timer and the caption. */
  var VOICES = {
    fi: [{ id: 'grandma', label: 'Grandma', src: 'assets/sample-mokki-puhdas.m4a', seconds: 13.24 }],
    en: [{ id: 'karen',  label: 'Karen',  src: 'assets/sample-cottage-en.m4a',        seconds: 11.61 },
         { id: 'daniel', label: 'Daniel', src: 'assets/sample-cottage-en-daniel.m4a', seconds: 12.31 }]
  };
  var voiceChoice = 'karen';
  try { voiceChoice = localStorage.getItem('kinlore.voice') || 'karen'; } catch (e) {}

  function voices() { return VOICES[lang]; }
  function currentVoice() {
    var list = voices();
    for (var i = 0; i < list.length; i++) if (list[i].id === voiceChoice) return list[i];
    return list[0];
  }
  function audioSeconds() { return currentVoice().seconds; }
  var QUOTA_SECONDS = 600;     /* the free tier: ten minutes of AI a month */

  var archive = {
    family: 'Virtaset',
    people: 3,
    photos: 1,
    memories: 0,
    secondsUsed: 0,
    told: false,
    subjects: [
      { id: 'mokki', kind: 'photo', name: { fi: 'Mökin ranta', en: 'The cottage shore' },
        sub: { fi: 'Ei vielä muistoja', en: 'No memories yet' }, memories: 0 },
      { id: 'sanni', kind: 'person', name: { fi: 'Sanni', en: 'Sanni' },
        sub: { fi: 'Perustaja', en: 'Founder' }, memories: 0 }
    ],
    /* Rule 4: everything the model inferred starts here, at confirmed = 0. */
    proposals: [
      { id: 'aino',  name: 'Aino',  state: 'proposed',
        heard: { fi: 'Aino oli siinä vieressäni', en: 'Aino was there beside me' } },
      { id: 'toivo', name: 'Toivo', state: 'proposed',
        heard: { fi: 'Toivo otti sen kuvan', en: 'Toivo took the picture' } }
    ],
    guest: null
  };

  var T = {
    fi: {
      proposed: 'vahvistamatta', confirmed: 'vahvistettu', member: 'jäsen',
      photoSub: 'Ei vielä muistoja', photoSub1: '1 muisto',
      hintIdle: 'Paina ja ala puhua', hintRec: 'Kuuntelen', hintWork: 'Järjestelen muistoa…',
      qs: ['Kuka muu oli paikalla?', 'Millainen ihminen Aino oli?', 'Minä vuonna tämä suunnilleen oli?'],
      propState: 'vahvistamatta', voiceLabel: 'Ääni',
      wireBody: '"Kuva on otettu mökin\n            rannassa Puumalassa…",',
      confirmedWord: 'Vahvistettu', rejectedWord: 'Hylätty, ei tallennettu',
      undo: 'Kumoa',
      liveYes: ' on nyt sukupuussa. Sinä vahvistit sen, ei malli.',
      liveNo:  ' jäi pois. Puuttuva nimi on turvallisempi virhe kuin väärä.',
      liveUndo: 'Kumottu. Nimi on taas vahvistamatta.',
      treeOpenOne: 'nimi odottaa ihmistä.',
      treeOpenMany: 'nimeä odottaa ihmistä.',
      treeStart: 'Puu kasvaa vasta kun joku kertoo jotain.',
      treeDone: 'Ei katkoviivoja. Jokaisen nimen on vahvistanut ihminen.',
      treeNone: 'Puu jäi vajaaksi, ja se on kelvollinen lopputulos.',
      keptLine: 'Sana sanalta niin kuin kirjoitit sen. Sääntö 3: alkuperäistä ei siivota, koska kertojalta ei ehkä voi enää kysyä.',
      guestTag: 'sinun',
      vAll: 'Sukupuussa ei ole enää katkoviivaa. Sen teit sinä, ei malli.',
      vSome: 'Yksi nimi jäi pois, ja se on kelvollinen lopputulos: väärä sukulaisuus on pahempi kuin puuttuva.',
      vNone: 'Kaksi nimeä on yhä katkoviivalla. Sivu ei täytä niitä puolestasi, eikä sovelluskaan täytä.',
      vOpen: 'Yksi nimi on yhä katkoviivalla. Se ei ole hylätty, sitä ei vain ole vielä kysytty keneltäkään.',
      vGuest: ' Yhtä nimeä ei voi vahvistaa täältä ollenkaan: sitä varten pitää kysyä häneltä.'
    },
    en: {
      proposed: 'unconfirmed', confirmed: 'confirmed', member: 'member',
      /* The app's own string, then a gloss. The panel is the first thing a
         stranger reads, so it is the last place to leave untranslated. */
      photoSub: 'No memories yet', photoSub1: '1 memory',
      hintIdle: 'Press and start talking', hintRec: 'Listening', hintWork: 'Organising the memory…',
      qs: ['Who else was there?', 'What sort of person was Aino?', 'Roughly what year was this?'],
      propState: 'unconfirmed', voiceLabel: 'Voice',
      wireBody: '"The photograph was taken at\n            the cottage shore…",',
      confirmedWord: 'Confirmed', rejectedWord: 'Rejected, not written',
      undo: 'Undo',
      liveYes: ' is in the family tree now. You confirmed that, not the model.',
      liveNo:  ' was left out. A missing name is a safer error than a wrong one.',
      liveUndo: 'Undone. The name is unconfirmed again.',
      treeOpenOne: 'name is waiting for a person.',
      treeOpenMany: 'names are waiting for a person.',
      treeStart: 'The tree grows once somebody tells something.',
      treeDone: 'No dashed lines. Every name here was confirmed by a person.',
      treeNone: 'The tree stayed incomplete, and that is a good outcome.',
      keptLine: 'Word for word as you typed it. Rule 3: the original is never tidied, because the person who said it may not be there to ask.',
      guestTag: 'yours',
      vAll: 'There is no dotted line left in the tree. You did that, not the model.',
      vSome: 'One name was left out, and that is a good outcome: a wrong relationship is worse than a missing one.',
      vNone: 'Two names are still dotted. This page will not fill them in for you, and neither will the app.',
      vOpen: 'One name is still dotted. It has not been rejected, it has simply not been asked about yet.',
      vGuest: ' One name cannot be confirmed from here at all. That one needs you to go and ask.'
    }
  };
  var lang = 'en';
  var t = function (k) { return T[lang][k]; };

  /* ------------------------------------------------------------- language -- */
  function setLang(next) {
    lang = next === 'fi' ? 'fi' : 'en';
    document.documentElement.setAttribute('data-lang', lang);
    document.documentElement.lang = lang;
    $$('[data-set-lang]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-set-lang') === lang));
    });
    try { localStorage.setItem('kinlore.lang', lang); } catch (e) {}
    render();
  }

  $$('[data-set-lang]').forEach(function (b) {
    b.addEventListener('click', function () { setLang(b.getAttribute('data-set-lang')); });
  });

  /* The initial choice is made in the boot block at the bottom: setLang renders,
     and the elements it renders into are declared further down this file. */

  /* --------------------------------------------------------------- how to --
     Opens itself once and never again, closes on Esc, on the button, and on
     the visitor scrolling past the act it is describing. It is not modal on
     purpose: a panel that traps focus and freezes the page in front of the
     thing it is explaining is worse than the confusion it is fixing. */
  var howto = $('#howto'), howtoOpen = $('#howto-open'), howtoClose = $('#howto-close');
  var howtoVeil = $('#howto-veil');
  howtoVeil.hidden = false;   /* markup ships it hidden so no-script never dims */
  howtoVeil.addEventListener('click', function () { setHowto(false); howtoOpen.focus(); });

  function howtoIsOpen() { return document.documentElement.getAttribute('data-howto') !== 'seen'; }

  function setHowto(open) {
    if (open) document.documentElement.removeAttribute('data-howto');
    else document.documentElement.setAttribute('data-howto', 'seen');
    howtoOpen.setAttribute('aria-expanded', String(open));
    try { localStorage.setItem('kinlore.howto', open ? 'open' : 'seen'); } catch (e) {}
  }

  /* The markup ships with the panel open, because that is what a first visit
     and a scriptless visit both want. The head script decides otherwise for a
     returning one, so the button's state is synced to what it decided. */
  howtoOpen.setAttribute('aria-expanded', String(howtoIsOpen()));

  howtoOpen.addEventListener('click', function () {
    var open = howtoIsOpen();
    setHowto(!open);
    if (!open) $('#howto-h').focus();       /* opened by a person: take them there */
    else howtoOpen.focus();
  });
  howtoClose.addEventListener('click', function () { setHowto(false); howtoOpen.focus(); });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    if (!howtoIsOpen()) return;
    setHowto(false); howtoOpen.focus();
  });
  /* Scrolling past the first act is an answer too. */
  addEventListener('scroll', function () {
    if (scrollY < innerHeight * 1.2 || !howtoIsOpen()) return;
    setHowto(false);
  }, { passive: true });

  /* ------------------------------------------------------------- big text -- */
  var bigBtn = $('#bigtext');
  bigBtn.addEventListener('click', function () {
    var on = document.documentElement.hasAttribute('data-bigtext');
    if (on) document.documentElement.removeAttribute('data-bigtext');
    else document.documentElement.setAttribute('data-bigtext', '');
    bigBtn.setAttribute('aria-pressed', String(!on));
    if (window.ScrollCraft && ScrollCraft.instances[0]) ScrollCraft.instances[0].layout();
  });

  /* --------------------------------------------------------------- render -- */
  var treeList = $('#tree-list'), treeState = $('#tree-state');
  var subjectsEl = $('#subjects'), proposalsEl = $('#proposals');

  function nodes() {
    var out = [
      { id: 'family', depth: 0, name: archive.family, state: 'confirmed', tag: '', to: '#surface' },
      { id: 'sanni',  depth: 1, name: 'Sanni',        state: 'confirmed', tag: t('member'), to: '#tell' }
    ];
    archive.proposals.forEach(function (p) {
      if (p.state === 'rejected') return;
      out.push({
        id: p.id, depth: 1, name: p.name,
        state: p.state === 'confirmed' ? 'confirmed' : 'proposed',
        tag: p.state === 'confirmed' ? t('confirmed') : t('proposed'),
        to: '#confirm',
        /* A node appears once the telling has produced it, and once somebody
           has acted on it, it stays whatever the scroll does afterwards. */
        show: archive.told || p.state !== 'proposed'
      });
    });
    if (archive.guest) {
      out.push({ id: 'guest', depth: 1, name: archive.guest, state: 'proposed', tag: t('guestTag'), to: '#ask', show: true });
    }
    return out.filter(function (n) { return n.show !== false; });
  }

  function renderTree() {
    var list = nodes();
    treeList.innerHTML = '';
    list.forEach(function (n) {
      var li = document.createElement('li');
      li.setAttribute('data-depth', String(n.depth));
      li.setAttribute('data-state', n.state);
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'node';
      b.innerHTML = '<span class="node__dot"></span><span class="node__name"></span><span class="node__tag"></span>';
      $('.node__name', b).textContent = n.name;
      $('.node__tag', b).textContent = n.tag;
      b.setAttribute('aria-label', n.name + (n.tag ? ', ' + n.tag : ''));
      b.addEventListener('click', function () {
        var target = $(n.to);
        if (target) target.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      });
      li.appendChild(b);
      treeList.appendChild(li);
    });

    /* The line has to be true at every point of the visit, which is four
       states and not two: before anything is proposed it must not congratulate
       the visitor on a tree nobody has been asked about yet, and a tree left
       incomplete on purpose is not the same as a tree completed. */
    var open = list.filter(function (n) { return n.state === 'proposed'; }).length;
    var yes = archive.proposals.filter(function (p) { return p.state === 'confirmed'; }).length;
    treeState.innerHTML = '';
    if (open) {
      var b = document.createElement('b');
      b.textContent = String(open);
      treeState.appendChild(b);
      treeState.appendChild(document.createTextNode(' ' + (open === 1 ? t('treeOpenOne') : t('treeOpenMany'))));
    } else if (!archive.told) {
      treeState.textContent = t('treeStart');
    } else if (!yes) {
      treeState.textContent = t('treeNone');
    } else {
      treeState.textContent = t('treeDone');
    }
  }

  function renderArchive() {
    $('[data-tally="people"]').textContent = String(archive.people);
    $('[data-tally="memories"]').textContent = String(archive.memories);
    $('[data-tally="photos"]').textContent = String(archive.photos);
    $('[data-tally="memories"]').classList.toggle('is-new', archive.memories > 0);

    var used = archive.secondsUsed;
    $('#quota-text').textContent = fmt(used) + ' / 10:00';
    $('#quota-fill').style.setProperty('--w', String(Math.min(1, used / QUOTA_SECONDS)));

    subjectsEl.innerHTML = '';
    archive.subjects.concat(
      archive.proposals.filter(function (p) { return p.state === 'confirmed'; })
                       .map(function (p) { return { id: p.id, kind: 'person', name: p.name, sub: { fi: 'Vahvistettu', en: 'Confirmed' }, memories: 0 }; })
    ).forEach(function (s) {
      var li = document.createElement('li');
      var sub = s.id === 'mokki' && archive.told ? t('photoSub1') : s.sub[lang];
      var nm = typeof s.name === 'string' ? s.name : s.name[lang];
      li.innerHTML = '<span class="subj__kind" aria-hidden="true"></span>' +
                     '<span><span class="subj__name"></span><span class="subj__sub"></span></span>' +
                     '<span class="subj__count"></span>';
      $('.subj__kind', li).textContent = s.kind === 'photo' ? '▣' : '☻';
      $('.subj__name', li).textContent = nm;
      $('.subj__sub', li).textContent = sub;
      subjectsEl.appendChild(li);
    });
  }

  function renderProposals() {
    proposalsEl.innerHTML = '';
    archive.proposals.forEach(function (p) {
      var li = document.createElement('li');
      li.className = 'prop';
      li.setAttribute('data-state', p.state);

      var mark = p.state === 'confirmed' ? '✓' : p.state === 'rejected' ? '×' : '?';
      li.innerHTML =
        '<span class="prop__mark" aria-hidden="true">' + mark + '</span>' +
        '<span class="prop__body"><span class="prop__name"></span>' +
        '<span class="prop__meta"></span></span>';
      $('.prop__name', li).textContent = p.name;
      $('.prop__meta', li).textContent = '"' + p.heard[lang] + '"';

      if (p.state === 'proposed') {
        var acts = document.createElement('span');
        acts.className = 'prop__acts';
        acts.appendChild(actionButton(p, 'no'));
        acts.appendChild(actionButton(p, 'yes'));
        li.appendChild(acts);
      } else {
        var done = document.createElement('span');
        done.className = 'prop__done';
        var v = document.createElement('span');
        v.className = 'prop__verdict';
        v.textContent = p.state === 'confirmed' ? t('confirmedWord') : t('rejectedWord');
        var u = document.createElement('button');
        u.type = 'button'; u.className = 'undo'; u.textContent = t('undo');
        u.setAttribute('aria-label', t('undo') + ': ' + p.name);
        u.addEventListener('click', function () {
          if (p.state === 'confirmed') archive.people -= 1;
          p.state = 'proposed';
          say(t('liveUndo'));
          render();
        });
        done.appendChild(v); done.appendChild(u);
        li.appendChild(done);
      }
      proposalsEl.appendChild(li);
    });
  }

  function actionButton(p, kind) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'act-btn act-btn--' + kind;
    b.innerHTML = kind === 'yes'
      ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 12.5l5.5 5.5L20 6.5"/></svg>'
      : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';
    b.setAttribute('aria-label',
      (kind === 'yes' ? (lang === 'fi' ? 'Vahvista' : 'Confirm') : (lang === 'fi' ? 'Hylkää' : 'Reject')) + ': ' + p.name);
    b.addEventListener('click', function () {
      p.state = kind === 'yes' ? 'confirmed' : 'rejected';
      if (kind === 'yes') archive.people += 1;
      say(p.name + (kind === 'yes' ? t('liveYes') : t('liveNo')));
      render();
    });
    return b;
  }

  function say(msg) { $('#confirm-live').textContent = msg; }

  function renderVerdict() {
    var el = $('#verdict');
    var open = archive.proposals.filter(function (p) { return p.state === 'proposed'; }).length;
    var no = archive.proposals.filter(function (p) { return p.state === 'rejected'; }).length;
    var msg;
    /* Four states, not three. Confirming one of two names and leaving the other
       alone is not the same as rejecting it, and saying "one name was left
       out" there tells the visitor they did something they did not do. */
    if (open === archive.proposals.length) msg = t('vNone');
    else if (open > 0) msg = t('vOpen');
    else if (no > 0) msg = t('vSome');
    else msg = t('vAll');
    if (archive.guest) msg += t('vGuest');
    el.textContent = msg;
  }

  function render() {
    renderTree(); renderArchive(); renderProposals(); renderVerdict(); renderKept();
    /* Everything the surface itself renders, repainted in the language the page
       is being read in. The guard is for the first call, which happens before
       these exist. */
    if (typeof fillPhone === 'function' && $('#props')) {
      fillPhone(); paintHint(); repaintWire(); paintAudio();
    }
  }

  function fmt(s) {
    s = Math.max(0, Math.round(s));
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  }

  /* ------------------------------------------------------------- the peak --
     One rAF loop, reading --sc-p off the act element the engine writes it to. */
  var tellAct = $('#tell');
  var phone = $('#phone'), recTime = $('#rec-time'), recHint = $('#rec-hint');
  var waveEl = $('#wave'), transcriptEl = $('#transcript'), wireCode = $('#wire-code');
  var wireRaw = $('#wire-raw');

  /* Words become real elements so the paragraph still reads as one sentence to
     a screen reader and to anyone whose JS never ran. Both languages are split,
     and the tick drives whichever one is on screen. */
  var wordSets = { fi: splitWords(transcriptEl), en: splitWords($('#transcript-en')) };
  function splitWords(el) {
    var out = [], parts = el.textContent.split(/(\s+)/);
    el.textContent = '';
    parts.forEach(function (part) {
      if (/^\s+$/.test(part)) { el.appendChild(document.createTextNode(part)); return; }
      var w = document.createElement('w');
      w.textContent = part;
      if (reduce) w.classList.add('on');
      el.appendChild(w);
      out.push(w);
    });
    return out;
  }
  function words() { return wordSets[lang]; }

  /* An authored envelope, replaced by the real one if the browser will decode
     the sample for us. Either way it is a waveform, never a claim. */
  var BARS = 44;
  var env = [];
  for (var i = 0; i < BARS; i++) {
    env.push(0.28 + 0.62 * Math.abs(Math.sin(i * 0.7) * Math.cos(i * 0.23) + 0.3 * Math.sin(i * 1.9)));
  }
  var bars = [];
  for (var b2 = 0; b2 < BARS; b2++) {
    var el = document.createElement('i');
    el.style.setProperty('--h', env[b2].toFixed(3));
    waveEl.appendChild(el);
    bars.push(el);
  }

  /* The waveform is the file's own envelope, decoded once per language and
     kept. If a browser will not decode AAC the authored fallback stays and
     nothing on the page claims otherwise. */
  var envCache = {};
  function paintEnvelope(which) {
    if (!envCache[which]) return false;
    envCache[which].forEach(function (v, k) { bars[k].style.setProperty('--h', v.toFixed(3)); });
    return true;
  }
  function loadEnvelope(v) {
    var AC = window.AudioContext || window.webkitAudioContext;
    var which = v.id;
    if (paintEnvelope(which)) return;
    if (!AC || !window.fetch) return;
    fetch(v.src).then(function (r) { return r.arrayBuffer(); })
      .then(function (buf) { return new AC().decodeAudioData(buf); })
      .then(function (audio) {
        var data = audio.getChannelData(0), step = Math.floor(data.length / BARS), peak = 0, out = [];
        for (var k = 0; k < BARS; k++) {
          var m = 0;
          for (var j = k * step; j < (k + 1) * step; j++) { var v = Math.abs(data[j]); if (v > m) m = v; }
          out.push(m); if (m > peak) peak = m;
        }
        if (!peak) return;
        envCache[which] = out.map(function (n) { return Math.max(0.06, n / peak); });
        if (which === currentVoice().id) paintEnvelope(which);
      }).catch(function () { /* the authored envelope stays */ });
  }

  /* The row it writes, line by line, beside the screen that caused it. */
  var WIRE = [
    { at: 0.71, html: '{' },
    { at: 0.72, key: 'body' },
    { at: 0.78, html: '  "mentions": [' },
    { at: 0.79, html: '    { "name": <b>"Aino"</b>, "kind": "person" },' },
    { at: 0.80, html: '    { "name": <b>"Toivo"</b>, "kind": "person" },' },
    { at: 0.81, html: '    { "name": "Puumala", "kind": "place" }' },
    { at: 0.82, html: '  ],' },
    { at: 0.85, html: '  "date": { "start_year": 1950,' },
    { at: 0.86, html: '            "end_year": 1959,' },
    { at: 0.87, html: '            "precision": <i>"decade"</i> },' },
    { at: 0.91, html: '  "questions": [ 3 ]' },
    { at: 0.92, html: '}' },
    { at: 0.94, html: '' },
    { at: 0.95, html: '<s>subject.confirmed = 0  ×2</s>' },
    { at: 0.96, html: '<s>memory.raw_transcript kept</s>' },
    { at: 0.97, html: '<s>memory.audio_r2_key kept</s>' }
  ];
  WIRE.forEach(function (line) {
    var s = document.createElement('span');
    s.style.opacity = reduce ? '1' : '0';
    s.style.transition = 'opacity 220ms var(--sc-ease-out)';
    line.el = s;
    wireCode.appendChild(s);
  });
  function repaintWire() {
    WIRE.forEach(function (line) {
      line.el.innerHTML = (line.key === 'body' ? '  "body": ' + t('wireBody') : line.html) + '\n';
    });
  }

  /* The result assembles: each block has its own threshold. */
  var REVEAL = [
    { sel: '.rowset', at: 0.735 },
    { sel: '#listen', at: 0.79 }, { sel: '.listen__note', at: 0.79 }, { sel: '#voicepick', at: 0.79 },
    { sel: '#props', at: 0.845 }, { sel: '#asks', at: 0.915 }
  ];
  REVEAL.forEach(function (r) {
    r.el = $(r.sel);
    if (!r.el) return;
    /* Under reduced motion the result is simply there once the phase is
       `result`. Staging it in would be the same defect the words and the
       annotation column already avoid, and it left the phone showing a memory
       with no proposals and no questions under it, which is half the argument
       missing rather than a gentler version of it. */
    if (reduce) { r.el.style.opacity = '1'; return; }
    r.el.style.transition = 'opacity 300ms var(--sc-ease-out), transform 300ms var(--sc-ease-out)';
    r.el.style.opacity = '0';
    r.el.style.transform = 'translateY(10px)';
  });

  /* The three proposals inside the phone, and the three questions back. Both
     are drawn from the model above, so the phone and act 4 cannot disagree. */
  /* The phone's proposals and the three questions it asks back, both drawn
     from the model so the phone and act 4 cannot disagree, and both repainted
     when the language changes. */
  function fillPhone() {
    var props = $('#props'), asks = $('#asks');
    $$('.props__row', props).forEach(function (el) { el.remove(); });
    $$('ul', asks).forEach(function (el) { el.remove(); });
    archive.proposals.forEach(function (p) {
      var row = document.createElement('div');
      row.className = 'props__row';
      row.innerHTML = '<span class="props__q" aria-hidden="true">?</span><span class="props__name"></span><span class="props__state"></span>';
      $('.props__name', row).textContent = p.name;
      $('.props__state', row).textContent = t('propState');
      props.appendChild(row);
    });
    var ul = document.createElement('ul');
    t('qs').forEach(function (q) {
      var li = document.createElement('li');
      li.textContent = q;
      ul.appendChild(li);
    });
    asks.appendChild(ul);
  }

  function actP(el) {
    var r = el.getBoundingClientRect();
    if (r.bottom <= 0) return 1;
    if (r.top >= innerHeight) return 0;
    var v = parseFloat(el.style.getPropertyValue('--sc-p'));
    return isNaN(v) ? 0 : Math.min(1, Math.max(0, v));
  }

  var lastPhase = '', toldFired = false;

  function paintHint() {
    var ph = lastPhase || 'idle';   /* before the first tick, the phone is idle */
    recHint.textContent = ph === 'idle' ? t('hintIdle')
      : ph === 'recording' ? t('hintRec')
      : ph === 'working' ? t('hintWork') : '';
  }


  function tick() {
    var p = actP(tellAct);

    var phase = p < 0.08 ? 'idle' : p < 0.56 ? 'recording' : p < 0.70 ? 'working' : 'result';
    if (phase !== lastPhase) {
      phone.setAttribute('data-phase', phase);
      lastPhase = phase;
      paintHint();
    }

    var rp = Math.min(1, Math.max(0, (p - 0.08) / 0.48));
    recTime.textContent = fmt(audioSeconds() * (phase === 'idle' ? 0 : rp));

    for (var i = 0; i < bars.length; i++) {
      var on = phase !== 'idle' && (i / bars.length) <= rp;
      if (on !== bars[i].__on) { bars[i].classList.toggle('on', on); bars[i].__on = on; }
    }
    var shown = words().length;
    if (!reduce) {
      shown = 0;
      var ws = words();
      for (var w = 0; w < ws.length; w++) {
        var vis = rp >= (w + 0.6) / ws.length;
        if (vis) shown = w + 1;
        if (vis !== ws[w].__on) { ws[w].classList.toggle('on', vis); ws[w].__on = vis; }
      }
    }

    /* The verbatim field fills as she speaks, because that is the order it
       happens in: the transcript is stored before anything is asked of a model.
       It is also what stops this column being an empty box for a third of the
       act. */
    var all = words();
    var rawN = phase === 'idle' ? 0 : (phase === 'recording' ? shown : all.length);
    if (rawN !== wireRaw.__n || lang !== wireRaw.__lang) {
      wireRaw.__n = rawN; wireRaw.__lang = lang;
      if (!rawN) {
        wireRaw.textContent = '';
      } else {
        var txt = all.slice(0, rawN).map(function (el) { return el.textContent; }).join(' ');
        wireRaw.textContent = '"' + txt + (rawN < all.length ? '' : '"');
        if (rawN < all.length) {
          var caret = document.createElement('i');
          caret.textContent = '▌';
          wireRaw.appendChild(caret);
        }
      }
    }

    if (!reduce) {
      WIRE.forEach(function (line) {
        var vis = p >= line.at;
        if (vis !== line.__on) { line.el.style.opacity = vis ? '1' : '0'; line.__on = vis; }
      });
    }
    if (!reduce) {
      REVEAL.forEach(function (r) {
        if (!r.el) return;
        var vis = p >= r.at;
        if (vis !== r.__on) {
          r.el.style.opacity = vis ? '1' : '0';
          r.el.style.transform = vis ? 'none' : 'translateY(10px)';
          r.__on = vis;
        }
      });
    }

    /* The archive learns about the memory once the record exists, and the
       minute counter moves by the recording's real length. */
    var told = p >= 0.72;
    if (told !== toldFired) {
      toldFired = told;
      archive.told = told;
      archive.memories = told ? 1 : 0;
      archive.secondsUsed = told ? audioSeconds() : 0;
      render();
    }

    requestAnimationFrame(tick);
  }

  /* ---------------------------------------------------------------- audio -- */
  var audio = $('#audio'), listen = $('#listen');

  /* The sample follows the language, and so does every number that describes
     it. Switching mid-playback stops the old one rather than leaving two
     recordings racing. */
  function paintAudio() {
    var v = currentVoice();
    if (audio.getAttribute('src') !== v.src) {
      if (!audio.paused) audio.pause();
      audio.setAttribute('src', v.src);
    }
    $$('.secs').forEach(function (el) { el.textContent = Math.round(v.seconds) + ' s'; });
    loadEnvelope(v);
    paintVoicePicker();
  }

  /* A page control, not an app one, and it says so by living in the annotation
     register the caption above it already uses. The app has no voice picker;
     this chooses which synthesised sample the page plays. It appears only when
     there is something to choose. */
  function paintVoicePicker() {
    var wrap = $('#voicepick');
    var list = voices();
    wrap.hidden = list.length < 2;
    /* Clearing the markup has to clear the memo with it, or coming back from
       Finnish takes the "already built" path and finds no buttons to update. */
    if (wrap.hidden) { wrap.innerHTML = ''; wrap.__for = null; return; }
    if (wrap.__for === lang) {
      $$('button', wrap).forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-voice') === currentVoice().id));
      });
      $('.voicepick__label', wrap).textContent = t('voiceLabel');
      return;
    }
    wrap.__for = lang;
    wrap.innerHTML = '<span class="voicepick__label"></span>';
    $('.voicepick__label', wrap).textContent = t('voiceLabel');
    list.forEach(function (v) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'voicepick__btn';
      b.setAttribute('data-voice', v.id);
      b.textContent = v.label;
      b.setAttribute('aria-pressed', String(v.id === currentVoice().id));
      b.addEventListener('click', function () {
        if (!audio.paused) audio.pause();
        voiceChoice = v.id;
        try { localStorage.setItem('kinlore.voice', v.id); } catch (e) {}
        paintAudio();
      });
      wrap.appendChild(b);
    });
  }
  listen.addEventListener('click', function () {
    if (audio.paused) { audio.currentTime = 0; audio.play().catch(function () {}); }
    else audio.pause();
  });
  ['play', 'pause', 'ended'].forEach(function (ev) {
    audio.addEventListener(ev, function () { listen.classList.toggle('is-playing', !audio.paused); });
  });

  /* ----------------------------------------------------------- the close --- */
  var form = $('#askform'), input = $('#askname'), kept = $('#kept');

  function renderKept() {
    if (!archive.guest) { kept.hidden = true; return; }
    kept.hidden = false;
    $('#kept-code').innerHTML =
      'subject.kind      = "person"\n' +
      'subject.title     = ' + esc(JSON.stringify(archive.guest)) + '\n' +
      'subject.confirmed = <b>0</b>';
    $('#kept-line').textContent = t('keptLine');
  }
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var v = input.value.trim();
    if (!v) { input.focus(); return; }
    archive.guest = v;              /* stays here. The page has no server. */
    archive.people += 1;
    render();
    $('#kept').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'nearest' });
  });

  /* ----------------------------------------------------------------- boot -- */
  var saved = null;
  try { saved = localStorage.getItem('kinlore.lang'); } catch (e) {}
  /* ?lang=fi and ?lang=en so a link can carry the language it was read in.
     The query wins over a remembered choice, which wins over the default, and
     the default is English. Same order as the head script, which has already
     decided this before the first paint; this call only has to agree with it. */
  var q = (location.search.match(/[?&]lang=(fi|en)\b/) || [])[1];
  setLang(q || saved || 'en');   /* setLang renders */
  if (window.ScrollCraft) ScrollCraft.mount(document.body);
  requestAnimationFrame(tick);
})();
