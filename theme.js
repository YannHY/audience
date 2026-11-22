const THEME_STORAGE_KEY = 'audience-theme';
let themePreference = null;

function systemPrefersDark() {
    return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
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

function applyDarkMode(isDark) {
    const root = document.documentElement;
    root.classList.toggle('theme-dark', isDark);
    root.classList.toggle('theme-light', !isDark);
    root.style.colorScheme = isDark ? 'dark' : 'light';
}

function applyThemeFromStorage() {
    try {
        const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);
        themePreference = savedTheme === 'dark' || savedTheme === 'light' ? savedTheme : null;
    } catch (_) {
        themePreference = null;
    }

    const isDark = themePreference === null ? systemPrefersDark() : themePreference === 'dark';
    applyDarkMode(isDark);
    return isDark;
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
            // The classes describe the active theme; only a manual choice overrides the system.
            if (themePreference !== null) {
                return;
            }
            const autoDark = darkMedia.matches;
            applyDarkMode(autoDark);

            updateThemeToggleLabel(button, autoDark);
        });
    }

    if (!button) {
        return;
    }

    button.addEventListener('click', function() {
        const currentlyDark = getEffectiveDarkMode();
        const nextDark = !currentlyDark;
        themePreference = nextDark ? 'dark' : 'light';

        button.style.transition = 'transform 0.4s cubic-bezier(0.4, 0, 0.2, 1)';
        button.style.transform = 'rotate(360deg) scale(0.85)';

        setTimeout(function() {
            applyDarkMode(nextDark);

            try {
                localStorage.setItem(THEME_STORAGE_KEY, themePreference);
            } catch (_) {
                // ignore storage issues
            }


            updateThemeToggleLabel(button, nextDark);

            button.style.transform = 'rotate(0deg) scale(1)';
        }, 200);
    });
});
