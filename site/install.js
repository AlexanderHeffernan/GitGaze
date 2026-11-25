const copyButton = document.querySelector('#copy-install');
const command = document.querySelector('#install-command');
const status = document.querySelector('#copy-status');
const platforms = document.querySelector('.platforms');
const mac = document.querySelector('#install-mac');
const windows = document.querySelector('#install-windows');

function showPlatform() {
  const isMac = platforms.querySelector(':checked').value === 'mac';
  mac.hidden = !isMac;
  windows.hidden = isMac;
}
platforms.hidden = false;
platforms.addEventListener('change', showPlatform);
showPlatform();

if (navigator.clipboard?.writeText) {
  copyButton.hidden = false;
  copyButton.addEventListener('click', async () => {
    status.textContent = '';
    try {
      await navigator.clipboard.writeText(command.textContent);
      status.textContent = 'Command copied.';
    } catch {
      status.textContent = 'Couldn’t copy. Select the command and copy it manually.';
    }
  });
}
