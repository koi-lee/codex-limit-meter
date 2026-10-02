(() => {
  let remaining = null;
  const normalize = value => typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.min(100, value)) : null;
  const fill = (value, band) => value === null ? 0 : Math.max(0, Math.min(1, value * 3 / 100 - band));
  const surface = (ctx, lamp, lit) => {
    const left = Math.min(...lamp.rows.map(row => row[1]));
    const right = Math.max(...lamp.rows.map(row => row[2]));
    const gradient = ctx.createLinearGradient(left, lamp.top, right, lamp.bottom);
    const colors = !lit ? ['#545d68', '#929aa5', '#666f7b']
      : remaining <= 19 ? ['#a8342c', '#ff6858', '#d83b31']
      : remaining <= 39 ? ['#aa660c', '#ffbc48', '#db8b15']
      : ['#198043', '#55dd85', '#28a75d'];
    gradient.addColorStop(0, colors[0]);
    gradient.addColorStop(.42, colors[1]);
    gradient.addColorStop(1, colors[2]);
    return gradient;
  };
  window.readerLampFill = fill;
  window.setReaderQuota = value => {
    remaining = normalize(value);
    const label = document.getElementById('quota-label');
    if (label) label.textContent = remaining === null ? '模拟额度：未知' : `模拟剩余额度：${remaining}%`;
    window.repaintReader?.();
  };
  window.paintReaderLamps = (ctx, frame) => {
    const lamps = window.readerLampMasks[frame];
    lamps.forEach((lamp, band) => {
      const rows = lamp.rows;
      let available = rows.reduce((sum, row) => sum + row[2] - row[1] + 1, 0) * fill(remaining, band);
      // Cover the entire old lamp first; never retain a baked green perimeter.
      ctx.fillStyle = surface(ctx, lamp, false);
      rows.forEach(([y, left, right]) => ctx.fillRect(left, y, right-left+1, 1));
      ctx.fillStyle = surface(ctx, lamp, true);
      for (let n = rows.length - 1; n >= 0 && available > 0; n--) {
        const [y, left, right] = rows[n];
        const width = right-left+1, height = Math.min(1, available / width);
        ctx.fillRect(left, y+1-height, width, height);
        available -= width * height;
      }
    });
  };
  const selector = document.getElementById('quota-select');
  if (selector) selector.onchange = event => {
    window.setReaderQuota(event.target.value === 'unknown' ? null : Number(event.target.value));
  };
  window.setReaderQuota(window.readerUseNativeState ? null : 36);
})();
