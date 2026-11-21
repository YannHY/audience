/*
 * Pied de page commun à toutes les pages du site.
 * Chaque page contient seulement : <footer class="footer" data-site-footer></footer>
 * Option : data-support="off" masque l'appel aux dons (ex. page participant).
 * Pour modifier le pied de page, c'est ici et nulle part ailleurs.
 */
(function() {
    'use strict';

    const EXTERNAL = 'target="_blank" rel="noopener noreferrer"';

    const LINKS = [
        { href: 'conditions-utilisation.html', label: "Conditions d'utilisation" },
        { href: 'aide.html', label: 'Aide' },
        { href: 'app.html', label: 'Applications' },
        { href: 'https://github.com/YannHY/audience', label: 'Code source', external: true },
        { href: 'contact.html', label: 'Contact' }
    ];

    const SUPPORT_HTML = '' +
        '<div class="footer-support">' +
            '<span>Soutenez <span class="footer-support-brand">Audience</span> en faisant </span>' +
            '<a class="footer-support-link" href="https://paypal.me/yannhoury" ' + EXTERNAL + ' aria-label="Faire un don sur PayPal">' +
                'un don sur <i class="fa-brands fa-paypal" aria-hidden="true"></i>' +
            '</a>' +
            '<span> ou en </span>' +
            '<a class="footer-support-link" href="https://www.buymeacoffee.com/yannhoury" ' + EXTERNAL + ' aria-label="Offrir un café via Buy Me a Coffee">' +
                'm&apos;offrant un <i class="fa-solid fa-mug-hot" aria-hidden="true"></i>' +
            '</a>' +
            '<span>.</span>' +
        '</div>';

    function buildFooterHtml(withSupport) {
        const links = LINKS.map(function(link) {
            return '<a href="' + link.href + '"' + (link.external ? ' ' + EXTERNAL : '') + '>' + link.label + '</a>';
        }).join(' | ');

        return '' +
            '<div class="footer-content">' +
                '<p class="made-with">' +
                    'Créé avec <i class="fas fa-heart" aria-hidden="true"></i> par ' +
                    '<a href="https://www.linkedin.com/in/yann-houry-a2350651/" ' + EXTERNAL + '>Yann Houry</a>' +
                '</p>' +
                '<p class="footer-legal">' + links + '</p>' +
                (withSupport ? SUPPORT_HTML : '') +
                '<div class="license">' +
                    '<p><i class="fa-brands fa-creative-commons" aria-hidden="true"></i> Logiciel libre : code sous ' +
                    '<a href="https://www.gnu.org/licenses/gpl-3.0.fr.html" ' + EXTERNAL + '>GPL v3</a>, contenus sous ' +
                    '<a href="https://creativecommons.org/licenses/by-sa/4.0/deed.fr" ' + EXTERNAL + '>CC BY-SA 4.0</a></p>' +
                '</div>' +
                '<p class="year"><span id="current-year">' + new Date().getFullYear() + '</span></p>' +
            '</div>';
    }

    function renderFooters() {
        document.querySelectorAll('footer[data-site-footer]').forEach(function(footer) {
            if (footer.dataset.rendered === 'true') {
                return;
            }
            footer.innerHTML = buildFooterHtml(footer.dataset.support !== 'off');
            footer.dataset.rendered = 'true';
        });
    }

    renderFooters();
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', renderFooters);
    }
})();
