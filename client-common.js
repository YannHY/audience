(function() {
    'use strict';

    function escapeHtml(value) {
        return String(value ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function decodeHtmlEntities(value) {
        const decoder = document.createElement('textarea');
        decoder.innerHTML = String(value ?? '');
        return decoder.value;
    }

    function decodeHtmlEntitiesDeep(value, maxPasses) {
        const safeMaxPasses = Number.isInteger(maxPasses) && maxPasses > 0 ? maxPasses : 5;
        let current = String(value ?? '');
        for (let index = 0; index < safeMaxPasses; index += 1) {
            const decoded = decodeHtmlEntities(current);
            if (decoded === current) {
                break;
            }
            current = decoded;
        }
        return current;
    }

    function extractQuestionPlainText(value) {
        const withBreaks = String(value ?? '')
            .replace(/<br\s*\/?>/gi, '\n')
            .replace(/<\/(p|div|li|ul|ol)>/gi, '\n');
        const withoutTags = withBreaks.replace(/<[^>]+>/g, '');
        const decoder = document.createElement('textarea');
        decoder.innerHTML = withoutTags;
        return decoder.value
            .replace(/\u00a0/g, ' ')
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
    }

    function sanitizeQuestionRichTextHtml(value) {
        const raw = String(value ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
        if (!raw.trim()) {
            return '';
        }

        if (typeof DOMParser === 'undefined') {
            return escapeHtml(raw).replace(/\n/g, '<br>');
        }

        const source = raw.includes('<')
            ? raw
            : escapeHtml(decodeHtmlEntitiesDeep(raw)).replace(/\n/g, '<br>');
        const doc = new DOMParser().parseFromString(`<body>${source}</body>`, 'text/html');

        const wrapInline = (tagName, html) => {
            const safeHtml = String(html || '');
            if (!extractQuestionPlainText(safeHtml)) {
                return '';
            }
            return `<${tagName}>${safeHtml}</${tagName}>`;
        };

        const applyInlineStyles = (node, html) => {
            let output = String(html || '');
            const style = String(node.getAttribute('style') || '').toLowerCase();
            if (!output) {
                return '';
            }
            if (/font-weight\s*:\s*(bold|[7-9]00)/.test(style)) {
                output = wrapInline('strong', output);
            }
            if (/font-style\s*:\s*italic/.test(style)) {
                output = wrapInline('em', output);
            }
            if (/text-decoration(?:-line)?\s*:\s*[^;]*underline/.test(style)) {
                output = wrapInline('u', output);
            }
            return output;
        };

        const sanitizeNode = (node) => {
            if (!node) {
                return '';
            }
            if (node.nodeType === Node.TEXT_NODE) {
                return escapeHtml(decodeHtmlEntitiesDeep(node.textContent || '')).replace(/\n/g, '<br>');
            }
            if (node.nodeType !== Node.ELEMENT_NODE) {
                return '';
            }

            const tagName = node.tagName.toUpperCase();
            if (tagName === 'SCRIPT' || tagName === 'STYLE' || tagName === 'IFRAME' || tagName === 'OBJECT' || tagName === 'EMBED') {
                return '';
            }

            const html = Array.from(node.childNodes).map(sanitizeNode).join('');
            if (tagName === 'BODY') {
                return html;
            }
            if (tagName === 'STRONG' || tagName === 'B') {
                return wrapInline('strong', html);
            }
            if (tagName === 'EM' || tagName === 'I') {
                return wrapInline('em', html);
            }
            if (tagName === 'U') {
                return wrapInline('u', html);
            }
            if (tagName === 'BR') {
                return '<br>';
            }
            if (tagName === 'LI') {
                if (!extractQuestionPlainText(html)) {
                    return '';
                }
                return `<li>${html}</li>`;
            }
            if (tagName === 'UL' || tagName === 'OL') {
                const items = Array.from(node.children)
                    .filter(child => child.tagName && child.tagName.toUpperCase() === 'LI')
                    .map(sanitizeNode)
                    .join('');
                if (!extractQuestionPlainText(items)) {
                    return '';
                }
                return `<${tagName.toLowerCase()}>${items}</${tagName.toLowerCase()}>`;
            }
            if (tagName === 'P' || tagName === 'DIV') {
                if (!extractQuestionPlainText(html)) {
                    return '';
                }
                if (/<(?:p|ul|ol|li)\b/i.test(html)) {
                    return html;
                }
                return `<p>${html}</p>`;
            }
            if (tagName === 'SPAN' || tagName === 'FONT') {
                return applyInlineStyles(node, html);
            }
            return html;
        };

        return Array.from(doc.body.childNodes)
            .map(sanitizeNode)
            .join('')
            .replace(/(?:<br>\s*){3,}/gi, '<br><br>')
            .trim();
    }

    function normalizeRemoteApiBases(value) {
        if (!Array.isArray(value)) {
            return [];
        }
        return value
            .map(entry => String(entry || '').trim())
            .filter(entry => /^https?:\/\/.+\/$/i.test(entry));
    }

    function buildApiCandidates(path, remoteApiBases) {
        const safePath = String(path || '');
        const bases = normalizeRemoteApiBases(remoteApiBases);
        if (window.location.protocol === 'file:') {
            return bases.map(base => `${base}${safePath}`);
        }
        return [
            new URL(safePath, window.location.href).toString(),
            ...bases.map(base => `${base}${safePath}`)
        ];
    }

    async function fetchApiWithCandidates(path, options, remoteApiBases) {
        const candidates = buildApiCandidates(path, remoteApiBases);
        let lastError;

        for (const url of candidates) {
            try {
                return await fetch(url, options);
            } catch (error) {
                lastError = error;
            }
        }

        throw lastError || new Error('Aucune API disponible');
    }

    window.AudienceClientCommon = {
        escapeHtml,
        decodeHtmlEntitiesDeep,
        extractQuestionPlainText,
        sanitizeQuestionRichTextHtml,
        normalizeRemoteApiBases,
        buildApiCandidates,
        fetchApiWithCandidates
    };
})();

/*
 * Boîtes de dialogue de l'interface (remplacent alert() et confirm()).
 *   AudienceDialog.alert(message | { title, message, tone })            -> Promise<void>
 *   AudienceDialog.confirm({ title, message, confirmLabel, cancelLabel,
 *                            tone: 'danger' | 'primary', icon })      -> Promise<boolean>
 * Les dialogues s'enchaînent si plusieurs sont demandés en même temps.
 * window.alert est redirigé vers AudienceDialog.alert (non bloquant).
 */
(function() {
    'use strict';

    const supportsDialog = typeof window.HTMLDialogElement === 'function';
    const nativeAlert = window.alert.bind(window);
    const nativeConfirm = window.confirm.bind(window);
    let chain = Promise.resolve();
    let idCounter = 0;

    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) {
            node.className = className;
        }
        if (text !== undefined) {
            node.textContent = text;
        }
        return node;
    }

    function show(options) {
        return new Promise(resolve => {
            const isConfirm = options.kind === 'confirm';
            const tone = options.tone === 'danger' ? 'danger' : 'primary';
            const uid = `ui-dialog-${++idCounter}`;

            const dialog = el('dialog', `ui-dialog ui-dialog-${isConfirm ? tone : 'info'}`);
            dialog.setAttribute('aria-describedby', `${uid}-message`);
            const form = el('form', 'ui-dialog-panel');
            form.method = 'dialog';

            const icon = el('span', 'ui-dialog-icon');
            icon.setAttribute('aria-hidden', 'true');
            const iconName = options.icon || (isConfirm ? (tone === 'danger' ? 'fa-trash' : 'fa-circle-question') : 'fa-circle-info');
            icon.appendChild(el('i', `fa-solid ${iconName}`));

            const body = el('div', 'ui-dialog-body');
            if (options.title) {
                const title = el('h2', 'ui-dialog-title', options.title);
                title.id = `${uid}-title`;
                dialog.setAttribute('aria-labelledby', title.id);
                body.appendChild(title);
            } else {
                dialog.setAttribute('aria-label', isConfirm ? 'Confirmation' : 'Information');
            }
            const message = el('p', 'ui-dialog-message', String(options.message ?? ''));
            message.id = `${uid}-message`;
            body.appendChild(message);

            const actions = el('div', 'ui-dialog-actions');
            if (isConfirm) {
                const cancel = el('button', 'ui-dialog-btn', options.cancelLabel || 'Annuler');
                cancel.type = 'submit';
                cancel.value = 'cancel';
                actions.appendChild(cancel);
            }
            const confirm = el('button', `ui-dialog-btn ${isConfirm && tone === 'danger' ? 'is-danger' : 'is-primary'}`, options.confirmLabel || (isConfirm ? 'Confirmer' : 'OK'));
            confirm.type = 'submit';
            confirm.value = 'confirm';
            actions.appendChild(confirm);

            form.append(icon, body, actions);
            dialog.appendChild(form);
            document.body.appendChild(dialog);

            const previousFocus = document.activeElement;
            dialog.addEventListener('click', event => {
                if (event.target === dialog) {
                    dialog.close('cancel');
                }
            });
            dialog.addEventListener('close', () => {
                const accepted = dialog.returnValue === 'confirm';
                dialog.remove();
                if (previousFocus && typeof previousFocus.focus === 'function' && document.contains(previousFocus)) {
                    previousFocus.focus();
                }
                resolve(isConfirm ? accepted : undefined);
            }, { once: true });

            dialog.showModal();
            // Pour une action destructive, le focus va sur « Annuler » par prudence.
            const focusTarget = isConfirm && tone === 'danger' ? actions.querySelector('[value="cancel"]') : confirm;
            focusTarget?.focus();
        });
    }

    function enqueue(options) {
        const run = chain.then(() => show(options));
        chain = run.catch(() => undefined);
        return run;
    }

    function normalize(input, kind) {
        const options = (input && typeof input === 'object') ? { ...input } : { message: input };
        options.kind = kind;
        return options;
    }

    const AudienceDialog = {
        alert(input) {
            const options = normalize(input, 'alert');
            if (!supportsDialog || !document.body) {
                nativeAlert([options.title, options.message].filter(Boolean).join('\n\n'));
                return Promise.resolve();
            }
            return enqueue(options);
        },
        confirm(input) {
            const options = normalize(input, 'confirm');
            if (!supportsDialog || !document.body) {
                return Promise.resolve(nativeConfirm([options.title, options.message].filter(Boolean).join('\n\n')));
            }
            return enqueue(options);
        }
    };

    window.AudienceDialog = AudienceDialog;
    window.alert = function(message) {
        AudienceDialog.alert(message);
    };
})();
