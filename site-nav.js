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

        if (user) {
            links.push(createIconLink({
                href: 'profile.php',
                label: 'Profil',
                icon: 'fa-solid fa-user',
                isCurrent: currentPage === 'profile.php'
            }));

            if (String(user.role || '') === 'admin') {
                links.push(createIconLink({
                    href: 'admin.php',
                    label: 'Admin',
                    icon: 'fa-solid fa-gear',
                    isCurrent: currentPage === 'admin.php'
                }));
            }

            if (!user.offline) {
                links.push(createIconLink({
                    href: 'logout.php',
                    label: 'Déconnexion',
                    icon: 'fa-solid fa-door-open',
                    isCurrent: false
                }));
            }
        }

        structure.left.replaceChildren(...links);
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

    document.addEventListener('DOMContentLoaded', async function() {
        renderAccountBar(null);
        const user = await fetchCurrentUser();
        renderAccountBar(user);
    });

    window.addEventListener('audience:user', function(event) {
        const user = event && event.detail ? event.detail.user : null;
        renderAccountBar(user || null);
    });
})();
