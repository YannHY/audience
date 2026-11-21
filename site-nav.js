(function() {
    'use strict';

    function normalizePage(pathname) {
        const value = String(pathname || '').trim();
        if (!value) {
            return 'index.html';
        }
        const parts = value.split('/');
        const last = parts[parts.length - 1];
        return last || 'index.html';
    }

    function createIconLink(options) {
        const link = document.createElement('a');
        link.className = 'account-icon-link';
        link.href = options.href;
        link.setAttribute('aria-label', options.label);
        link.setAttribute('title', options.label);
        link.dataset.tooltip = options.label;
        if (options.isCurrent) {
            link.classList.add('is-current');
            link.setAttribute('aria-current', 'page');
        }
        link.innerHTML = `<i class="${options.icon}" aria-hidden="true"></i>`;
        return link;
    }

    function ensureBarStructure() {
        const bar = document.getElementById('accountBar');
        if (!bar) {
            return null;
        }

        let left = bar.querySelector('.account-left');
        if (!left) {
            left = document.createElement('div');
            left.className = 'account-left';
            bar.appendChild(left);
        }

        let right = bar.querySelector('.account-right');
        if (!right) {
            right = document.createElement('div');
            right.className = 'account-right';
            bar.appendChild(right);
        }

        let themeButton = right.querySelector('#themeToggle');
        if (!themeButton) {
            themeButton = document.createElement('button');
            themeButton.type = 'button';
            themeButton.id = 'themeToggle';
            themeButton.className = 'theme-toggle theme-toggle-inline';
            themeButton.setAttribute('aria-label', 'Activer le mode sombre');
            themeButton.setAttribute('title', 'Activer le mode sombre');
            themeButton.innerHTML = '<i class="fa-solid fa-moon" aria-hidden="true"></i>';
            right.replaceChildren(themeButton);
        }

        bar.classList.remove('hidden');

        return { bar, left, right };
    }

    function renderAccountBar(user) {
        const structure = ensureBarStructure();
        if (!structure) {
            return;
        }

        const currentPage = normalizePage(window.location.pathname);
        const links = [
            createIconLink({
                href: 'index.html',
                label: 'Accueil',
                icon: 'fa-solid fa-house',
                isCurrent: currentPage === 'index.html'
            })
        ];
        // Account links sit on the right, just before the theme toggle.
        const accountLinks = [];

        if (user) {
            accountLinks.push(createIconLink({
                href: 'profile.php',
                label: 'Profil',
                icon: 'fa-solid fa-user',
                isCurrent: currentPage === 'profile.php'
            }));

            if (String(user.role || '') === 'admin') {
                accountLinks.push(createIconLink({
                    href: 'admin.php',
                    label: 'Admin',
                    icon: 'fa-solid fa-gear',
                    isCurrent: currentPage === 'admin.php'
                }));
            }

            if (!user.offline) {
                accountLinks.push(createIconLink({
                    href: 'logout.php',
                    label: 'Déconnexion',
                    icon: 'fa-solid fa-door-open',
                    isCurrent: false
                }));
            }
        }

        structure.left.replaceChildren(...links);
        const themeButton = structure.right.querySelector('#themeToggle');
        structure.right.querySelectorAll('.account-icon-link').forEach(function(link) { link.remove(); });
        accountLinks.forEach(function(link) { structure.right.insertBefore(link, themeButton); });
    }

    async function fetchCurrentUser() {
        try {
            const response = await fetch('auth_me.php', {
                credentials: 'same-origin',
                headers: {
                    'Accept': 'application/json'
                }
            });
            if (!response.ok) {
                return null;
            }
            const data = await response.json();
            if (!data || !data.success || !data.user) {
                return null;
            }
            return data.user;
        } catch (_) {
            return null;
        }
    }

    // Shown once per account, until the user accepts the terms of use.
    function showTermsDialog() {
        if (document.getElementById('termsDialog') || typeof HTMLDialogElement !== 'function') {
            return;
        }
        const dialog = document.createElement('dialog');
        dialog.id = 'termsDialog';
        dialog.className = 'terms-dialog';
        dialog.setAttribute('aria-labelledby', 'termsDialogTitle');
        dialog.innerHTML =
            '<form method="dialog" class="terms-dialog-panel">' +
                '<h2 id="termsDialogTitle">Conditions d’utilisation</h2>' +
                '<p>Bienvenue sur Audience ! Avant de commencer, merci de prendre connaissance des conditions d’utilisation. En résumé :</p>' +
                '<ul>' +
                    '<li>le site est fourni « en l’état », sans garantie de disponibilité : exportez régulièrement vos questionnaires ;</li>' +
                    '<li>vous êtes seul(e) responsable des contenus que vous publiez (questions, images, vidéos, liens) et de leur usage ;</li>' +
                    '<li>vous vous engagez à respecter le droit d’auteur, le droit à l’image et les données personnelles de vos participants.</li>' +
                '</ul>' +
                '<p><a href="conditions-utilisation.html" target="_blank" rel="noopener">Lire les conditions d’utilisation complètes</a></p>' +
                '<label class="terms-dialog-check"><input type="checkbox" id="termsDialogCheck"> J’ai lu et j’accepte les conditions d’utilisation</label>' +
                '<p class="terms-dialog-error" id="termsDialogError" role="alert" hidden></p>' +
                '<div class="terms-dialog-actions">' +
                    '<a class="terms-dialog-secondary" href="logout.php">Refuser et se déconnecter</a>' +
                    '<button type="submit" class="terms-dialog-accept" id="termsDialogAccept" disabled>Accepter</button>' +
                '</div>' +
            '</form>';
        document.body.appendChild(dialog);

        const check = dialog.querySelector('#termsDialogCheck');
        const accept = dialog.querySelector('#termsDialogAccept');
        const error = dialog.querySelector('#termsDialogError');
        check.addEventListener('change', function() { accept.disabled = !check.checked; });
        // Escape must not close the dialog: the terms have to be answered. Browsers may
        // ignore preventDefault on "cancel", so a dialog closed without acceptance reopens.
        let accepted = false;
        dialog.addEventListener('cancel', function(event) { event.preventDefault(); });
        dialog.addEventListener('keydown', function(event) {
            if (event.key === 'Escape') { event.preventDefault(); }
        });
        dialog.addEventListener('close', function() {
            if (!accepted && dialog.isConnected) { dialog.showModal(); }
        });
        dialog.querySelector('form').addEventListener('submit', async function(event) {
            event.preventDefault();
            accept.disabled = true;
            error.hidden = true;
            try {
                const response = await fetch('accept_terms.php', {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: { 'Accept': 'application/json' }
                });
                const data = await response.json().catch(function() { return null; });
                if (!response.ok || !data || !data.success) {
                    throw new Error(data && data.error ? data.error : 'Erreur inattendue.');
                }
                accepted = true;
                dialog.close();
                dialog.remove();
            } catch (failure) {
                error.textContent = 'Votre acceptation n’a pas pu être enregistrée. ' + failure.message;
                error.hidden = false;
                accept.disabled = !check.checked;
            }
        });
        dialog.showModal();
    }

    document.addEventListener('DOMContentLoaded', async function() {
        renderAccountBar(null);
        const user = await fetchCurrentUser();
        renderAccountBar(user);
        // The terms page itself stays readable.
        if (user && user.termsAccepted === false && normalizePage(window.location.pathname) !== 'conditions-utilisation.html') {
            showTermsDialog();
        }
    });

    window.addEventListener('audience:user', function(event) {
        const user = event && event.detail ? event.detail.user : null;
        renderAccountBar(user || null);
    });
})();
