// Pinned FlutterFire 3.12.0 otherwise injects an inline import bootstrap.
// Keep the strict CSP: import the two modules only after explicit opt-in.
(() => {
  let pending;
  window.schulpilotLoadFirebase = () => {
    if (!pending) {
      pending = (async () => {
        const core = await import('https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js');
        const messaging = await import('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging.js');
        window.firebase_core = core;
        window.firebase_messaging = messaging;
      })().catch(error => { pending = null; throw error; });
    }
    return pending;
  };
})();
