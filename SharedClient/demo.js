(() => {
  const frame = document.querySelector('iframe');
  const fixture = fetch('fixture.json').then(response => {
    if (!response.ok) throw new Error('Fixture unavailable');
    return response.json();
  });
  frame.addEventListener('load', async () => {
    try { frame.contentWindow.gitGazeReceive(await fixture); }
    catch { document.getElementById('notice').textContent = 'Sample data unavailable'; }
  });
  frame.src = 'dashboard.html';
})();
