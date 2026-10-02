// Load after lamp-overlay.js. Native host must set readerUseNativeState=true first.
// Matches PetState Codable fields; no credentials or direct account requests.
(() => {
  window.setReaderPetState = state => {
    if (!window.readerUseNativeState) return false;
    const loading = state?.loading === true;
    const value = !loading && Number.isInteger(state?.remaining)
      && state.remaining >= 0 && state.remaining <= 100 ? state.remaining : null;
    window.setReaderQuota(value);
    const label = document.getElementById('quota-label');
    if (label) label.textContent = loading ? '读取中…' : value === null ? '额度未知'
      : typeof state.label === 'string' && state.label.trim() ? state.label : `剩余额度 ${value}%`;
    return true;
  };
})();
