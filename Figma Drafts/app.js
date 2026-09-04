const root = document.documentElement;
const themeButtons = [...document.querySelectorAll('[data-theme]')];
const chromeButton = document.querySelector('#toggleChrome');

for (const button of themeButtons) {
  button.addEventListener('click', () => {
    root.dataset.theme = button.dataset.theme;
    for (const item of themeButtons) item.classList.toggle('is-active', item === button);
  });
}

chromeButton.addEventListener('click', () => {
  const hidden = document.body.classList.toggle('no-chrome');
  chromeButton.textContent = hidden ? '显示外框' : '隐藏外框';
});
