const app = document.getElementById('mori-window');
const fileToggle = document.getElementById('toggle-files');
const outlineToggle = document.getElementById('toggle-outline');
const sourceScroll = document.getElementById('source-scroll');
const previewScroll = document.getElementById('preview-scroll');

function setToggle(button, hiddenClass) {
  button.addEventListener('click', () => {
    const willHide = !app.classList.contains(hiddenClass);
    app.classList.toggle(hiddenClass, willHide);
    button.classList.toggle('is-active', !willHide);
    button.setAttribute('aria-pressed', String(!willHide));
  });
}

setToggle(fileToggle, 'hide-files');
setToggle(outlineToggle, 'hide-outline');

document.querySelectorAll('[data-mode]').forEach((button) => {
  button.addEventListener('click', () => {
    const mode = button.dataset.mode;
    app.classList.remove('mode-edit', 'mode-reader');
    if (mode !== 'split') app.classList.add(`mode-${mode}`);
    document.querySelectorAll('[data-mode]').forEach((item) => {
      const selected = item === button;
      item.classList.toggle('is-selected', selected);
      item.setAttribute('aria-pressed', String(selected));
    });
  });
});

document.querySelectorAll('[data-folder]').forEach((button) => {
  button.addEventListener('click', () => {
    const children = document.querySelector(`[data-children="${button.dataset.folder}"]`);
    if (!children) return;
    const open = !children.classList.contains('is-open');
    children.classList.toggle('is-open', open);
    button.querySelector('.disclosure')?.classList.toggle('is-open', open);
  });
});

document.querySelectorAll('.file-row').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.file-row').forEach((row) => row.classList.remove('is-selected'));
    button.classList.add('is-selected');
  });
});

document.querySelectorAll('.outline-row').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.outline-row').forEach((row) => row.classList.remove('is-selected'));
    button.classList.add('is-selected');
    const target = button.dataset.target;
    sourceScroll.querySelector(`[data-section="${target}"]`)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    previewScroll.querySelector(`[data-section="${target}"]`)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  });
});

let scrollLock = null;
function syncScroll(source, destination, sourceName) {
  source.addEventListener('scroll', () => {
    if (scrollLock && scrollLock !== sourceName) return;
    scrollLock = sourceName;
    const sourceRange = Math.max(1, source.scrollHeight - source.clientHeight);
    const destinationRange = Math.max(0, destination.scrollHeight - destination.clientHeight);
    destination.scrollTop = (source.scrollTop / sourceRange) * destinationRange;
    window.clearTimeout(syncScroll.releaseTimer);
    syncScroll.releaseTimer = window.setTimeout(() => { scrollLock = null; }, 90);
  }, { passive: true });
}

syncScroll(sourceScroll, previewScroll, 'source');
syncScroll(previewScroll, sourceScroll, 'preview');
