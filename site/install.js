const copyButton = document.querySelector('#copy-install');
const command = document.querySelector('#install-command');
const status = document.querySelector('#copy-status');

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
