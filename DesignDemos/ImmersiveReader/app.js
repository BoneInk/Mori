const shell = document.getElementById('mori-shell');
const reader = document.querySelector('.reader-surface');
const paper = document.getElementById('reader-paper');
const progressBar = document.getElementById('progress-bar');
const panelProgress = document.getElementById('panel-progress');
const popover = document.getElementById('tool-popover');

document.querySelectorAll('[data-mode]').forEach((button) => {
  button.addEventListener('click', () => {
    shell.dataset.mode = button.dataset.mode;
    document.querySelectorAll('[data-mode]').forEach((item) => item.classList.toggle('selected', item === button));
  });
});

document.querySelectorAll('[data-panel-button]').forEach((button) => {
  button.addEventListener('click', () => {
    const panel = button.dataset.panelButton;
    const samePanel = shell.classList.contains('panel-open') && shell.dataset.panel === panel;
    shell.classList.toggle('panel-open', !samePanel);
    shell.dataset.panel = panel;
    document.querySelectorAll('[data-panel-button]').forEach((item) => item.classList.toggle('active', !samePanel && item === button));
    document.querySelectorAll('[data-panel-view]').forEach((view) => view.classList.toggle('active', view.dataset.panelView === panel));
  });
});

document.querySelectorAll('.outline-item').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.outline-item').forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    document.getElementById(button.dataset.target)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
});

function updateProgress() {
  const range = Math.max(1, reader.scrollHeight - reader.clientHeight);
  const value = Math.max(0, Math.min(100, Math.round((reader.scrollTop / range) * 100)));
  progressBar.style.width = `${value}%`;
  panelProgress.textContent = `${value}%`;
}
reader.addEventListener('scroll', updateProgress, { passive: true });

const popoverContent = {
  type: '<div class="popover-title">文字排版</div><div class="popover-row"><span>字号</span><span><button data-font="down">A−</button> <button data-font="up">A＋</button></span></div><div class="popover-row"><span>行距</span><strong>舒适</strong></div>',
  width: '<div class="popover-title">正文栏宽</div><div class="popover-row"><button data-width="compact">窄</button><button data-width="normal">标准</button><button data-width="wide">宽</button></div>',
  theme: '<div class="popover-title">阅读主题</div><div class="popover-row"><button data-theme="paper">纸白</button><button data-theme="sepia">米色</button><button data-theme="night">深色</button></div>',
  export: '<div class="popover-title">导出文档</div><div class="popover-row"><button>HTML</button><button>PDF</button><button>打印</button></div>'
};

document.querySelectorAll('[data-tool]').forEach((button) => {
  button.addEventListener('click', () => {
    const tool = button.dataset.tool;
    if (tool === 'focus') {
      shell.classList.toggle('focus-mode');
      button.classList.toggle('active', shell.classList.contains('focus-mode'));
      popover.hidden = true;
      return;
    }
    const wasOpen = !popover.hidden && button.classList.contains('active');
    document.querySelectorAll('[data-tool]').forEach((item) => { if (item.dataset.tool !== 'focus') item.classList.remove('active'); });
    if (wasOpen) { popover.hidden = true; return; }
    popover.innerHTML = popoverContent[tool] || '';
    const rect = button.getBoundingClientRect();
    popover.style.left = `${rect.left - 222}px`;
    popover.style.top = `${Math.max(75, rect.top - 20)}px`;
    popover.hidden = false;
    button.classList.add('active');
  });
});

popover.addEventListener('click', (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.dataset.width) {
    paper.classList.remove('compact', 'wide');
    if (button.dataset.width !== 'normal') paper.classList.add(button.dataset.width);
  }
  if (button.dataset.theme) {
    shell.classList.remove('sepia', 'night');
    if (button.dataset.theme !== 'paper') shell.classList.add(button.dataset.theme);
  }
  if (button.dataset.font) {
    const current = Number.parseFloat(getComputedStyle(paper).getPropertyValue('--reader-font')) || 15.5;
    paper.style.setProperty('--reader-font', `${Math.max(14, Math.min(20, current + (button.dataset.font === 'up' ? 1 : -1)))}px`);
  }
});

document.addEventListener('click', (event) => {
  if (!event.target.closest('[data-tool]') && !event.target.closest('#tool-popover')) {
    popover.hidden = true;
    document.querySelectorAll('[data-tool]').forEach((item) => { if (item.dataset.tool !== 'focus') item.classList.remove('active'); });
  }
});

updateProgress();
