// Apply the design-system theme from the OS appearance and keep it in sync.
// Every Murmur window imports this for side effect; tokens re-theme via the
// `data-theme` attribute on <html> (see styles/colors_and_type.css).
function apply(dark: boolean): void {
  document.documentElement.dataset.theme = dark ? 'dark' : 'light'
}

const mq = window.matchMedia('(prefers-color-scheme: dark)')
apply(mq.matches)
mq.addEventListener('change', (e) => apply(e.matches))
