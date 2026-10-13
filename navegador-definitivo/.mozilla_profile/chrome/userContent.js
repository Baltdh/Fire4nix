
(function() {
    'use strict';
    const VIEWPORT_HEIGHT = window.innerHeight;
    const CULL_THRESHOLD = VIEWPORT_HEIGHT * 2;
    let lastCullTime = 0;
    const CULL_INTERVAL = 5000;
    function cullOffscreenElements() {
        const now = performance.now();
        if (now - lastCullTime < CULL_INTERVAL) return;
        lastCullTime = now;
        try {
            const elements = document.querySelectorAll('div, article, section, li, p, img');
            let culled = 0;
            elements.forEach((el) => {
                if (!el || !el.offsetParent) return;
                const rect = el.getBoundingClientRect();
                if (rect.bottom < -CULL_THRESHOLD || rect.top > VIEWPORT_HEIGHT + CULL_THRESHOLD) {
                    if (!el.dataset.culled) {
                        el.style.display = 'none';
                        el.dataset.culled = 'true';
                        culled++;
                    }
                } else if (el.dataset.culled === 'true') {
                    el.style.display = '';
                    delete el.dataset.culled;
                }
            });
            if (culled > 10) console.log('[Fire4Nix] Culled ' + culled + ' elements');
        } catch (e) {}
    }
    window.addEventListener('scroll', () => { setTimeout(cullOffscreenElements, 100); }, { passive: true });
    setInterval(cullOffscreenElements, CULL_INTERVAL);
})();
