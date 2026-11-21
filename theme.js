const THEME_STORAGE_KEY = 'audience-theme';

function systemPrefersDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function getEffectiveDarkMode() {
    const root = document.documentElement;
    if (root.classList.contains('theme-dark')) {
        return true;
    }
    if (root.classList.contains('theme-light')) {
        return false;
    }
    return systemPrefersDark();
}

function applyThemeFromStorage() {
    const root = document.documentElement;
    try {
        const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);

        root.classList.remove('theme-dark', 'theme-light');

        if (savedTheme === 'dark') {
            root.classList.add('theme-dark');
            return true;
        }

        if (savedTheme === 'light') {
            root.classList.add('theme-light');
            return false;
        }
    } catch (_) {
        root.classList.remove('theme-dark', 'theme-light');
    }

    return systemPrefersDark();
}

function updateThemeToggleLabel(button, isDark) {
    if (!button) {
        return;
    }
    const label = isDark ? 'Activer le mode clair' : 'Activer le mode sombre';
    button.innerHTML = isDark
        ? '<i class="fa-solid fa-sun" aria-hidden="true"></i>'
        : '<i class="fa-solid fa-moon" aria-hidden="true"></i>';
    button.setAttribute('aria-label', label);
    button.setAttribute('title', label);
}

document.addEventListener('DOMContentLoaded', function() {
    const button = document.getElementById('themeToggle');
    const isDark = applyThemeFromStorage();

    updateThemeToggleLabel(button, isDark);

    if (window.matchMedia) {
        const darkMedia = window.matchMedia('(prefers-color-scheme: dark)');
        darkMedia.addEventListener('change', function() {
            const root = document.documentElement;
            if (root.classList.contains('theme-dark') || root.classList.contains('theme-light')) {
                return;
            }
            const autoDark = getEffectiveDarkMode();

            updateThemeToggleLabel(button, autoDark);
        });
    }

    if (!button) {
        return;
    }

    button.addEventListener('click', function() {
        const root = document.documentElement;
        const currentlyDark = getEffectiveDarkMode();
        const nextDark = !currentlyDark;

        button.style.transition = 'transform 0.4s cubic-bezier(0.4, 0, 0.2, 1)';
        button.style.transform = 'rotate(360deg) scale(0.85)';

        setTimeout(function() {
            root.classList.toggle('theme-dark', nextDark);
            root.classList.toggle('theme-light', !nextDark);

            try {
                localStorage.setItem(THEME_STORAGE_KEY, nextDark ? 'dark' : 'light');
            } catch (_) {
                // ignore storage issues
            }


            updateThemeToggleLabel(button, nextDark);

            button.style.transform = 'rotate(0deg) scale(1)';
        }, 200);
    });
});
