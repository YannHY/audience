const questions = JSON.parse(localStorage.getItem('questions') || '{}');
const responses = JSON.parse(localStorage.getItem('responses') || '{}');
const SESSION_CODE_KEY = 'sessionCode';
const BATCH_STATE_KEY = 'sessionBatchState';
const EDITOR_DRAFT_KEY = 'sessionEditorDraft';
const RESULTS_POLL_INTERVAL_MS = 2000;
const PRESENCE_POLL_INTERVAL_MS = 4000;
const PRESENCE_ACTIVE_WINDOW_SECONDS = 20;
const DEFAULT_QUESTION_TIME_LIMIT_SEC = 30;
const QUESTION_TIME_LIMIT_OPTIONS = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
const MAX_VIDEO_BOUNDARY_SEC = 43200;
const MAX_QUESTION_IMAGE_BYTES = 2 * 1024 * 1024;
const MAX_QUESTION_IMAGE_SOURCE_BYTES = 8 * 1024 * 1024;
const TARGET_QUESTION_IMAGE_BYTES = 700 * 1024;
const MAX_MULTIPLE_ANSWERS = 12;
const ALLOWED_QUESTION_IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);
const LEGEND_MARKER_MIN_PERCENT = 8;
const LEGEND_MARKER_MAX_PERCENT = 92;
const MATH_RENDER_DELIMITERS = [
    { left: '\\(', right: '\\)', display: false },
    { left: '\\[', right: '\\]', display: true }
];
const {
    escapeHtml,
    decodeHtmlEntitiesDeep,
    extractQuestionPlainText,
    sanitizeQuestionRichTextHtml,
    normalizeRemoteApiBases,
    fetchApiWithCandidates
} = window.AudienceClientCommon;

function normalizeOpenResponseFormat(value) {
    return String(value || '').trim().toLowerCase() === 'math' ? 'math' : 'text';
}

function normalizeParticipantResponsesVisibility(value) {
    if (typeof value === 'string') {
        const normalized = value.trim().toLowerCase();
        if (normalized === 'false' || normalized === '0' || normalized === 'non' || normalized === 'no' || normalized === 'masquer' || normalized === 'masquées' || normalized === 'masquees' || normalized === 'cacher' || normalized === 'cachées' || normalized === 'cachees') {
            return false;
        }
        if (normalized === 'true' || normalized === '1' || normalized === 'oui' || normalized === 'yes' || normalized === 'afficher' || normalized === 'visibles') {
            return true;
        }
    }
    return value !== false;
}

function renderMathInElementSafe(element) {
    if (!element || typeof window.renderMathInElement !== 'function') {
        return;
    }
    window.renderMathInElement(element, {
        delimiters: MATH_RENDER_DELIMITERS,
        throwOnError: false,
        strict: 'ignore',
        trust: false
    });
}

function setPlainRichTextContent(element, value) {
    if (!element) {
        return;
    }
    element.innerHTML = escapeHtml(decodeHtmlEntitiesDeep(value)).replace(/\n/g, '<br>');
}

function renderFormattedQuestion(element, value, fallbackText = '') {
    if (!element) {
        return;
    }
    const html = sanitizeQuestionRichTextHtml(value);
    element.innerHTML = html || escapeHtml(fallbackText);
    renderMathInElementSafe(element);
}

function renderMathText(element, value, fallbackText = '') {
    if (!element) {
        return;
    }
    const source = String(value ?? '').trim();
    setPlainRichTextContent(element, source || fallbackText);
    renderMathInElementSafe(element);
}

document.addEventListener('DOMContentLoaded', function() {
    const yearEl = document.getElementById('current-year');
    if (yearEl) {
        yearEl.textContent = String(new Date().getFullYear());
    }

    const REMOTE_API_BASES = normalizeRemoteApiBases(window.AUDIENCE_REMOTE_API_BASES);

    const state = {
        user: null,
        quizTitle: '',
        participantReportEnabled: false,
        requireParticipantName: true,
        code: null,
        runId: null,
        batch: [],
        currentIndex: 0,
        liveActive: false,
        revealCorrectAnswer: false,
        showParticipantResponses: true,
        checkboxResultsMetric: 'count',
        currentResultsQuestionKey: null,
        latestResultsSnapshot: null,
        participantResponsesVisibilityOverrides: {},
        latestQuestionSignature: '',
        lastStatsSignature: null,
        resultsTotalQuestions: 1,
        showingFinalReport: false,
        latestFinalReport: null,
        wordcloudScaleMode: 'compact',
        connectedParticipants: 0
    };
    let resultsPollTimer = null;
    let presencePollTimer = null;
    let lastPresencePollingCode = '';
    let liveQuestionTimer = null;
    let resultsQuestionTimer = null;
    let resultsQuestionTimerKey = '';
    let resultsQuestionTimerOffsetMs = 0;
    let resultsQuestionTimerStartMs = 0;
    let resultsQuestionTimerTotalMs = 0;
    let resultsQuestionTimerPendingTotalMs = 0;
    let codeCopyFeedbackTimer = null;
    let presenterServerOffsetMs = 0;
    let draggedQuestionBlock = null;
    let draftSaveTimer = null;
    let serverDraftSaveTimer = null;
    let isSubmittingBatch = false;
    let questionFormatToolbar = null;
    let activeQuestionEditor = null;
    let pendingMathInsertionTarget = null;
    let siteNoticeTimer = null;

    const questionForm = document.getElementById('questionForm');
    const batchQuestions = document.getElementById('batchQuestions');
    const quizTitleInput = document.getElementById('quizTitleInput');
    const participantReportEnabledInput = document.getElementById('participantReportEnabledInput');
    const requireParticipantNameInput = document.getElementById('requireParticipantNameInput');
    const addQuestionBtn = document.getElementById('addQuestionBtn');
    const createSuccess = document.getElementById('createSuccess');
    const createTabTitle = document.getElementById('createTabTitle');
    const homePanel = document.getElementById('homePanel');
    const editorPanel = document.getElementById('editorPanel');
    const backHomeBtn = document.getElementById('backHomeBtn');
    const startNewQuizBtn = document.getElementById('startNewQuizBtn');
    const tabsNav = document.querySelector('.tabs-nav');
    const savedQuizzesPanel = document.getElementById('savedQuizzesPanel');
    const savedQuizCards = document.getElementById('savedQuizCards');
    const importQuizMdBtn = document.getElementById('importQuizMdBtn');
    const importQuizMdInput = document.getElementById('importQuizMdInput');
    const importMarkdownModal = document.getElementById('importMarkdownModal');
    const importMarkdownTextarea = document.getElementById('importMarkdownTextarea');
    const importMarkdownApplyBtn = document.getElementById('importMarkdownApplyBtn');
    const importMarkdownCancelBtn = document.getElementById('importMarkdownCancelBtn');
    const importMarkdownCloseBtn = document.getElementById('importMarkdownCloseBtn');
    const importMarkdownFileBtn = document.getElementById('importMarkdownFileBtn');
    const siteNotice = document.getElementById('siteNotice');
    const trashQuizzesPanel = document.getElementById('trashQuizzesPanel');
    const trashQuizSelect = document.getElementById('trashQuizSelect');
    const restoreTrashQuizBtn = document.getElementById('restoreTrashQuizBtn');
    const purgeTrashQuizBtn = document.getElementById('purgeTrashQuizBtn');
    const mathInsertModal = document.getElementById('mathInsertModal');
    const mathInsertField = document.getElementById('mathInsertField');
    const mathInsertPreview = document.getElementById('mathInsertPreview');
    const mathInsertApplyBtn = document.getElementById('mathInsertApplyBtn');
    const mathInsertCancelBtn = document.getElementById('mathInsertCancelBtn');
    const mathInsertCloseBtn = document.getElementById('mathInsertCloseBtn');
    const WORD_STOP_WORDS = new Set([
        'a', 'ai', 'as', 'au', 'aux', 'avec', 'ce', 'ces', 'dans', 'de', 'des', 'du', 'elle', 'en', 'et',
        'eux', 'il', 'ils', 'je', 'la', 'le', 'les', 'leur', 'lui', 'ma', 'mais', 'me', 'meme', 'mes',
        'moi', 'mon', 'ne', 'nos', 'notre', 'nous', 'on', 'ou', 'par', 'pas', 'pour', 'qu', 'que', 'qui',
        'sa', 'se', 'ses', 'son', 'sur', 'ta', 'te', 'tes', 'toi', 'ton', 'tu', 'un', 'une', 'vos', 'votre',
        'vous', 'cest', 'est', 'sont', 'etre', 'ete'
    ]);

    function configureMathFieldUi(field, options = {}) {
        if (!field) {
            return;
        }
        const {
            policy = 'manual',
            ariaLabel = 'Éditeur de formule'
        } = options;

        field.setAttribute('lang', 'fr');
        field.setAttribute('aria-label', ariaLabel);
        field.setAttribute('math-virtual-keyboard-policy', policy);

        if (window.MathfieldElement) {
            try {
                window.MathfieldElement.locale = 'fr';
            } catch (_) {}
        }
        if (typeof field.setOptions === 'function') {
            try {
                field.setOptions({ locale: 'fr' });
            } catch (_) {}
        }
    }

    if (questionForm) {
        // Validation native désactivée: les champs dynamiques cachés peuvent bloquer la soumission
        // avec "An invalid form control ... is not focusable".
        questionForm.setAttribute('novalidate', 'novalidate');
    }

    configureMathFieldUi(mathInsertField, {
        policy: 'manual',
        ariaLabel: 'Saisie de formule'
    });
    mathInsertField?.addEventListener('input', updateMathInsertPreview);
    mathInsertApplyBtn?.addEventListener('click', applyMathInsertion);
    mathInsertCancelBtn?.addEventListener('click', closeMathInsertModal);
    mathInsertCloseBtn?.addEventListener('click', closeMathInsertModal);
    importMarkdownApplyBtn?.addEventListener('click', handlePastedMarkdownImport);
    importMarkdownCancelBtn?.addEventListener('click', closeImportMarkdownModal);
    importMarkdownCloseBtn?.addEventListener('click', closeImportMarkdownModal);
    importMarkdownFileBtn?.addEventListener('click', function() {
        importQuizMdInput?.click();
    });
    importMarkdownModal?.addEventListener('click', function(event) {
        const trigger = event.target.closest('[data-action="close-import-modal"]');
        if (trigger) {
            closeImportMarkdownModal();
        }
    });

    document.addEventListener('selectionchange', function() {
        if (!activeQuestionEditor) {
            return;
        }
        window.requestAnimationFrame(refreshQuestionFormatToolbar);
    });

    document.addEventListener('mousedown', function(event) {
        const target = event.target;
        if ((questionFormatToolbar && questionFormatToolbar.contains(target)) || (activeQuestionEditor && activeQuestionEditor.contains(target))) {
            return;
        }
        hideQuestionFormatToolbar();
        activeQuestionEditor = null;
    });

    window.addEventListener('resize', hideQuestionFormatToolbar);
    window.addEventListener('scroll', hideQuestionFormatToolbar, true);
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape' && importMarkdownModal && !importMarkdownModal.classList.contains('hidden')) {
            event.preventDefault();
            closeImportMarkdownModal();
            return;
        }
        if (event.key === 'Escape' && mathInsertModal && !mathInsertModal.classList.contains('hidden')) {
            event.preventDefault();
            closeMathInsertModal();
        }
    });

    function openImportMarkdownModal() {
        if (!importMarkdownModal) {
            return;
        }
        importMarkdownModal.classList.remove('hidden');
        importMarkdownModal.setAttribute('aria-hidden', 'false');
        window.setTimeout(() => {
            importMarkdownTextarea?.focus();
        }, 0);
    }

    function closeImportMarkdownModal() {
        if (!importMarkdownModal) {
            return;
        }
        importMarkdownModal.classList.add('hidden');
        importMarkdownModal.setAttribute('aria-hidden', 'true');
    }

    function showSiteNotice(message, type = 'success') {
        if (!siteNotice) {
            return;
        }
        siteNotice.textContent = String(message || '').trim();
        siteNotice.classList.remove('hidden', 'is-success', 'is-error');
        siteNotice.classList.add(type === 'error' ? 'is-error' : 'is-success');
        if (siteNoticeTimer) {
            clearTimeout(siteNoticeTimer);
        }
        siteNoticeTimer = window.setTimeout(() => {
            siteNotice.classList.add('hidden');
            siteNotice.classList.remove('is-success', 'is-error');
            siteNoticeTimer = null;
        }, 3200);
    }

    function normalizeRequireParticipantName(value) {
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            if (['false', '0', 'non', 'no', 'off', 'disabled', 'desactive', 'desactivee', 'désactivé', 'désactivée', 'optionnel', 'anonyme'].includes(normalized)) {
                return false;
            }
            if (['true', '1', 'oui', 'yes', 'on', 'active', 'activee', 'activé', 'activée', 'requis', 'obligatoire'].includes(normalized)) {
                return true;
            }
        }
        if (value === false || value === 0 || value === '0') {
            return false;
        }
        return value !== false;
    }

    function normalizeParticipantReportEnabled(value) {
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            if (['false', '0', 'non', 'no', 'off', 'disabled', 'desactive', 'desactivee', 'désactivé', 'désactivée'].includes(normalized)) {
                return false;
            }
            if (['true', '1', 'oui', 'yes', 'on', 'active', 'activee', 'activé', 'activée'].includes(normalized)) {
                return true;
            }
        }
        return value === true || value === 1 || value === '1';
    }

    function applyImportedMarkdown(markdown) {
        const parsed = parseQuizMarkdown(markdown);

        state.code = null;
        state.runId = null;
        state.quizTitle = parsed.quizTitle;
        state.participantReportEnabled = normalizeParticipantReportEnabled(parsed.participantReportEnabled);
        state.requireParticipantName = normalizeRequireParticipantName(parsed.requireParticipantName);
        state.batch = normalizeBatchQuestionTiming(parsed.batch);
        state.currentIndex = 0;
        state.liveActive = false;
        state.revealCorrectAnswer = false;
        state.showParticipantResponses = true;
        state.participantResponsesVisibilityOverrides = {};
        state.latestQuestionSignature = '';

        localStorage.removeItem(SESSION_CODE_KEY);
        localStorage.removeItem(BATCH_STATE_KEY);
        clearEditorDraft();

        renderBatchEditor(state.batch);
        if (quizTitleInput) {
            quizTitleInput.value = state.quizTitle;
        }
        if (participantReportEnabledInput) {
            participantReportEnabledInput.checked = state.participantReportEnabled;
        }
        if (requireParticipantNameInput) {
            requireParticipantNameInput.checked = state.requireParticipantName;
        }
        showBuilderView();
        return parsed;
    }

    function handlePastedMarkdownImport() {
        const markdown = String(importMarkdownTextarea?.value || '').trim();
        if (!markdown) {
            showSiteNotice('Collez un questionnaire en Markdown avant de lancer l’import.', 'error');
            return;
        }

        try {
            const parsed = applyImportedMarkdown(markdown);
            closeImportMarkdownModal();
            if (importMarkdownTextarea) {
                importMarkdownTextarea.value = '';
            }
            showSiteNotice(`Import réussi : ${parsed.batch.length} question(s) chargée(s).`, 'success');
        } catch (error) {
            showSiteNotice(error.message || 'Import impossible.', 'error');
        }
    }

    function normalizeQuestionType(type) {
        const raw = String(type ?? '').trim().toLowerCase();
        if (raw === 'open' || raw.includes('ouverte') || raw.includes('open')) {
            return 'open';
        }
        if (raw === 'wordcloud' || raw.includes('nuage')) {
            return 'wordcloud';
        }
        if (raw === 'rating' || raw.includes('notation') || raw.includes('etoile') || raw.includes('étoile')) {
            return 'rating';
        }
        if (raw === 'cloze' || raw.includes('trou')) {
            return 'cloze';
        }
        if (raw === 'video' || raw.includes('vidéo') || raw.includes('video') || raw.includes('youtube')) {
            return 'video';
        }
        if (raw === 'ranking' || raw === 'rank' || raw.includes('classement') || raw.includes('classer') || raw.includes('ordre')) {
            return 'ranking';
        }
        if (raw === 'labelimage' || raw.includes('legender') || raw.includes('légender') || raw.includes('étiquette') || raw.includes('etiquette')) {
            return 'labelimage';
        }
        if (raw === 'checkbox' || raw.includes('checkbox') || raw.includes('cases a cocher') || raw.includes('cases à cocher') || raw.includes('case a cocher') || raw.includes('case à cocher') || raw.includes('cocher')) {
            return 'checkbox';
        }
        return 'multiple';
    }

    function isChoiceQuestionType(type) {
        const normalizedType = normalizeQuestionType(type);
        return normalizedType === 'multiple' || normalizedType === 'checkbox';
    }

    function isSingleChoiceQuestionType(type) {
        return normalizeQuestionType(type) === 'multiple';
    }

    function getOpenQuestionHelpText(type) {
        if (type === 'wordcloud') {
            return "L'audience enverra un mot ou une courte expression. Un nuage sera généré.";
        }
        if (type === 'rating') {
            return "L'audience notera cette question de 1 à 5 étoiles.";
        }
        if (type === 'cloze') {
            return "L'audience complétera le texte à trous en envoyant une réponse libre.";
        }
        if (type === 'video') {
            return "L'audience verra une vidéo YouTube. Aucune réponse ne sera demandée.";
        }
        if (type === 'ranking') {
            return "L'audience devra classer les éléments dans le bon ordre par glisser-déposer.";
        }
        if (type === 'labelimage') {
            return '';
        }
        return "L'audience enverra une réponse libre en texte.";
    }

    function parseRankingLines(rawText) {
        return String(rawText || '')
            .split('\n')
            .map(line => line.trim())
            .filter(Boolean);
    }

    function parseLegendLabelsMarkdown(rawText) {
        const source = String(rawText || '').trim();
        if (!source) {
            return [];
        }

        const parseCoordinate = (value) => {
            if (value === null || value === undefined) {
                return null;
            }
            const raw = String(value).trim();
            if (!raw) {
                return null;
            }
            const numeric = Number(raw.replace(',', '.'));
            return Number.isFinite(numeric) ? numeric : null;
        };

        const parseAsJson = () => {
            try {
                const parsed = JSON.parse(source);
                const entries = Array.isArray(parsed)
                    ? parsed
                    : (parsed && Array.isArray(parsed.labels) ? parsed.labels : []);
                return entries.map((entry, index) => {
                    if (entry && typeof entry === 'object') {
                        return {
                            id: String(entry.id || `lbl${index + 1}`),
                            text: String(entry.text || ''),
                            x: parseCoordinate(entry.x),
                            y: parseCoordinate(entry.y)
                        };
                    }
                    if (Array.isArray(entry)) {
                        return {
                            id: String(entry[0] || `lbl${index + 1}`),
                            text: String(entry[1] || ''),
                            x: parseCoordinate(entry[2]),
                            y: parseCoordinate(entry[3])
                        };
                    }
                    return {
                        id: `lbl${index + 1}`,
                        text: String(entry || ''),
                        x: null,
                        y: null
                    };
                });
            } catch (_) {
                return null;
            }
        };

        if (source.startsWith('[') || source.startsWith('{')) {
            const jsonLabels = parseAsJson();
            if (jsonLabels) {
                return normalizeLegendLabels(jsonLabels);
            }
        }

        const labels = source
            .split('\n')
            .map(line => line.trim())
            .filter(Boolean)
            .map((line, index) => {
                const cleanLine = line.replace(/^-\s+/, '');
                const parts = cleanLine.split('|').map(part => part.trim());
                if (parts.length >= 4) {
                    return {
                        id: parts[0] || `lbl${index + 1}`,
                        text: parts[1] || '',
                        x: parseCoordinate(parts[2]),
                        y: parseCoordinate(parts[3])
                    };
                }
                if (parts.length >= 3) {
                    return {
                        id: `lbl${index + 1}`,
                        text: parts[0] || '',
                        x: parseCoordinate(parts[1]),
                        y: parseCoordinate(parts[2])
                    };
                }
                return {
                    id: `lbl${index + 1}`,
                    text: cleanLine,
                    x: null,
                    y: null
                };
            });

        return normalizeLegendLabels(labels);
    }

    function secureRandomInt(maxExclusive) {
        const max = Number.isInteger(maxExclusive) && maxExclusive > 0 ? maxExclusive : 1;
        if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
            const arr = new Uint32Array(1);
            window.crypto.getRandomValues(arr);
            return arr[0] % max;
        }
        return Math.floor(Math.random() * max);
    }

    function secureRandomToken(length = 8) {
        const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        let out = '';
        for (let i = 0; i < length; i += 1) {
            out += chars.charAt(secureRandomInt(chars.length));
        }
        return out;
    }

    function getOrCreateVoteToken() {
        const key = 'audience-vote-token';
        try {
            const existing = String(localStorage.getItem(key) || '').trim();
            if (/^[a-zA-Z0-9_-]{16,120}$/.test(existing)) {
                return existing;
            }
        } catch (_) {}

        const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
        let token = '';
        const length = 32;
        if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
            const bytes = new Uint8Array(length);
            window.crypto.getRandomValues(bytes);
            for (let i = 0; i < bytes.length; i += 1) {
                token += alphabet.charAt(bytes[i] % alphabet.length);
            }
        } else {
            for (let i = 0; i < length; i += 1) {
                token += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
            }
        }

        try {
            localStorage.setItem(key, token);
        } catch (_) {}
        return token;
    }

    function generateRunId() {
        return `run_${Date.now()}_${secureRandomToken(8)}`;
    }

    function normalizeQuestionTimeLimit(value) {
        const seconds = Number.isFinite(Number(value)) ? Math.trunc(Number(value)) : DEFAULT_QUESTION_TIME_LIMIT_SEC;
        if (QUESTION_TIME_LIMIT_OPTIONS.includes(seconds)) {
            return seconds;
        }
        return DEFAULT_QUESTION_TIME_LIMIT_SEC;
    }

    function normalizeQuestionStartedAtMs(value) {
        const startedAt = Number(value);
        if (!Number.isFinite(startedAt) || startedAt <= 0) {
            return null;
        }
        return Math.trunc(startedAt);
    }

    function normalizeVideoBoundarySec(value) {
        if (value === null || value === undefined) {
            return null;
        }
        const raw = String(value).trim();
        if (!raw) {
            return null;
        }
        let seconds = null;
        const colonMatch = raw.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/);
        if (colonMatch) {
            const first = Number(colonMatch[1]);
            const second = Number(colonMatch[2]);
            const third = colonMatch[3] !== undefined ? Number(colonMatch[3]) : null;
            if (third === null) {
                if (!Number.isInteger(first) || !Number.isInteger(second) || second > 59) {
                    return null;
                }
                seconds = (first * 60) + second;
            } else {
                if (!Number.isInteger(first) || !Number.isInteger(second) || !Number.isInteger(third) || second > 59 || third > 59) {
                    return null;
                }
                seconds = (first * 3600) + (second * 60) + third;
            }
        } else {
            const dotAsColon = raw.match(/^(\d+)[\.,](\d{1,2})$/);
            if (dotAsColon) {
                const minutes = Number(dotAsColon[1]);
                const secs = Number(dotAsColon[2]);
                if (!Number.isInteger(minutes) || !Number.isInteger(secs) || secs > 59) {
                    return null;
                }
                seconds = (minutes * 60) + secs;
            } else {
                const numeric = Number(raw);
                if (!Number.isFinite(numeric)) {
                    return null;
                }
                seconds = Math.trunc(numeric);
            }
        }

        if (seconds < 0) {
            return null;
        }
        return Math.min(MAX_VIDEO_BOUNDARY_SEC, seconds);
    }

    function normalizeVideoRange(startValue, endValue) {
        let startSec = normalizeVideoBoundarySec(startValue);
        let endSec = normalizeVideoBoundarySec(endValue);
        if (startSec !== null && startSec <= 0) {
            startSec = null;
        }
        if (endSec !== null && endSec <= 0) {
            endSec = null;
        }
        if (startSec !== null && endSec !== null && endSec <= startSec) {
            endSec = null;
        }
        return { startSec, endSec };
    }

    function formatVideoBoundaryLabel(value) {
        const seconds = normalizeVideoBoundarySec(value);
        if (seconds === null) {
            return '';
        }
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        if (hours > 0) {
            return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
        }
        return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    function formatVideoBoundaryInput(value) {
        const seconds = normalizeVideoBoundarySec(value);
        if (seconds === null) {
            return '';
        }
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        if (hours > 0) {
            return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
        }
        return `${minutes}:${String(secs).padStart(2, '0')}`;
    }

    function describeVideoRange(startValue, endValue) {
        const range = normalizeVideoRange(startValue, endValue);
        if (range.startSec === null && range.endSec === null) {
            return '';
        }
        const from = range.startSec !== null ? formatVideoBoundaryLabel(range.startSec) : '00:00';
        if (range.endSec !== null) {
            return `Lecture de ${from} à ${formatVideoBoundaryLabel(range.endSec)}`;
        }
        return `Lecture à partir de ${from}`;
    }

    function normalizeBatchQuestionTiming(batch, currentIndex = null, currentStartedAtMs = null) {
        if (!Array.isArray(batch)) {
            return [];
        }
        const normalized = batch.map((item, index) => {
            const source = item && typeof item === 'object' ? item : {};
            const out = {
                ...source,
                timeLimitSec: normalizeQuestionTimeLimit(source.timeLimitSec),
                participantResponsesVisible: normalizeParticipantResponsesVisibility(
                    Object.prototype.hasOwnProperty.call(source, 'participantResponsesVisible')
                        ? source.participantResponsesVisible
                        : source.showParticipantResponses
                )
            };
            const sourceType = normalizeQuestionType(source.type);
            const videoRange = sourceType === 'video'
                ? normalizeVideoRange(source.videoStartSec, source.videoEndSec)
                : { startSec: null, endSec: null };
            out.videoStartSec = videoRange.startSec;
            out.videoEndSec = videoRange.endSec;
            if (Object.prototype.hasOwnProperty.call(source, 'questionStartedAtMs')) {
                out.questionStartedAtMs = normalizeQuestionStartedAtMs(source.questionStartedAtMs);
            } else {
                out.questionStartedAtMs = null;
            }
            if (Number.isInteger(currentIndex) && index === currentIndex) {
                out.questionStartedAtMs = normalizeQuestionStartedAtMs(currentStartedAtMs);
            }
            return out;
        });
        return normalized;
    }

    function formatTimerValue(totalSeconds) {
        const safeSeconds = Math.max(0, Math.trunc(totalSeconds));
        const minutes = Math.floor(safeSeconds / 60);
        const seconds = safeSeconds % 60;
        return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }

    function stopLiveQuestionTimer() {
        if (liveQuestionTimer) {
            cancelAnimationFrame(liveQuestionTimer);
            liveQuestionTimer = null;
        }
    }

    function updateLiveQuestionTimerWidget(remainingMs, totalMs, expired, options = {}) {
        const timerEl = document.getElementById('createdQuestionTimer');
        const valueEl = document.getElementById('createdQuestionTimerValue');
        const barEl = document.getElementById('createdQuestionTimerBar');
        if (!timerEl || !valueEl || !barEl) {
            return;
        }
        const labelEl = timerEl.querySelector('.question-timer-label');
        const mode = options.mode === 'pending' ? 'pending' : 'running';
        if (mode === 'pending') {
            const pendingMs = Math.max(0, Number(options.pendingMs || 0));
            const pendingTotalMs = Math.max(1000, Number(options.pendingTotalMs || pendingMs || 1000));
            const pendingRatio = Math.max(0, Math.min(1, pendingMs / pendingTotalMs));
            if (labelEl) {
                labelEl.textContent = 'Démarrage dans';
            }
            valueEl.textContent = formatTimerValue(Math.ceil(pendingMs / 1000));
            barEl.style.width = `${(pendingRatio * 100).toFixed(3)}%`;
            timerEl.classList.toggle('is-warning', pendingMs > 0 && pendingMs <= 1500);
            timerEl.classList.remove('is-expired');
            return;
        }
        const safeTotal = Math.max(1000, Number(totalMs || 0));
        const safeRemaining = Math.max(0, Number(remainingMs || 0));
        const ratio = Math.max(0, Math.min(1, safeRemaining / safeTotal));
        if (labelEl) {
            labelEl.textContent = 'Temps restant';
        }
        valueEl.textContent = formatTimerValue(Math.ceil(safeRemaining / 1000));
        barEl.style.width = `${(ratio * 100).toFixed(3)}%`;
        timerEl.classList.toggle('is-warning', !expired && ratio <= 0.25);
        timerEl.classList.toggle('is-expired', !!expired);
    }

    function refreshLiveQuestionTimer() {
        const timerEl = document.getElementById('createdQuestionTimer');
        if (!timerEl) {
            return;
        }
        if (!Array.isArray(state.batch) || state.batch.length === 0) {
            timerEl.classList.add('hidden');
            stopLiveQuestionTimer();
            return;
        }
        const activeQuestion = state.batch[state.currentIndex];
        const activeType = normalizeQuestionType(activeQuestion?.type);
        if (activeType === 'video') {
            timerEl.classList.add('hidden');
            stopLiveQuestionTimer();
            return;
        }
        const timeLimitSec = normalizeQuestionTimeLimit(activeQuestion?.timeLimitSec);
        const startedAtMs = normalizeQuestionStartedAtMs(activeQuestion?.questionStartedAtMs);
        if (!state.liveActive || !startedAtMs) {
            timerEl.classList.add('hidden');
            stopLiveQuestionTimer();
            return;
        }

        const totalMs = timeLimitSec * 1000;
        const setupNowMs = Date.now() + presenterServerOffsetMs;
        const initialPendingMs = Math.max(0, startedAtMs - setupNowMs);
        const pendingTotalMs = initialPendingMs > 0 ? Math.max(1000, initialPendingMs) : 0;
        timerEl.classList.remove('hidden');
        stopLiveQuestionTimer();

        const render = () => {
            const nowMs = Date.now() + presenterServerOffsetMs;
            const pendingMs = startedAtMs - nowMs;
            if (pendingMs > 0) {
                updateLiveQuestionTimerWidget(totalMs, totalMs, false, {
                    mode: 'pending',
                    pendingMs,
                    pendingTotalMs: pendingTotalMs || pendingMs
                });
                liveQuestionTimer = requestAnimationFrame(render);
                return;
            }
            const remainingMs = Math.max(0, (startedAtMs + totalMs) - nowMs);
            const isExpired = remainingMs <= 0;
            updateLiveQuestionTimerWidget(remainingMs, totalMs, isExpired);
            if (isExpired) {
                stopLiveQuestionTimer();
                return;
            }
            liveQuestionTimer = requestAnimationFrame(render);
        };

        render();
    }

    function stopResultsQuestionTimer() {
        if (resultsQuestionTimer) {
            cancelAnimationFrame(resultsQuestionTimer);
            resultsQuestionTimer = null;
        }
        resultsQuestionTimerKey = '';
        resultsQuestionTimerOffsetMs = 0;
        resultsQuestionTimerStartMs = 0;
        resultsQuestionTimerTotalMs = 0;
        resultsQuestionTimerPendingTotalMs = 0;
    }

    function startResultsQuestionTimer(timeLimitSec, startedAtMs, serverNowMs) {
        const timerEl = document.getElementById('resultsQuestionTimer');
        const valueEl = document.getElementById('resultsQuestionTimerValue');
        const barEl = document.getElementById('resultsQuestionTimerBar');
        if (!timerEl || !valueEl || !barEl) {
            return;
        }

        const safeLimitSec = normalizeQuestionTimeLimit(timeLimitSec);
        const safeStartedAtMs = normalizeQuestionStartedAtMs(startedAtMs);
        const safeServerNowMs = Number(serverNowMs);
        if (!safeStartedAtMs || state.showingFinalReport) {
            timerEl.classList.add('hidden');
            stopResultsQuestionTimer();
            return;
        }

        const totalMs = safeLimitSec * 1000;
        const offsetMs = Number.isFinite(safeServerNowMs) ? (safeServerNowMs - Date.now()) : 0;
        const timerKey = `${safeLimitSec}|${safeStartedAtMs}`;
        if (resultsQuestionTimer && resultsQuestionTimerKey === timerKey) {
            // Même question/même départ: on ajuste seulement l'offset serveur, sans relancer visuellement le timer.
            resultsQuestionTimerOffsetMs = offsetMs;
            return;
        }

        resultsQuestionTimerKey = timerKey;
        resultsQuestionTimerOffsetMs = offsetMs;
        resultsQuestionTimerStartMs = safeStartedAtMs;
        resultsQuestionTimerTotalMs = totalMs;

        const setupNowMs = Date.now() + resultsQuestionTimerOffsetMs;
        const initialPendingMs = Math.max(0, safeStartedAtMs - setupNowMs);
        resultsQuestionTimerPendingTotalMs = initialPendingMs > 0 ? Math.max(1000, initialPendingMs) : 0;
        const labelEl = timerEl.querySelector('.question-timer-label');
        timerEl.classList.remove('hidden');
        stopResultsQuestionTimer();
        resultsQuestionTimerKey = timerKey;
        resultsQuestionTimerOffsetMs = offsetMs;
        resultsQuestionTimerStartMs = safeStartedAtMs;
        resultsQuestionTimerTotalMs = totalMs;
        resultsQuestionTimerPendingTotalMs = initialPendingMs > 0 ? Math.max(1000, initialPendingMs) : 0;

        const tick = () => {
            const nowMs = Date.now() + resultsQuestionTimerOffsetMs;
            const pendingMs = resultsQuestionTimerStartMs - nowMs;
            if (pendingMs > 0) {
                if (labelEl) {
                    labelEl.textContent = 'Temps restant';
                }
                valueEl.textContent = formatTimerValue(Math.ceil(resultsQuestionTimerTotalMs / 1000));
                barEl.style.width = '100%';
                timerEl.classList.remove('is-warning');
                timerEl.classList.remove('is-expired');
                resultsQuestionTimer = requestAnimationFrame(tick);
                return;
            }
            const remainingMs = Math.max(0, (resultsQuestionTimerStartMs + resultsQuestionTimerTotalMs) - nowMs);
            const ratio = Math.max(0, Math.min(1, remainingMs / Math.max(resultsQuestionTimerTotalMs, 1000)));
            if (labelEl) {
                labelEl.textContent = 'Temps restant';
            }
            valueEl.textContent = formatTimerValue(Math.ceil(remainingMs / 1000));
            barEl.style.width = `${(ratio * 100).toFixed(3)}%`;
            timerEl.classList.toggle('is-warning', remainingMs > 0 && ratio <= 0.25);
            timerEl.classList.toggle('is-expired', remainingMs <= 0);
            if (remainingMs <= 0) {
                stopResultsQuestionTimer();
                return;
            }
            resultsQuestionTimer = requestAnimationFrame(tick);
        };

        tick();
    }

    function batchWithRunId(batch, runId) {
        const safeRunId = String(runId || '').trim();
        return (Array.isArray(batch) ? batch : []).map(item => ({
            ...(item && typeof item === 'object' ? item : {}),
            runId: safeRunId
        }));
    }

    async function copyTextToClipboard(text) {
        const value = String(text || '').trim();
        if (!value) {
            return false;
        }

        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
            try {
                await navigator.clipboard.writeText(value);
                return true;
            } catch (_) {
                // Fallback ci-dessous
            }
        }

        const area = document.createElement('textarea');
        area.value = value;
        area.setAttribute('readonly', 'readonly');
        area.style.position = 'fixed';
        area.style.opacity = '0';
        area.style.pointerEvents = 'none';
        area.style.left = '-9999px';
        document.body.appendChild(area);
        area.select();
        let ok = false;
        try {
            ok = document.execCommand('copy');
        } catch (_) {
            ok = false;
        }
        document.body.removeChild(area);
        return ok;
    }

    function renderAccessCodeDisplay(code) {
        const codeDisplay = document.getElementById('codeDisplay');
        if (!codeDisplay) {
            return;
        }
        const safeCode = String(code || '').trim();
        codeDisplay.innerHTML = `
            <span class="code-display-value">${escapeHtml(safeCode)}</span>
            <button
                type="button"
                class="code-copy-btn code-copy-icon-btn"
                data-code="${escapeHtml(safeCode)}"
                aria-label="Copier le code d'accès"
                title="Copier le code d'accès"
            >
                <i class="fa-regular fa-copy" aria-hidden="true"></i>
            </button>
        `;
    }

    function normalizeLegendLabels(rawLabels) {
        if (!Array.isArray(rawLabels)) {
            return [];
        }
        const out = [];
        rawLabels.forEach((entry, index) => {
            if (!entry || typeof entry !== 'object') {
                return;
            }
            const text = String(entry.text || '').trim();
            const safeId = String(entry.id || '').trim().replace(/[^a-zA-Z0-9_-]/g, '') || `lbl${index + 1}`;
            const hasX = Number.isFinite(Number(entry.x));
            const hasY = Number.isFinite(Number(entry.y));
            out.push({
                id: safeId,
                text,
                x: hasX ? Math.max(0, Math.min(100, Number(entry.x))) : null,
                y: hasY ? Math.max(0, Math.min(100, Number(entry.y))) : null
            });
        });
        // Compat: ancien comportement pouvait créer un point coincé en haut-gauche (0,0)
        // sans intention utilisateur.
        out.forEach(item => {
            if (item.x !== null && item.y !== null && item.x <= 1 && item.y <= 1) {
                item.x = null;
                item.y = null;
            }
        });
        return out;
    }

    function safeSetLocalStorage(key, value) {
        try {
            localStorage.setItem(key, value);
            return true;
        } catch (_) {
            return false;
        }
    }

    function keepImageOnlyIfLightStorage(value) {
        const raw = String(value || '').trim();
        if (!raw) {
            return '';
        }
        if (/^https?:\/\//i.test(raw) || raw.startsWith('uploads/')) {
            return raw;
        }
        return '';
    }

    function sanitizeBatchForLocalStorage(batch) {
        if (!Array.isArray(batch)) {
            return [];
        }
        return batch.map(item => {
            if (!item || typeof item !== 'object') {
                return item;
            }
            const clone = { ...item };
            if (Object.prototype.hasOwnProperty.call(clone, 'questionImage')) {
                clone.questionImage = keepImageOnlyIfLightStorage(clone.questionImage);
            }
            return clone;
        });
    }

    function hasInlineQuestionImage(batch) {
        if (!Array.isArray(batch)) {
            return false;
        }
        return batch.some(item => {
            const image = String(item?.questionImage || '').trim();
            return image.startsWith('data:image/');
        });
    }

    function compactLocalStoragePayloads() {
        try {
            const savedRaw = localStorage.getItem(BATCH_STATE_KEY);
            if (savedRaw) {
                const saved = JSON.parse(savedRaw);
                if (saved && Array.isArray(saved.batch)) {
                    const compacted = { ...saved, batch: sanitizeBatchForLocalStorage(saved.batch) };
                    if (!safeSetLocalStorage(BATCH_STATE_KEY, JSON.stringify(compacted))) {
                        localStorage.removeItem(BATCH_STATE_KEY);
                    }
                }
            }
        } catch (_) {
            localStorage.removeItem(BATCH_STATE_KEY);
        }

        try {
            const draftRaw = localStorage.getItem(EDITOR_DRAFT_KEY);
            if (draftRaw) {
                const draft = JSON.parse(draftRaw);
                if (draft && Array.isArray(draft.batch)) {
                    const compactedDraft = { ...draft, batch: sanitizeBatchForLocalStorage(draft.batch) };
                    if (!safeSetLocalStorage(EDITOR_DRAFT_KEY, JSON.stringify(compactedDraft))) {
                        localStorage.removeItem(EDITOR_DRAFT_KEY);
                    }
                }
            }
        } catch (_) {
            localStorage.removeItem(EDITOR_DRAFT_KEY);
        }

        try {
            const questionsRaw = localStorage.getItem('questions');
            if (questionsRaw) {
                const parsed = JSON.parse(questionsRaw);
                if (parsed && typeof parsed === 'object') {
                    Object.keys(parsed).forEach(code => {
                        const item = parsed[code];
                        if (!item || typeof item !== 'object') {
                            return;
                        }
                        if (Object.prototype.hasOwnProperty.call(item, 'questionImage')) {
                            item.questionImage = keepImageOnlyIfLightStorage(item.questionImage);
                        }
                    });
                    if (!safeSetLocalStorage('questions', JSON.stringify(parsed))) {
                        localStorage.removeItem('questions');
                    }
                }
            }
        } catch (_) {
            localStorage.removeItem('questions');
        }
    }

    function supportsQuestionImage(type) {
        const normalizedType = normalizeQuestionType(type);
        return normalizedType === 'multiple' || normalizedType === 'checkbox' || normalizedType === 'open' || normalizedType === 'cloze' || normalizedType === 'labelimage';
    }

    function isValidQuestionImage(value) {
        const raw = String(value || '').trim();
        if (!raw) {
            return false;
        }
        if (raw.startsWith('data:image/png;base64,') || raw.startsWith('data:image/jpeg;base64,') || raw.startsWith('data:image/webp;base64,') || raw.startsWith('data:image/gif;base64,')) {
            return true;
        }
        return /^https?:\/\//i.test(raw) || raw.startsWith('uploads/');
    }

    function getQuestionImageFromBlock(block) {
        const input = block.querySelector('.batch-question-image-data');
        const value = String(input?.value || '').trim();
        return isValidQuestionImage(value) ? value : '';
    }

    function normalizeQuestionImageZoom(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric)) {
            return 1;
        }
        return Math.max(0.6, Math.min(2.2, numeric));
    }

    function getQuestionImageZoomFromBlock(block) {
        const preview = block.querySelector('.batch-question-image-preview');
        const previewZoom = Number(preview?.dataset.zoom || NaN);
        if (Number.isFinite(previewZoom)) {
            return normalizeQuestionImageZoom(previewZoom);
        }
        return normalizeQuestionImageZoom(block?.dataset.questionImageZoom);
    }

    function updateQuestionImagePreview(block) {
        const fields = block.querySelector('.question-image-fields');
        const labelImageFields = block.querySelector('.question-labelimage-image-fields');
        const wrap = block.querySelector('.batch-question-image-preview');
        const img = block.querySelector('.batch-question-image-preview-img');
        const src = getQuestionImageFromBlock(block);
        const selectedType = normalizeQuestionType(block.querySelector('.batch-question-type')?.value);
        const isLabelImage = selectedType === 'labelimage';
        const clearLabelImageBtn = block.querySelector('.clear-labelimage-btn');
        if (!wrap || !img) {
            syncLegendEditorImage(block);
            return;
        }
        if (!src) {
            img.removeAttribute('src');
            wrap.classList.add('hidden');
            wrap.classList.remove('is-landscape-full');
            wrap.classList.remove('is-portrait-large');
            if (fields) {
                fields.classList.remove('has-image');
            }
            if (labelImageFields) {
                labelImageFields.classList.remove('has-image');
            }
            syncLegendEditorImage(block);
            if (clearLabelImageBtn) {
                clearLabelImageBtn.classList.add('hidden');
            }
            return;
        }
        img.src = src;
        if (isLabelImage) {
            wrap.classList.add('hidden');
            wrap.classList.remove('is-landscape-full');
            wrap.classList.remove('is-portrait-large');
        } else {
            wrap.classList.remove('hidden');
            applyQuestionImageSizing(wrap, img);
        }
        if (fields) {
            if (isLabelImage) {
                fields.classList.remove('has-image');
            } else {
                fields.classList.add('has-image');
            }
        }
        if (labelImageFields) {
            labelImageFields.classList.toggle('has-image', isLabelImage);
        }
        if (clearLabelImageBtn) {
            clearLabelImageBtn.classList.remove('hidden');
        }
        syncLegendEditorImage(block);
    }

    function createLegendLabelEditorRow(label = {}, index = 0) {
        const id = String(label.id || `lbl${index + 1}`).replace(/[^a-zA-Z0-9_-]/g, '') || `lbl${index + 1}`;
        const text = String(label.text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
        const x = Number.isFinite(Number(label.x)) ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(label.x))) : null;
        const y = Number.isFinite(Number(label.y)) ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(label.y))) : null;
        const row = document.createElement('div');
        row.className = 'legend-label-row';
        row.dataset.labelId = id;
        if (x !== null && y !== null) {
            row.dataset.x = String(x);
            row.dataset.y = String(y);
        }
        row.innerHTML = `
            <span class="legend-label-index">${index + 1}</span>
            <input type="text" class="batch-legend-label-input" placeholder="Texte de l'étiquette" value="${text}">
            <button type="button" class="secondary-btn icon-only-btn remove-legend-label-btn" aria-label="Supprimer cette étiquette" title="Supprimer">
                <i class="fa-solid fa-trash" aria-hidden="true"></i>
            </button>
        `;
        return row;
    }

    function getDefaultLegendMarkerPosition(index) {
        const safeIndex = Math.max(0, Number(index) || 0);
        const col = safeIndex % 5;
        const row = Math.floor(safeIndex / 5) % 4;
        return {
            x: Math.min(82, 18 + col * 14),
            y: Math.min(78, 18 + row * 10)
        };
    }

    function getLegendImageGeometry(canvas, imageEl) {
        if (!canvas || !imageEl) {
            return null;
        }
        const canvasRect = canvas.getBoundingClientRect();
        const imageRect = imageEl.getBoundingClientRect();
        if (canvasRect.width <= 0 || canvasRect.height <= 0 || imageRect.width <= 0 || imageRect.height <= 0) {
            return null;
        }
        return {
            canvasRect,
            imageRect,
            offsetX: imageRect.left - canvasRect.left,
            offsetY: imageRect.top - canvasRect.top
        };
    }

    function legendClientToPercent(clientX, clientY, canvas, imageEl) {
        const geometry = getLegendImageGeometry(canvas, imageEl);
        if (!geometry) {
            return null;
        }
        const { imageRect } = geometry;
        if (clientX < imageRect.left || clientX > imageRect.right || clientY < imageRect.top || clientY > imageRect.bottom) {
            return null;
        }
        const x = ((clientX - imageRect.left) / imageRect.width) * 100;
        const y = ((clientY - imageRect.top) / imageRect.height) * 100;
        return {
            x: Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(x.toFixed(3)))),
            y: Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(y.toFixed(3))))
        };
    }

    function placeLegendMarker(marker, percentX, percentY, canvas, imageEl) {
        const safeX = Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(percentX)));
        const safeY = Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(percentY)));
        const geometry = getLegendImageGeometry(canvas, imageEl);
        if (!geometry) {
            marker.style.left = `${safeX}%`;
            marker.style.top = `${safeY}%`;
            return;
        }
        const left = geometry.offsetX + ((safeX / 100) * geometry.imageRect.width);
        const top = geometry.offsetY + ((safeY / 100) * geometry.imageRect.height);
        marker.style.left = `${left}px`;
        marker.style.top = `${top}px`;
    }

    function collectLegendLabelsFromBlock(block) {
        return Array.from(block.querySelectorAll('.legend-label-row')).map((row, index) => {
            const xRaw = row.dataset.x;
            const yRaw = row.dataset.y;
            const x = Number.isFinite(Number(xRaw))
                ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(xRaw)))
                : null;
            const y = Number.isFinite(Number(yRaw))
                ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(yRaw)))
                : null;
            return {
                id: String(row.dataset.labelId || `lbl${index + 1}`).replace(/[^a-zA-Z0-9_-]/g, '') || `lbl${index + 1}`,
                text: String(row.querySelector('.batch-legend-label-input')?.value || '').trim(),
                x,
                y
            };
        });
    }

    function syncLegendEditorImage(block) {
        const canvas = block.querySelector('.legend-editor-canvas');
        const img = block.querySelector('.legend-editor-image');
        const empty = block.querySelector('.legend-editor-empty');
        const src = getQuestionImageFromBlock(block);
        if (!canvas || !img || !empty) {
            return;
        }

        if (!src) {
            img.removeAttribute('src');
            canvas.classList.add('is-empty');
            return;
        }

        if (img.getAttribute('src') !== src) {
            img.src = src;
        }
        canvas.classList.remove('is-empty');
    }

    function refreshLegendEditor(block) {
        const list = block.querySelector('.batch-legend-label-items');
        const overlay = block.querySelector('.legend-editor-overlay');
        const canvas = block.querySelector('.legend-editor-canvas');
        const imageEl = block.querySelector('.legend-editor-image');
        if (!list || !overlay) {
            return;
        }
        const activeLabelId = String(canvas?.dataset.activeLabelId || '').trim();
        const rows = Array.from(list.querySelectorAll('.legend-label-row'));
        rows.forEach((row, index) => {
            const indexEl = row.querySelector('.legend-label-index');
            if (indexEl) {
                indexEl.textContent = String(index + 1);
            }
            const removeBtn = row.querySelector('.remove-legend-label-btn');
            if (removeBtn) {
                removeBtn.disabled = rows.length <= 1;
            }
        });

        overlay.innerHTML = '';
        rows.forEach((row, index) => {
            const x = Number(row.dataset.x);
            const y = Number(row.dataset.y);
            const isPlaced = Number.isFinite(x) && Number.isFinite(y);
            const showPlaceholder = !isPlaced;

            const basePos = isPlaced
                ? { x, y }
                : getDefaultLegendMarkerPosition(index);
            const marker = document.createElement('button');
            marker.type = 'button';
            marker.className = `legend-editor-marker${showPlaceholder ? ' is-placeholder' : ''}`;
            if (activeLabelId !== '' && (row.dataset.labelId || '') === activeLabelId) {
                marker.classList.add('is-current');
            }
            marker.dataset.labelId = row.dataset.labelId || '';
            marker.textContent = String(index + 1);
            if (showPlaceholder) {
                marker.title = `Étiquette ${index + 1} (emplacement indicatif à ajuster)`;
            } else {
                marker.title = `Étiquette ${index + 1}`;
            }
            placeLegendMarker(marker, basePos.x, basePos.y, canvas, imageEl);
            overlay.appendChild(marker);
        });
    }

    function setupLegendEditor(block, initialLabels = []) {
        const list = block.querySelector('.batch-legend-label-items');
        const addBtn = block.querySelector('.add-legend-label-btn');
        const canvas = block.querySelector('.legend-editor-canvas');
        const overlay = block.querySelector('.legend-editor-overlay');
        const imageEl = block.querySelector('.legend-editor-image');
        if (!list || !addBtn || !canvas || !overlay || !imageEl) {
            return;
        }

        const labels = normalizeLegendLabels(initialLabels);
        const seed = labels.length ? labels : [{ id: 'lbl1', text: '', x: null, y: null }];
        seed.forEach((label, index) => list.appendChild(createLegendLabelEditorRow(label, index)));

        const setActive = (labelId) => {
            const safeId = String(labelId || '').trim();
            list.querySelectorAll('.legend-label-row').forEach(row => {
                row.classList.toggle('is-active', row.dataset.labelId === safeId);
            });
            canvas.dataset.activeLabelId = safeId;
        };

        const activateFirstAvailable = () => {
            const rows = Array.from(list.querySelectorAll('.legend-label-row'));
            const missing = rows.find(row => !Number.isFinite(Number(row.dataset.x)) || !Number.isFinite(Number(row.dataset.y)));
            setActive((missing || rows[0])?.dataset.labelId || '');
        };

        refreshLegendEditor(block);
        syncLegendEditorImage(block);
        activateFirstAvailable();

        addBtn.addEventListener('click', function() {
            const rows = Array.from(list.querySelectorAll('.legend-label-row'));
            const nextIndex = rows.length + 1;
            const newRow = createLegendLabelEditorRow(
                { id: `lbl${Date.now()}${nextIndex}`, text: '', x: null, y: null },
                rows.length
            );
            list.appendChild(newRow);
            refreshLegendEditor(block);
            setActive(newRow.dataset.labelId);
            const input = newRow.querySelector('.batch-legend-label-input');
            if (input) {
                input.focus();
            }
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        list.addEventListener('click', function(e) {
            const removeBtn = e.target.closest('.remove-legend-label-btn');
            if (removeBtn) {
                const rows = Array.from(list.querySelectorAll('.legend-label-row'));
                if (rows.length <= 1) {
                    return;
                }
                const row = removeBtn.closest('.legend-label-row');
                const removedId = row?.dataset.labelId || '';
                row?.remove();
                refreshLegendEditor(block);
                if (canvas.dataset.activeLabelId === removedId) {
                    activateFirstAvailable();
                }
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
                return;
            }

            const row = e.target.closest('.legend-label-row');
            if (!row) {
                return;
            }
            setActive(row.dataset.labelId);
        });

        list.addEventListener('input', function(e) {
            if (!e.target.classList.contains('batch-legend-label-input')) {
                return;
            }
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        list.addEventListener('focusin', function(e) {
            const row = e.target.closest('.legend-label-row');
            if (!row) {
                return;
            }
            setActive(row.dataset.labelId);
        });

        overlay.addEventListener('click', function(e) {
            const marker = e.target.closest('.legend-editor-marker');
            if (!marker) {
                return;
            }
            setActive(marker.dataset.labelId);
        });

        let draggingMarkerId = '';
        function updateDraggedMarkerPosition(clientX, clientY) {
            if (!draggingMarkerId) {
                return;
            }
            const row = list.querySelector(`.legend-label-row[data-label-id="${draggingMarkerId}"]`);
            if (!row) {
                return;
            }
            const rect = canvas.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) {
                return;
            }
            const pos = legendClientToPercent(clientX, clientY, canvas, imageEl);
            if (!pos) {
                return;
            }
            row.dataset.x = String(pos.x);
            row.dataset.y = String(pos.y);
            refreshLegendEditor(block);
        }
        function stopMarkerDrag(save = false) {
            if (!draggingMarkerId) {
                return;
            }
            draggingMarkerId = '';
            document.removeEventListener('pointermove', onPointerMoveMarker);
            document.removeEventListener('pointerup', onPointerUpMarker);
            document.removeEventListener('pointercancel', onPointerUpMarker);
            if (save) {
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
            }
        }
        function onPointerMoveMarker(e) {
            updateDraggedMarkerPosition(e.clientX, e.clientY);
        }
        function onPointerUpMarker() {
            stopMarkerDrag(true);
        }
        overlay.addEventListener('pointerdown', function(e) {
            const marker = e.target.closest('.legend-editor-marker');
            if (!marker) {
                return;
            }
            e.preventDefault();
            draggingMarkerId = String(marker.dataset.labelId || '');
            setActive(draggingMarkerId);
            document.addEventListener('pointermove', onPointerMoveMarker);
            document.addEventListener('pointerup', onPointerUpMarker);
            document.addEventListener('pointercancel', onPointerUpMarker);
        });

        canvas.addEventListener('click', function(e) {
            if (!getQuestionImageFromBlock(block)) {
                return;
            }
            if (e.target.closest('.legend-editor-marker')) {
                return;
            }
            const activeId = String(canvas.dataset.activeLabelId || '').trim();
            if (!activeId) {
                activateFirstAvailable();
            }
            const resolvedActiveId = String(canvas.dataset.activeLabelId || '').trim();
            const activeRow = resolvedActiveId
                ? list.querySelector(`.legend-label-row[data-label-id="${resolvedActiveId}"]`)
                : null;
            if (!activeRow) {
                return;
            }
            const pos = legendClientToPercent(e.clientX, e.clientY, canvas, imageEl);
            if (!pos) {
                return;
            }
            activeRow.dataset.x = String(pos.x);
            activeRow.dataset.y = String(pos.y);
            refreshLegendEditor(block);
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        imageEl.addEventListener('load', () => refreshLegendEditor(block));
    }

    function setupQuestionImageZoomControls(block) {
        const preview = block.querySelector('.batch-question-image-preview');
        const img = block.querySelector('.batch-question-image-preview-img');
        const zoomValue = block.querySelector('.question-image-zoom-value');
        const zoomInBtn = block.querySelector('.question-image-zoom-btn[data-action="in"]');
        const zoomOutBtn = block.querySelector('.question-image-zoom-btn[data-action="out"]');
        if (!preview || !img || !zoomValue || !zoomInBtn || !zoomOutBtn) {
            return;
        }

        const MIN_ZOOM = 0.6;
        const MAX_ZOOM = 2.2;
        const ZOOM_STEP = 0.1;

        const setZoom = (value) => {
            const safeZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Number(value) || 1));
            preview.dataset.zoom = safeZoom.toFixed(2);
            block.dataset.questionImageZoom = safeZoom.toFixed(2);
            img.style.transform = `scale(${safeZoom})`;
            zoomValue.textContent = `${Math.round(safeZoom * 100)}%`;
            zoomInBtn.disabled = safeZoom >= (MAX_ZOOM - 0.001);
            zoomOutBtn.disabled = safeZoom <= (MIN_ZOOM + 0.001);
        };

        zoomInBtn.addEventListener('click', function() {
            setZoom(Number(preview.dataset.zoom || 1) + ZOOM_STEP);
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });
        zoomOutBtn.addEventListener('click', function() {
            setZoom(Number(preview.dataset.zoom || 1) - ZOOM_STEP);
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        setZoom(getQuestionImageZoomFromBlock(block));
    }

    function readImageFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(String(reader.result || ''));
            reader.onerror = () => reject(new Error("Impossible de lire l'image sélectionnée."));
            reader.readAsDataURL(file);
        });
    }

    function estimateDataUrlBytes(dataUrl) {
        const raw = String(dataUrl || '');
        const commaIndex = raw.indexOf(',');
        if (commaIndex === -1) {
            return raw.length;
        }
        const b64 = raw.slice(commaIndex + 1);
        return Math.ceil((b64.length * 3) / 4);
    }

    function loadImageFromDataUrl(dataUrl) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = () => reject(new Error("Impossible de décoder l'image."));
            img.src = dataUrl;
        });
    }

    function dataUrlToBlob(dataUrl) {
        const raw = String(dataUrl || '');
        const commaIndex = raw.indexOf(',');
        if (commaIndex === -1) {
            return null;
        }
        const meta = raw.slice(0, commaIndex);
        const b64 = raw.slice(commaIndex + 1);
        const mimeMatch = meta.match(/^data:([^;]+);base64$/i);
        const mime = mimeMatch ? mimeMatch[1] : 'application/octet-stream';
        try {
            const binary = atob(b64);
            const len = binary.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i += 1) {
                bytes[i] = binary.charCodeAt(i);
            }
            return new Blob([bytes], { type: mime });
        } catch (_) {
            return null;
        }
    }

    async function uploadQuestionImageAsset(dataUrl, originalFileName = 'image.webp') {
        const blob = dataUrlToBlob(dataUrl);
        if (!blob) {
            throw new Error("Impossible de préparer l'image pour l'envoi.");
        }
        const fileBase = String(originalFileName || 'image').replace(/\.[^.]+$/, '').replace(/[^a-zA-Z0-9_-]+/g, '_') || 'image';
        const extension = blob.type === 'image/png' ? 'png' :
            blob.type === 'image/jpeg' ? 'jpg' :
            blob.type === 'image/gif' ? 'gif' : 'webp';
        const fileName = `${fileBase}.${extension}`;

        const form = new FormData();
        form.append('image', blob, fileName);
        form.append('code', state.code || getOrCreateSessionCode(true));

        const resp = await fetchApi('upload_question_image.php', {
            method: 'POST',
            body: form
        });
        const data = await resp.json();
        if (!data.success || !data.imageUrl) {
            throw new Error(data.error || "Échec de l'upload de l'image.");
        }
        return String(data.imageUrl);
    }

    async function optimizeQuestionImageFile(file) {
        const originalDataUrl = await readImageFileAsDataUrl(file);
        if (file.size > 0 && file.size <= TARGET_QUESTION_IMAGE_BYTES) {
            return originalDataUrl;
        }
        if (file.type === 'image/gif') {
            if (estimateDataUrlBytes(originalDataUrl) > MAX_QUESTION_IMAGE_BYTES) {
                throw new Error("GIF trop volumineux (2 Mo maximum).");
            }
            return originalDataUrl;
        }

        const sourceImg = await loadImageFromDataUrl(originalDataUrl);
        const srcW = Number(sourceImg.naturalWidth || sourceImg.width || 0);
        const srcH = Number(sourceImg.naturalHeight || sourceImg.height || 0);
        if (srcW <= 0 || srcH <= 0) {
            throw new Error('Dimensions image invalides.');
        }

        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        if (!ctx) {
            throw new Error('Canvas indisponible pour traiter l’image.');
        }

        const maxW = 1600;
        const maxH = 1600;
        let currentScale = Math.min(1, maxW / srcW, maxH / srcH);
        let dataUrl = '';
        let encodedBytes = Number.MAX_SAFE_INTEGER;

        for (let pass = 0; pass < 9; pass += 1) {
            const outW = Math.max(1, Math.round(srcW * currentScale));
            const outH = Math.max(1, Math.round(srcH * currentScale));
            canvas.width = outW;
            canvas.height = outH;
            ctx.clearRect(0, 0, outW, outH);
            ctx.drawImage(sourceImg, 0, 0, outW, outH);

            for (let quality = 0.86; quality >= 0.36; quality -= 0.06) {
                dataUrl = canvas.toDataURL('image/webp', quality);
                encodedBytes = estimateDataUrlBytes(dataUrl);
                if (encodedBytes <= TARGET_QUESTION_IMAGE_BYTES) {
                    return dataUrl;
                }
            }

            currentScale *= 0.8;
        }

        if (encodedBytes <= MAX_QUESTION_IMAGE_BYTES) {
            return dataUrl;
        }
        if (encodedBytes > MAX_QUESTION_IMAGE_BYTES) {
            throw new Error("Image trop volumineuse, même après optimisation (2 Mo maximum).");
        }
        return dataUrl;
    }

    function applyQuestionImageSizing(container, img) {
        if (!container || !img) {
            return;
        }

        const update = () => {
            const w = Number(img.naturalWidth || 0);
            const h = Number(img.naturalHeight || 0);
            if (w <= 0 || h <= 0) {
                container.classList.remove('is-landscape-full');
                container.classList.remove('is-portrait-large');
                return;
            }

            const ratio = w / h;
            const isLandscape = ratio >= 1.25;
            const isPortrait = ratio <= 0.82;
            const hasEnoughQuality = w >= 900 && h >= 500;
            container.classList.toggle('is-landscape-full', isLandscape && hasEnoughQuality);
            container.classList.toggle('is-portrait-large', isPortrait && hasEnoughQuality);
        };

        img.addEventListener('load', update, { once: true });
        if (img.complete && Number(img.naturalWidth || 0) > 0) {
            update();
            return;
        }
        setTimeout(update, 0);
    }

    function normalizePublicQuestionImageZoom(value) {
        const zoom = Number(value);
        if (!Number.isFinite(zoom)) {
            return 1;
        }
        return Math.max(0.6, Math.min(2.2, zoom));
    }

    function applyPublicQuestionImageZoom(container, img, zoom) {
        if (!container || !img) {
            return;
        }
        const safeZoom = normalizePublicQuestionImageZoom(zoom);
        img.style.transformOrigin = 'center center';
        img.style.transition = 'transform 0.14s ease';
        img.style.transform = `scale(${safeZoom})`;
        container.style.overflow = safeZoom > 1 ? 'hidden' : '';
    }

    function collectRankingItemsFromBlock(block) {
        return Array.from(block.querySelectorAll('.batch-ranking-item-input'))
            .map(input => (input.value || '').trim())
            .filter(Boolean);
    }

    function collectMultipleChoiceItemsFromBlock(block) {
        return Array.from(block.querySelectorAll('.batch-answer-input'))
            .map(input => (input.value || '').trim());
    }

    function setupMultipleChoiceEditor(block, uid, initialAnswers = [], initialCorrectIndex = 0, initialCorrectIndexes = []) {
        const list = block.querySelector('.batch-multiple-items');
        const addBtn = block.querySelector('.add-multiple-option-btn');
        if (!list || !addBtn) {
            return;
        }

        const isSingleChoiceMode = () => isSingleChoiceQuestionType(block.querySelector('.batch-question-type')?.value);

        const seed = Array.isArray(initialAnswers) ? initialAnswers.filter(Boolean).slice(0, MAX_MULTIPLE_ANSWERS) : [];
        while (seed.length < 2) {
            seed.push('');
        }
        let currentCorrectIndex = Number.isInteger(initialCorrectIndex) ? initialCorrectIndex : 0;
        if (currentCorrectIndex < 0 || currentCorrectIndex >= seed.length) {
            currentCorrectIndex = 0;
        }
        const currentCorrectIndexes = Array.isArray(initialCorrectIndexes)
            ? initialCorrectIndexes
                .map(value => parseInt(value, 10))
                .filter(index => Number.isInteger(index) && index >= 0 && index < seed.length)
            : [];

        function createRow(index, value = '', checked = false) {
            const safeValue = String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
            const requiredAttr = index < 2 ? 'required' : '';
            const row = document.createElement('div');
            row.className = 'form-group answer-with-correct multiple-option-row';
            row.innerHTML = `
                <div class="answer-input-wrap">
                    <span class="answer-input-index">${index + 1}</span>
                    <div class="math-enabled-input-wrap">
                        <input type="text" class="batch-answer-input" value="${safeValue}" ${requiredAttr} ${index >= 2 ? 'placeholder="Optionnelle"' : ''}>
                        <button type="button" class="secondary-btn icon-only-btn open-math-editor-btn inline-math-insert-btn" data-target-kind="input" aria-label="Insérer une formule dans cette réponse" title="Insérer une formule">
                            <span class="math-tool-icon" aria-hidden="true">∑</span>
                        </button>
                    </div>
                </div>
                <div class="multiple-option-actions">
                    <label class="correct-choice" title="${isSingleChoiceMode() ? 'Définir comme bonne réponse' : 'Définir comme réponse correcte'}">
                        <input class="correct-marker-input" type="${isSingleChoiceMode() ? 'radio' : 'checkbox'}" name="${isSingleChoiceMode() ? `correct-${uid}` : `correct-${uid}-${index}`}" value="${index}" ${checked ? 'checked' : ''}>
                        <span class="correct-icon" aria-hidden="true"></span>
                        <span class="sr-only">Réponse correcte</span>
                    </label>
                    <button type="button" class="secondary-btn icon-only-btn remove-multiple-option-btn" aria-label="Supprimer cette option" title="Supprimer cette option">
                        <i class="fa-solid fa-trash" aria-hidden="true"></i>
                    </button>
                </div>
            `;
            return row;
        }

        function refreshRows() {
            const isSingleChoice = isSingleChoiceMode();
            const isChoice = isChoiceQuestionType(block.querySelector('.batch-question-type')?.value);
            const rows = Array.from(list.querySelectorAll('.multiple-option-row'));
            const checkedIndexes = rows
                .map((row, index) => {
                    const markerInput = row.querySelector('.correct-marker-input');
                    return markerInput && markerInput.checked ? index : null;
                })
                .filter(index => index !== null);
            rows.forEach((row, index) => {
                const indexBadge = row.querySelector('.answer-input-index');
                const input = row.querySelector('.batch-answer-input');
                const markerInput = row.querySelector('.correct-marker-input');
                const correctChoice = row.querySelector('.correct-choice');
                const removeBtn = row.querySelector('.remove-multiple-option-btn');
                if (indexBadge) {
                    indexBadge.textContent = String(index + 1);
                }
                if (input) {
                    input.required = index < 2;
                    input.placeholder = index >= 2 ? 'Optionnelle' : '';
                }
                if (markerInput) {
                    markerInput.type = isSingleChoice ? 'radio' : 'checkbox';
                    markerInput.value = String(index);
                    markerInput.name = isSingleChoice ? `correct-${uid}` : `correct-${uid}-${index}`;
                    markerInput.checked = isSingleChoice ? checkedIndexes[0] === index : checkedIndexes.includes(index);
                }
                if (correctChoice) {
                    const pollMode = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
                    correctChoice.classList.toggle('hidden', !isChoice || pollMode);
                    correctChoice.title = isSingleChoice ? 'Définir comme bonne réponse' : 'Définir comme réponse correcte';
                }
                if (removeBtn) {
                    removeBtn.disabled = rows.length <= 2;
                }
            });
            const pollMode = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
            if (isSingleChoice && !pollMode && !list.querySelector('.correct-marker-input:checked')) {
                const firstMarker = list.querySelector('.correct-marker-input');
                if (firstMarker) {
                    firstMarker.checked = true;
                }
            }
            addBtn.disabled = rows.length >= MAX_MULTIPLE_ANSWERS;
        }

        seed.forEach((value, index) => {
            const checked = isSingleChoiceMode() ? (index === currentCorrectIndex) : currentCorrectIndexes.includes(index);
            list.appendChild(createRow(index, value, checked));
        });
        refreshRows();

        addBtn.addEventListener('click', function() {
            const rows = list.querySelectorAll('.multiple-option-row');
            if (rows.length >= MAX_MULTIPLE_ANSWERS) {
                return;
            }
            list.appendChild(createRow(rows.length, '', false));
            refreshRows();
            const newInput = list.lastElementChild?.querySelector('.batch-answer-input');
            if (newInput) {
                newInput.focus();
            }
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        list.addEventListener('click', function(e) {
            const removeBtn = e.target.closest('.remove-multiple-option-btn');
            if (!removeBtn) {
                return;
            }
            const rows = Array.from(list.querySelectorAll('.multiple-option-row'));
            if (rows.length <= 2) {
                return;
            }
            const row = removeBtn.closest('.multiple-option-row');
            if (!row) {
                return;
            }
            const checkedMarker = row.querySelector('.correct-marker-input:checked');
            const removedChecked = !!checkedMarker;
            row.remove();
            refreshRows();
            const pollModeOnRemove = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
            if (removedChecked && isSingleChoiceMode() && !pollModeOnRemove) {
                const firstMarker = list.querySelector('.correct-marker-input');
                if (firstMarker) {
                    firstMarker.checked = true;
                }
            }
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });
    }

    function updateChoiceEditorMode(block, selectedType) {
        const isChoice = isChoiceQuestionType(selectedType);
        const isSingleChoice = isSingleChoiceQuestionType(selectedType);
        const answerInputs = block.querySelectorAll('.batch-answer-input');
        const choiceBadges = block.querySelectorAll('.correct-choice');
        const markerInputs = Array.from(block.querySelectorAll('.correct-marker-input'));
        const uid = String(block.dataset.uid || '').trim();
        const checkedIndexes = markerInputs
            .map((input, index) => (input.checked ? index : null))
            .filter(index => index !== null);

        answerInputs.forEach((input, index) => {
            input.required = isChoice && index < 2;
        });
        const pollMode = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
        choiceBadges.forEach((label, index) => {
            label.classList.toggle('hidden', !isChoice || pollMode);
            label.title = isSingleChoice ? 'Définir comme bonne réponse' : 'Définir comme réponse correcte';
            const markerInput = markerInputs[index];
            if (!markerInput) {
                return;
            }
            markerInput.type = isSingleChoice ? 'radio' : 'checkbox';
            markerInput.name = isSingleChoice ? `correct-${uid}` : `correct-${uid}-${index}`;
            markerInput.value = String(index);
            markerInput.checked = isSingleChoice ? checkedIndexes[0] === index : checkedIndexes.includes(index);
        });
        if (isSingleChoice && !pollMode && !block.querySelector('.correct-marker-input:checked') && markerInputs[0]) {
            markerInputs[0].checked = true;
        }
    }

    function createRankingEditorRow(value = '') {
        const safeValue = String(value ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
        const row = document.createElement('div');
        row.className = 'ranking-editor-row';
        row.draggable = false;
        row.innerHTML = `
            <button type="button" class="secondary-btn icon-only-btn ranking-editor-handle" draggable="true" aria-label="Déplacer cet élément" title="Glisser pour déplacer">
                <i class="fa-solid fa-grip-lines" aria-hidden="true"></i>
            </button>
            <div class="math-enabled-input-wrap">
                <input type="text" class="batch-ranking-item-input" placeholder="Élément à classer" value="${safeValue}">
                <button type="button" class="secondary-btn icon-only-btn open-math-editor-btn inline-math-insert-btn" data-target-kind="input" aria-label="Insérer une formule dans cet élément" title="Insérer une formule">
                    <span class="math-tool-icon" aria-hidden="true">∑</span>
                </button>
            </div>
            <button type="button" class="secondary-btn icon-only-btn remove-ranking-item-btn" aria-label="Supprimer cet élément" title="Supprimer">
                <i class="fa-solid fa-trash" aria-hidden="true"></i>
            </button>
        `;
        return row;
    }

    function setupRankingEditor(block, initialItems = []) {
        const list = block.querySelector('.batch-ranking-items');
        const addBtn = block.querySelector('.add-ranking-item-btn');
        if (!list || !addBtn) {
            return;
        }

        const starting = Array.isArray(initialItems) ? initialItems.filter(Boolean) : [];
        const seedItems = starting.length ? starting : ['', ''];
        seedItems.forEach(item => list.appendChild(createRankingEditorRow(item)));

        addBtn.addEventListener('click', function() {
            list.appendChild(createRankingEditorRow(''));
            const newInput = list.lastElementChild?.querySelector('.batch-ranking-item-input');
            if (newInput) {
                newInput.focus();
            }
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        list.addEventListener('click', function(e) {
            const removeBtn = e.target.closest('.remove-ranking-item-btn');
            if (!removeBtn) {
                return;
            }
            if (list.children.length <= 2) {
                return;
            }
            removeBtn.closest('.ranking-editor-row')?.remove();
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        let draggedRow = null;
        list.addEventListener('dragstart', function(e) {
            const handle = e.target.closest('.ranking-editor-handle');
            if (!handle) {
                e.preventDefault();
                return;
            }
            const row = handle.closest('.ranking-editor-row');
            if (!row) {
                return;
            }
            draggedRow = row;
            row.classList.add('is-dragging');
            if (e.dataTransfer) {
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', 'move');
            }
        });

        list.addEventListener('dragover', function(e) {
            e.preventDefault();
            if (!draggedRow) {
                return;
            }
            const row = e.target.closest('.ranking-editor-row');
            if (!row || row === draggedRow) {
                return;
            }
            const rect = row.getBoundingClientRect();
            const before = (e.clientY - rect.top) < (rect.height / 2);
            if (before) {
                list.insertBefore(draggedRow, row);
            } else {
                list.insertBefore(draggedRow, row.nextElementSibling);
            }
        });

        list.addEventListener('dragend', function() {
            if (draggedRow) {
                draggedRow.classList.remove('is-dragging');
            }
            draggedRow = null;
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        let touchDraggedRow = null;
        list.addEventListener('touchstart', function(e) {
            const handle = e.target.closest('.ranking-editor-handle');
            if (!handle) {
                return;
            }
            const row = handle.closest('.ranking-editor-row');
            if (!row) {
                return;
            }
            touchDraggedRow = row;
            row.classList.add('is-dragging');
        }, { passive: true });

        list.addEventListener('touchmove', function(e) {
            if (!touchDraggedRow) {
                return;
            }
            const touch = e.touches && e.touches[0];
            if (!touch) {
                return;
            }
            const target = document.elementFromPoint(touch.clientX, touch.clientY);
            const overRow = target?.closest('.ranking-editor-row');
            if (!overRow || overRow === touchDraggedRow || !list.contains(overRow)) {
                return;
            }
            e.preventDefault();
            const rect = overRow.getBoundingClientRect();
            const before = (touch.clientY - rect.top) < (rect.height / 2);
            if (before) {
                list.insertBefore(touchDraggedRow, overRow);
            } else {
                list.insertBefore(touchDraggedRow, overRow.nextElementSibling);
            }
        }, { passive: false });

        list.addEventListener('touchend', function() {
            if (touchDraggedRow) {
                touchDraggedRow.classList.remove('is-dragging');
            }
            touchDraggedRow = null;
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });
    }

    function extractYouTubeVideoId(input) {
        const value = String(input || '').trim();
        if (!value) {
            return '';
        }

        const directIdMatch = value.match(/^[a-zA-Z0-9_-]{11}$/);
        if (directIdMatch) {
            return directIdMatch[0];
        }

        let url;
        try {
            url = new URL(value);
        } catch (_) {
            try {
                url = new URL(`https://${value}`);
            } catch (_) {
                return '';
            }
        }

        const host = url.hostname.replace(/^www\./i, '').toLowerCase();
        const isYouTubeHost = host === 'youtube.com'
            || host === 'm.youtube.com'
            || host === 'music.youtube.com'
            || host === 'youtube-nocookie.com'
            || host.endsWith('.youtube.com')
            || host.endsWith('.youtube-nocookie.com');
        if (isYouTubeHost) {
            const fromQuery = url.searchParams.get('v');
            if (fromQuery && /^[a-zA-Z0-9_-]{11}$/.test(fromQuery)) {
                return fromQuery;
            }
            const embedMatch = url.pathname.match(/^\/embed\/([a-zA-Z0-9_-]{11})/);
            if (embedMatch) {
                return embedMatch[1];
            }
            const shortsMatch = url.pathname.match(/^\/shorts\/([a-zA-Z0-9_-]{11})/);
            if (shortsMatch) {
                return shortsMatch[1];
            }
            const liveMatch = url.pathname.match(/^\/live\/([a-zA-Z0-9_-]{11})/);
            if (liveMatch) {
                return liveMatch[1];
            }
        }

        if (host === 'youtu.be') {
            const shortMatch = url.pathname.match(/^\/([a-zA-Z0-9_-]{11})/);
            if (shortMatch) {
                return shortMatch[1];
            }
        }

        return '';
    }

    function buildYouTubeEmbedUrl(input, startValue = null, endValue = null) {
        const videoId = extractYouTubeVideoId(input);
        if (!videoId) {
            return '';
        }
        const params = new URLSearchParams();
        params.set('rel', '0');
        params.set('modestbranding', '1');
        const range = normalizeVideoRange(startValue, endValue);
        if (range.startSec !== null) {
            params.set('start', String(range.startSec));
        }
        if (range.endSec !== null) {
            params.set('end', String(range.endSec));
        }
        return `https://www.youtube.com/embed/${videoId}?${params.toString()}`;
    }

    function buildYouTubeWatchUrl(input, startValue = null, endValue = null) {
        const videoId = extractYouTubeVideoId(input);
        if (!videoId) {
            return '';
        }
        const params = new URLSearchParams();
        params.set('v', videoId);
        const range = normalizeVideoRange(startValue, endValue);
        if (range.startSec !== null) {
            params.set('t', `${range.startSec}s`);
        }
        if (range.endSec !== null) {
            params.set('end', String(range.endSec));
        }
        return `https://www.youtube.com/watch?${params.toString()}`;
    }

    function createYouTubeIframe(embedUrl, title = 'Vidéo YouTube') {
        const iframe = document.createElement('iframe');
        iframe.src = String(embedUrl || '');
        iframe.title = title;
        iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share');
        iframe.setAttribute('allowfullscreen', '');
        iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
        return iframe;
    }

    function animateStagger(container, selector = '.reveal-item') {
        const nodes = Array.from(container.querySelectorAll(selector));
        nodes.forEach((node, index) => {
            node.style.animationDelay = `${Math.min(index * 45, 360)}ms`;
        });
    }

    function updateResultsHelpText(type) {
        const el = document.querySelector('.results-help-text');
        if (!el) {
            return;
        }
        el.classList.add('hidden');
        el.textContent = '';
    }

    function setRevealButtonLabel(button, revealed) {
        if (!button) {
            return;
        }
        button.innerHTML = revealed
            ? '<i class="fa-solid fa-circle-check" aria-hidden="true"></i>Correction affichée'
            : '<i class="fa-solid fa-circle-check" aria-hidden="true"></i>Afficher la correction';
    }

    function setParticipantResponsesButtonLabel(button, visible) {
        if (!button) {
            return;
        }
        button.innerHTML = visible
            ? '<i class="fa-solid fa-eye-slash" aria-hidden="true"></i>Masquer les réponses'
            : '<i class="fa-solid fa-eye" aria-hidden="true"></i>Afficher les réponses';
    }

    function setWordcloudButtonLabel(button, isLarge) {
        if (!button) {
            return;
        }
        button.innerHTML = isLarge
            ? '<i class="fa-solid fa-compress" aria-hidden="true"></i>Nuage compact'
            : '<i class="fa-solid fa-expand" aria-hidden="true"></i>Nuage grand';
    }

    function appendParticipantResponsesHiddenMessage(container) {
        if (!container) {
            return;
        }
        const hiddenMessage = document.createElement('p');
        hiddenMessage.className = 'results-empty-line';
        hiddenMessage.textContent = 'Les réponses des participants sont actuellement masquées.';
        container.appendChild(hiddenMessage);
    }

    function getParticipantResponseEligibleQuestions(batch = state.batch) {
        if (!Array.isArray(batch)) {
            return [];
        }
        return batch.filter(item => normalizeQuestionType(item?.type) !== 'video');
    }

    function areParticipantResponsesVisibleForAllQuestions(batch = state.batch) {
        const eligible = getParticipantResponseEligibleQuestions(batch);
        if (eligible.length === 0) {
            return true;
        }
        return eligible.every(item => normalizeParticipantResponsesVisibility(item?.participantResponsesVisible));
    }

    function setLiveParticipantResponsesButtonLabel(button, allVisible) {
        if (!button) {
            return;
        }
        button.innerHTML = allVisible
            ? '<i class="fa-solid fa-eye-slash" aria-hidden="true"></i><span class="btn-label">Masquer les réponses</span>'
            : '<i class="fa-solid fa-eye" aria-hidden="true"></i><span class="btn-label">Afficher les réponses</span>';
    }

    function syncLiveActionButtonLabels() {
        const liveBtn = document.getElementById('viewResultsBtn');
        const editBtn = document.getElementById('createNewBtn');
        const newSessionBtn = document.getElementById('newSessionBtn');

        if (liveBtn) {
            liveBtn.innerHTML = '<i class="fa-solid fa-chart-line" aria-hidden="true"></i><span class="btn-label">Live</span>';
        }
        if (editBtn) {
            editBtn.innerHTML = '<i class="fa-solid fa-pen" aria-hidden="true"></i><span class="btn-label">Modifier</span>';
        }
        if (newSessionBtn) {
            newSessionBtn.innerHTML = '<i class="fa-solid fa-rotate-right" aria-hidden="true"></i><span class="btn-label">Nouvelle session</span>';
        }
    }

    function updateLiveParticipantResponsesButton() {
        const button = document.getElementById('toggleAllParticipantResponsesBtn');
        syncLiveActionButtonLabels();
        if (!button) {
            return;
        }
        const hasEligibleQuestions = getParticipantResponseEligibleQuestions(state.batch).length > 0;
        button.classList.toggle('hidden', !hasEligibleQuestions);
        setLiveParticipantResponsesButtonLabel(button, areParticipantResponsesVisibleForAllQuestions(state.batch));
    }

    function syncParticipantResponsesTogglesFromState() {
        const blocks = Array.from(batchQuestions?.querySelectorAll('.batch-question-block') || []);
        blocks.forEach((block, index) => {
            const toggle = block.querySelector('.batch-participant-responses-toggle');
            if (!toggle) {
                return;
            }
            const source = state.batch[index];
            toggle.checked = normalizeParticipantResponsesVisibility(source?.participantResponsesVisible);
        });
    }

    function getRatingAccentColor(avgRating, maxRating = 5) {
        const safeMax = Math.max(1, Number(maxRating || 5));
        const ratio = Math.max(0, Math.min(1, Number(avgRating || 0) / safeMax));
        const hue = Math.round(12 + (ratio * 116));
        return `hsl(${hue} 86% 52%)`;
    }

    function buildKeywordCounts(texts, ignoreStopWords = false, minLength = 2) {
        const counts = {};
        const displayWord = {};
        (texts || []).forEach(text => {
            const lowered = String(text || '').toLowerCase();
            const words = lowered.match(/[\p{L}\p{N}]+/gu) || [];
            words.forEach(rawWord => {
                const canonical = rawWord
                    .normalize('NFD')
                    .replace(/[\u0300-\u036f]/g, '');

                if (canonical.length < minLength || (!ignoreStopWords && WORD_STOP_WORDS.has(canonical))) {
                    return;
                }

                counts[canonical] = (counts[canonical] || 0) + 1;
                if (!displayWord[canonical] || rawWord.length > displayWord[canonical].length) {
                    displayWord[canonical] = rawWord;
                }
            });
        });

        return Object.entries(counts)
            .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
            .map(([canonical, count]) => ({ word: displayWord[canonical] || canonical, count }));
    }

    function hashWord(word) {
        let hash = 0;
        const text = String(word || '');
        for (let i = 0; i < text.length; i += 1) {
            hash = ((hash << 5) - hash) + text.charCodeAt(i);
            hash |= 0;
        }
        return Math.abs(hash);
    }

    function getWordCloudVisual(word, count, maxCount, isLarge = false) {
        const ratio = maxCount > 0 ? (count / maxCount) : 0;
        const scaledRatio = Math.pow(ratio, 0.85);
        const multiplier = isLarge ? 1.38 : 1;
        const size = Math.round((16 + Math.round(scaledRatio * 34)) * multiplier);
        const hue = hashWord(word) % 360;
        const saturation = 68;
        const lightness = 52 - Math.round(scaledRatio * 18);
        const weight = 500 + Math.round(scaledRatio * 300);
        return {
            size,
            color: `hsl(${hue} ${saturation}% ${lightness}%)`,
            weight
        };
    }

    async function fetchApi(path, options = undefined) {
        return fetchApiWithCandidates(path, options, REMOTE_API_BASES);
    }

    async function fetchAuth(path, options = undefined) {
        const response = await fetch(path, {
            credentials: 'same-origin',
            ...(options || {})
        });
        return response;
    }

    async function ensureAuthenticated() {
        const response = await fetchAuth('auth_me.php');
        if (!response.ok) {
            window.location.href = 'login.php';
            return false;
        }
        const data = await response.json();
        if (!data.success || !data.user) {
            window.location.href = 'login.php';
            return false;
        }
        state.user = data.user;
        return true;
    }

    function updateAccountBar() {
        const bar = document.getElementById('accountBar');
        const name = document.getElementById('accountName');
        if (!bar || !name || !state.user) {
            return;
        }
        name.textContent = state.user.username || state.user.email || '';
        bar.classList.remove('hidden');
    }

    function updateHomePanelDensity() {
        if (!homePanel) {
            return;
        }
        const hasSaved = !!savedQuizzesPanel && !savedQuizzesPanel.classList.contains('hidden');
        const hasTrash = !!trashQuizzesPanel && !trashQuizzesPanel.classList.contains('hidden');
        homePanel.classList.toggle('home-panel-empty', !hasSaved && !hasTrash);
    }

    async function setQuizFavorite(code, favorite) {
        const safeCode = String(code || '').trim();
        if (!safeCode) {
            throw new Error('Code manquant.');
        }
        const response = await fetchApi('set_quiz_favorite.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                code: safeCode,
                favorite: !!favorite
            })
        });
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'Mise à jour des favoris impossible.');
        }
        return !!data.isFavorite;
    }

    const QUIZ_COLORS = [
        { key: 'indigo', label: 'Indigo' },
        { key: 'blue', label: 'Bleu' },
        { key: 'teal', label: 'Sarcelle' },
        { key: 'green', label: 'Vert' },
        { key: 'amber', label: 'Ambre' },
        { key: 'rose', label: 'Rose' },
        { key: 'slate', label: 'Ardoise' }
    ];
    const QUIZ_COLOR_KEYS = new Set(QUIZ_COLORS.map(color => color.key));
    const QUIZ_DRAG_TYPE = 'text/x-audience-quiz';

    const homeState = {
        items: [],
        folders: [],
        foldersSupported: false,
        openFolderId: null,
        focusFolderNameId: null,
        filters: { query: '', date: 'all', sort: 'recent', tag: '' }
    };
    let pendingHomeRender = false;

    function normalizeQuizColorKey(value) {
        const key = String(value || '').trim().toLowerCase();
        return QUIZ_COLOR_KEYS.has(key) ? key : '';
    }

    function getHomeFolder(folderId) {
        if (folderId === null || folderId === undefined || folderId === '') {
            return null;
        }
        const id = Number(folderId);
        if (!Number.isFinite(id)) {
            return null;
        }
        return homeState.folders.find(folder => folder.id === id) || null;
    }

    function getHomeItem(code) {
        const safeCode = String(code || '').trim();
        return homeState.items.find(item => String(item?.code || '') === safeCode) || null;
    }

    function getQuizCardColor(item) {
        const own = normalizeQuizColorKey(item?.color);
        if (own) {
            return own;
        }
        const folder = getHomeFolder(item?.folderId);
        return folder ? normalizeQuizColorKey(folder.color) : '';
    }

    function foldSearchText(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLocaleLowerCase('fr');
    }

    function tagKey(tag) {
        return foldSearchText(String(tag || '').trim());
    }

    function getItemTags(item) {
        return Array.isArray(item?.tags) ? item.tags : [];
    }

    function getAllHomeTags() {
        const byKey = new Map();
        homeState.items.forEach(item => {
            getItemTags(item).forEach(tag => {
                const key = tagKey(tag);
                if (!key) {
                    return;
                }
                const entry = byKey.get(key) || { label: tag, key, count: 0 };
                entry.count += 1;
                byKey.set(key, entry);
            });
        });
        return Array.from(byKey.values()).sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, 'fr'));
    }

    function hasActiveHomeFilters() {
        const f = homeState.filters;
        return f.query.trim() !== '' || f.date !== 'all' || f.tag !== '';
    }

    function itemMatchesHomeFilters(item) {
        const f = homeState.filters;
        if (f.tag && !getItemTags(item).some(tag => tagKey(tag) === f.tag)) {
            return false;
        }
        if (f.date !== 'all') {
            const ms = Date.parse(String(item?.updatedAt || ''));
            if (!Number.isFinite(ms)) {
                return false;
            }
            const now = Date.now();
            const day = 86400000;
            if (f.date === 'today' && new Date(ms).toDateString() !== new Date(now).toDateString()) {
                return false;
            }
            if (f.date === 'week' && ms < now - 7 * day) {
                return false;
            }
            if (f.date === 'month' && ms < now - 30 * day) {
                return false;
            }
            if (f.date === 'older' && ms >= now - 30 * day) {
                return false;
            }
        }
        const query = foldSearchText(f.query.trim());
        if (query) {
            const folder = getHomeFolder(item?.folderId);
            const haystack = foldSearchText([
                item?.title,
                item?.code,
                folder?.name,
                ...getItemTags(item)
            ].join(' '));
            if (!query.split(/\s+/).every(word => haystack.includes(word))) {
                return false;
            }
        }
        return true;
    }

    function sortHomeItems(list) {
        const sorted = list.slice();
        const sort = homeState.filters.sort;
        const time = item => {
            const ms = Date.parse(String(item?.updatedAt || ''));
            return Number.isFinite(ms) ? ms : 0;
        };
        if (sort === 'title') {
            sorted.sort((a, b) => String(a?.title || '').localeCompare(String(b?.title || ''), 'fr', { sensitivity: 'base' }));
        } else if (sort === 'oldest') {
            sorted.sort((a, b) => time(a) - time(b));
        } else {
            sorted.sort((a, b) => time(b) - time(a));
        }
        return sorted;
    }

    function pluralFr(count, singular, plural = `${singular}s`) {
        return `${count} ${count > 1 ? plural : singular}`;
    }

    function formatRelativeDateFr(ms) {
        if (!Number.isFinite(ms)) {
            return '';
        }
        const diffSec = Math.round((ms - Date.now()) / 1000);
        const absSec = Math.abs(diffSec);
        if (absSec < 60) {
            return "à l'instant";
        }
        const rtf = new Intl.RelativeTimeFormat('fr', { numeric: 'auto' });
        if (absSec < 3600) {
            return rtf.format(Math.round(diffSec / 60), 'minute');
        }
        if (absSec < 86400) {
            return rtf.format(Math.round(diffSec / 3600), 'hour');
        }
        if (absSec < 86400 * 7) {
            return rtf.format(Math.round(diffSec / 86400), 'day');
        }
        const date = new Date(ms);
        const sameYear = date.getFullYear() === new Date().getFullYear();
        return 'le ' + date.toLocaleDateString('fr-FR', sameYear
            ? { day: 'numeric', month: 'short' }
            : { day: 'numeric', month: 'short', year: 'numeric' });
    }

    function getGreetingName() {
        const raw = String(state.user?.username || '').trim().replace(/_\d+$/, '');
        if (!raw || raw.includes('@')) {
            return '';
        }
        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    function renderHomeHeader() {
        const greetingEl = document.getElementById('homeGreeting');
        const statsEl = document.getElementById('homeStats');
        if (greetingEl) {
            const hour = new Date().getHours();
            const salutation = hour >= 18 || hour < 5 ? 'Bonsoir' : 'Bonjour';
            const name = getGreetingName();
            greetingEl.textContent = name ? `${salutation} ${name}` : salutation;
        }
        if (!statsEl) {
            return;
        }
        const items = homeState.items;
        if (items.length === 0) {
            statsEl.textContent = 'Créez votre premier questionnaire pour commencer.';
            return;
        }
        const totalQuestions = items.reduce((sum, item) => sum + Math.max(0, Number(item?.questionCount || 0)), 0);
        const latestMs = items.reduce((max, item) => {
            const ms = Date.parse(String(item?.updatedAt || ''));
            return Number.isFinite(ms) && ms > max ? ms : max;
        }, -Infinity);
        const parts = [
            pluralFr(items.length, 'questionnaire'),
            pluralFr(totalQuestions, 'question')
        ];
        if (homeState.foldersSupported && homeState.folders.length > 0) {
            parts.push(pluralFr(homeState.folders.length, 'dossier'));
        }
        if (Number.isFinite(latestMs)) {
            parts.push(`dernière modification ${formatRelativeDateFr(latestMs)}`);
        }
        statsEl.textContent = parts.join(' · ');
    }

    function buildOwnedQuizCard(item) {
        const code = String(item?.code || '').trim();
        if (!code) {
            return '';
        }
        const title = String(item?.title || '').trim() || '(sans titre)';
        const updatedAt = String(item?.updatedAt || '');
        const updatedMs = Date.parse(updatedAt);
        const updatedLabel = Number.isFinite(updatedMs) ? new Date(updatedMs).toLocaleString('fr-FR') : '';
        const updatedRelative = formatRelativeDateFr(updatedMs);
        const questionCount = Number(item?.questionCount || 0);
        const questionLabel = pluralFr(questionCount, 'question');
        const isActive = state.code && state.code === code;
        const isFavorite = !!item?.isFavorite;
        const favoriteActionLabel = isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris';
        const color = getQuizCardColor(item);
        const canOrganize = homeState.foldersSupported;
        return `
            <article class="saved-quiz-card${isActive ? ' is-active' : ''}${isFavorite ? ' is-favorite' : ''}" data-code="${escapeHtml(code)}"${color ? ` data-color="${color}"` : ''}${canOrganize ? ' draggable="true"' : ''}>
                <div class="saved-quiz-card-head">
                    <h3 title="${escapeHtml(title)}">${escapeHtml(title)}</h3>
                    <button type="button" class="secondary-btn icon-only-btn saved-quiz-favorite-btn${isFavorite ? ' is-favorite' : ''}" data-action="toggle-favorite" data-code="${escapeHtml(code)}" aria-label="${favoriteActionLabel} : ${escapeHtml(title)}" aria-pressed="${isFavorite ? 'true' : 'false'}" title="${favoriteActionLabel}">
                        <i class="${isFavorite ? 'fa-solid' : 'fa-regular'} fa-star" aria-hidden="true"></i>
                    </button>
                </div>
                <div class="saved-quiz-card-body">
                    <div class="saved-quiz-card-meta">
                        <span class="saved-quiz-card-chip saved-quiz-card-count"><i class="fa-solid fa-list-ul" aria-hidden="true"></i>${questionLabel}</span>
                        <span class="saved-quiz-card-chip saved-quiz-card-code" title="Code d'accès"><i class="fa-solid fa-hashtag" aria-hidden="true"></i>${escapeHtml(code)}</span>
                    </div>
                    ${buildCardTags(item)}
                    ${updatedRelative ? `<p class="saved-quiz-card-updated" title="Modifié le ${escapeHtml(updatedLabel)}"><i class="fa-regular fa-clock" aria-hidden="true"></i>Modifié ${escapeHtml(updatedRelative)}</p>` : ''}
                </div>
                <div class="saved-quiz-card-actions">
                    <button type="button" class="saved-quiz-present-btn" data-action="open-live" data-code="${escapeHtml(code)}" aria-label="Lancer la présentation de ${escapeHtml(title)}" title="Lancer la présentation">
                        <i class="fa-solid fa-play" aria-hidden="true"></i><span>Présenter</span>
                    </button>
                    <div class="saved-quiz-card-tools">
                        <button type="button" class="secondary-btn icon-only-btn saved-quiz-action-btn" data-action="open-edit" data-code="${escapeHtml(code)}" aria-label="Ouvrir ou modifier ${escapeHtml(title)}" title="Modifier">
                            <i class="fa-solid fa-pen" aria-hidden="true"></i>
                        </button>
                        <button type="button" class="secondary-btn icon-only-btn saved-quiz-action-btn" data-action="export" data-code="${escapeHtml(code)}" aria-label="Exporter ${escapeHtml(title)}" title="Exporter">
                            <i class="fa-solid fa-arrow-up-from-bracket" aria-hidden="true"></i>
                        </button>
                        <button type="button" class="secondary-btn icon-only-btn saved-quiz-action-btn saved-quiz-delete-btn" data-action="delete" data-code="${escapeHtml(code)}" aria-label="Supprimer ${escapeHtml(title)}" title="Supprimer">
                            <i class="fa-solid fa-trash" aria-hidden="true"></i>
                        </button>
                        ${canOrganize ? `
                        <button type="button" class="secondary-btn icon-only-btn saved-quiz-action-btn" data-action="card-menu" data-code="${escapeHtml(code)}" aria-haspopup="menu" aria-expanded="false" aria-label="Ranger ou colorer ${escapeHtml(title)}" title="Ranger, couleur">
                            <i class="fa-solid fa-ellipsis" aria-hidden="true"></i>
                        </button>` : ''}
                    </div>
                </div>
            </article>
        `;
    }

    function buildCardTags(item) {
        const tags = getItemTags(item);
        if (tags.length === 0) {
            return '';
        }
        const visible = tags.slice(0, 3);
        const activeTag = homeState.filters.tag;
        const chips = visible.map(tag => {
            const key = tagKey(tag);
            const isActive = key === activeTag;
            return `<button type="button" class="saved-quiz-tag${isActive ? ' is-active' : ''}" data-action="filter-tag" data-tag="${escapeHtml(key)}" aria-pressed="${isActive ? 'true' : 'false'}" title="${isActive ? 'Retirer ce filtre' : `Voir les questionnaires « ${escapeHtml(tag)} »`}">${escapeHtml(tag)}</button>`;
        }).join('');
        const more = tags.length > visible.length
            ? `<span class="saved-quiz-tag-more" title="${escapeHtml(tags.slice(3).join(', '))}">+${tags.length - visible.length}</span>`
            : '';
        return `<div class="saved-quiz-card-tags">${chips}${more}</div>`;
    }

    function renderHomeTagFilters() {
        const container = document.getElementById('homeTagFilters');
        if (!container) {
            return;
        }
        const tags = getAllHomeTags();
        if (tags.length === 0) {
            if (homeState.filters.tag) {
                homeState.filters.tag = '';
            }
            container.innerHTML = '';
            container.classList.add('hidden');
            return;
        }
        if (homeState.filters.tag && !tags.some(tag => tag.key === homeState.filters.tag)) {
            homeState.filters.tag = '';
        }
        const active = homeState.filters.tag;
        container.innerHTML = `
            <span class="home-tag-filters-label"><i class="fa-solid fa-tag" aria-hidden="true"></i> Étiquettes</span>
            <button type="button" class="home-tag-filter${active ? '' : ' is-active'}" data-tag="" aria-pressed="${active ? 'false' : 'true'}">Toutes</button>
            ${tags.map(tag => `
                <button type="button" class="home-tag-filter${tag.key === active ? ' is-active' : ''}" data-tag="${escapeHtml(tag.key)}" aria-pressed="${tag.key === active ? 'true' : 'false'}">
                    ${escapeHtml(tag.label)}<span class="home-tag-filter-count">${tag.count}</span>
                </button>
            `).join('')}
        `;
        container.classList.remove('hidden');
    }

    function buildFilteredResults(sourceItems, scopeLabel) {
        const results = sortHomeItems(sourceItems.filter(itemMatchesHomeFilters));
        const summary = `${pluralFr(results.length, 'résultat')}${scopeLabel ? ` dans « ${escapeHtml(scopeLabel)} »` : ''}`;
        return `
            <div class="saved-quiz-results">
                <div class="saved-quiz-results-bar">
                    <p class="saved-quiz-results-count" aria-live="polite">${summary}</p>
                    <button type="button" class="saved-quiz-clear-filters" data-action="clear-filters"><i class="fa-solid fa-xmark" aria-hidden="true"></i>Effacer les filtres</button>
                </div>
                ${results.length > 0
                    ? `<div class="saved-quiz-cards saved-quiz-cards-grid">${results.map(buildOwnedQuizCard).join('')}</div>`
                    : '<p class="saved-quiz-empty">Aucun questionnaire ne correspond à ces critères.</p>'}
            </div>
        `;
    }

    function buildFolderCard(folder) {
        const items = homeState.items.filter(item => item?.folderId === folder.id);
        const totalQuestions = items.reduce((sum, item) => sum + Math.max(0, Number(item?.questionCount || 0)), 0);
        const color = normalizeQuizColorKey(folder.color);
        const preview = items.slice(0, 3).map(item => `<li>${escapeHtml(String(item?.title || '').trim() || '(sans titre)')}</li>`).join('');
        const name = String(folder.name || '').trim() || 'Sans nom';
        return `
            <button type="button" class="saved-quiz-folder" data-action="open-folder" data-folder-id="${folder.id}"${color ? ` data-color="${color}"` : ''} aria-label="Ouvrir le dossier ${escapeHtml(name)}">
                <span class="saved-quiz-folder-head">
                    <span class="saved-quiz-folder-icon" aria-hidden="true"><i class="fa-solid fa-folder"></i></span>
                    <span class="saved-quiz-folder-text">
                        <strong>${escapeHtml(name)}</strong>
                        <small>${pluralFr(items.length, 'questionnaire')} · ${pluralFr(totalQuestions, 'question')}</small>
                    </span>
                </span>
                ${preview ? `<ul class="saved-quiz-folder-preview">${preview}</ul>` : '<span class="saved-quiz-folder-empty">Dossier vide</span>'}
            </button>
        `;
    }

    function buildNewQuizCard() {
        return `
            <button type="button" class="saved-quiz-new-card" data-action="new-quiz">
                <span class="saved-quiz-new-card-icon" aria-hidden="true"><i class="fa-solid fa-plus"></i></span>
                <span class="saved-quiz-new-card-label">Nouveau questionnaire</span>
            </button>
        `;
    }

    function buildQuizSection(title, icon, contentHtml, count, extraClass = '') {
        return `
            <section class="saved-quiz-section${extraClass ? ` ${extraClass}` : ''}">
                <h3 class="saved-quiz-section-title"><i class="fa-solid ${icon}" aria-hidden="true"></i> ${title} <span class="saved-quiz-section-count">${count}</span></h3>
                ${contentHtml}
            </section>
        `;
    }

    function renderHomeRoot() {
        if (hasActiveHomeFilters()) {
            return buildFilteredResults(homeState.items, '');
        }
        const items = sortHomeItems(homeState.items);
        const favorites = items.filter(item => item?.isFavorite);
        const loose = items.filter(item => !item?.isFavorite && (!homeState.foldersSupported || item?.folderId == null));
        const sections = [];

        if (favorites.length > 0) {
            sections.push(buildQuizSection(
                'Favoris',
                'fa-star',
                `<div class="saved-quiz-cards saved-quiz-cards-grid">${favorites.map(buildOwnedQuizCard).join('')}</div>`,
                favorites.length,
                'is-favorites'
            ));
        }

        if (homeState.foldersSupported) {
            const folderCards = homeState.folders.map(buildFolderCard).join('');
            sections.push(buildQuizSection(
                'Dossiers',
                'fa-folder',
                `<div class="saved-quiz-cards saved-quiz-folders-grid">
                    ${folderCards}
                    <button type="button" class="saved-quiz-new-folder" data-action="new-folder" title="Créer un dossier (vous pouvez aussi y déposer une carte)">
                        <i class="fa-solid fa-folder-plus" aria-hidden="true"></i>
                        <span>Nouveau dossier</span>
                    </button>
                </div>
                ${homeState.folders.length === 0 ? '<p class="saved-quiz-hint"><i class="fa-regular fa-lightbulb" aria-hidden="true"></i> Glissez une carte sur une autre pour créer un dossier.</p>' : ''}`,
                homeState.folders.length,
                'is-folders'
            ));
        }

        sections.push(buildQuizSection(
            homeState.foldersSupported ? 'Questionnaires' : 'Autres questionnaires',
            'fa-layer-group',
            `<div class="saved-quiz-cards saved-quiz-cards-grid">${loose.map(buildOwnedQuizCard).join('')}${buildNewQuizCard()}</div>`,
            loose.length
        ));

        return `<div class="saved-quiz-sections">${sections.join('')}</div>`;
    }

    function renderHomeFolder(folder) {
        const folderItems = homeState.items.filter(item => item?.folderId === folder.id);
        const items = sortHomeItems(folderItems);
        const filtering = hasActiveHomeFilters();
        const color = normalizeQuizColorKey(folder.color) || 'indigo';
        const swatches = QUIZ_COLORS.map(entry => `
            <button type="button" class="quiz-swatch${entry.key === color ? ' is-selected' : ''}" data-action="folder-color" data-folder-id="${folder.id}" data-color="${entry.key}" aria-label="Couleur ${entry.label}" aria-pressed="${entry.key === color ? 'true' : 'false'}" title="${entry.label}"></button>
        `).join('');
        return `
            <div class="saved-quiz-folder-view" data-color="${color}">
                <div class="folder-view-bar">
                    <button type="button" class="folder-back-btn" data-action="close-folder" title="Revenir à l'accueil (déposez une carte ici pour la sortir du dossier)">
                        <i class="fa-solid fa-arrow-left" aria-hidden="true"></i><span>Mes questionnaires</span>
                    </button>
                    <i class="fa-solid fa-chevron-right folder-view-sep" aria-hidden="true"></i>
                    <span class="folder-view-icon" aria-hidden="true"><i class="fa-solid fa-folder-open"></i></span>
                    <input type="text" class="folder-name-input" data-folder-id="${folder.id}" value="${escapeHtml(folder.name || '')}" maxlength="80" aria-label="Nom du dossier" placeholder="Nom du dossier">
                    <div class="folder-view-tools">
                        <div class="quiz-swatches" role="group" aria-label="Couleur du dossier">${swatches}</div>
                        <button type="button" class="secondary-btn icon-only-btn folder-delete-btn" data-action="delete-folder" data-folder-id="${folder.id}" aria-label="Supprimer le dossier" title="Supprimer le dossier (les questionnaires sont conservés)">
                            <i class="fa-solid fa-trash" aria-hidden="true"></i>
                        </button>
                    </div>
                </div>
                ${filtering ? buildFilteredResults(folderItems, folder.name || 'Sans nom') : items.length > 0
                    ? `<div class="saved-quiz-cards saved-quiz-cards-grid">${items.map(buildOwnedQuizCard).join('')}</div>`
                    : '<p class="saved-quiz-empty">Ce dossier est vide. Revenez à l\'accueil et glissez-y des cartes, ou utilisez le menu <i class="fa-solid fa-ellipsis" aria-hidden="true"></i> d\'une carte.</p>'}
            </div>
        `;
    }

    function renderOwnedQuizzes() {
        if (!savedQuizzesPanel || !savedQuizCards) {
            return;
        }
        pendingHomeRender = false;
        closeQuizMenu({ skipRender: true });
        renderHomeHeader();
        renderHomeTagFilters();

        const hasContent = homeState.items.length > 0 || homeState.folders.length > 0;
        if (!hasContent) {
            homeState.openFolderId = null;
            savedQuizCards.innerHTML = '';
            savedQuizzesPanel.classList.add('hidden');
            updateHomePanelDensity();
            return;
        }

        const openFolder = homeState.foldersSupported ? getHomeFolder(homeState.openFolderId) : null;
        if (!openFolder) {
            homeState.openFolderId = null;
        }
        savedQuizCards.innerHTML = openFolder ? renderHomeFolder(openFolder) : renderHomeRoot();
        savedQuizzesPanel.classList.remove('hidden');
        updateHomePanelDensity();

        if (openFolder && homeState.focusFolderNameId === openFolder.id) {
            homeState.focusFolderNameId = null;
            const input = savedQuizCards.querySelector('.folder-name-input');
            if (input) {
                input.focus();
                input.select();
            }
        }
    }

    async function loadOwnedQuizzes() {
        if (!savedQuizzesPanel || !savedQuizCards) {
            return;
        }

        let items = [];
        let folders = [];
        let foldersSupported = false;
        try {
            const response = await fetchApi('list_quizzes.php');
            const data = await response.json();
            if (data.success && Array.isArray(data.items)) {
                items = data.items.filter(Boolean);
            }
            if (data.success && Array.isArray(data.folders)) {
                foldersSupported = true;
                folders = data.folders
                    .map(folder => ({
                        id: Number(folder?.id),
                        name: String(folder?.name || ''),
                        color: normalizeQuizColorKey(folder?.color) || 'indigo'
                    }))
                    .filter(folder => Number.isFinite(folder.id));
            }
        } catch (_) {
            // En cas d'erreur réseau, on affiche ce qui est disponible.
        }

        homeState.items = items.map(item => ({
            ...item,
            folderId: item.folderId === null || item.folderId === undefined ? null : Number(item.folderId),
            color: normalizeQuizColorKey(item.color),
            tags: Array.isArray(item.tags) ? item.tags.map(tag => String(tag || '').trim()).filter(Boolean) : []
        }));
        homeState.folders = folders;
        homeState.foldersSupported = foldersSupported;
        renderOwnedQuizzes();
    }

    async function organizeQuizzes(payload) {
        const response = await fetchApi('quiz_organize.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'Action impossible.');
        }
        return data;
    }

    async function createFolderWith(codes, { open = true } = {}) {
        const data = await organizeQuizzes({ action: 'create_folder', name: 'Nouveau dossier', codes });
        const folderId = Number(data.folder?.id);
        if (open && Number.isFinite(folderId)) {
            homeState.openFolderId = folderId;
            homeState.focusFolderNameId = folderId;
        }
        await loadOwnedQuizzes();
        return folderId;
    }

    async function runHomeAction(task, fallbackMessage) {
        try {
            await task();
        } catch (error) {
            alert(error.message || fallbackMessage);
            loadOwnedQuizzes();
        }
    }

    // Menu « ⋯ » d'une carte : ranger dans un dossier, couleur de la carte.
    let quizMenuEl = null;
    let quizMenuAnchor = null;

    function closeQuizMenu({ skipRender = false } = {}) {
        if (quizMenuEl) {
            quizMenuEl.remove();
            quizMenuEl = null;
        }
        if (quizMenuAnchor) {
            quizMenuAnchor.setAttribute('aria-expanded', 'false');
            quizMenuAnchor = null;
        }
        if (pendingHomeRender && !skipRender) {
            pendingHomeRender = false;
            renderOwnedQuizzes();
        }
    }

    function openQuizMenu(anchor, code) {
        const item = getHomeItem(code);
        if (!item) {
            return;
        }
        closeQuizMenu();
        const currentFolderId = item.folderId;
        const ownColor = normalizeQuizColorKey(item.color);
        const folder = getHomeFolder(currentFolderId);
        const inheritedColor = folder ? normalizeQuizColorKey(folder.color) : '';
        const folderRows = homeState.folders.map(entry => `
            <button type="button" role="menuitemradio" aria-checked="${entry.id === currentFolderId ? 'true' : 'false'}" class="quiz-menu-item" data-menu="move" data-folder-id="${entry.id}">
                <span class="quiz-menu-dot" data-color="${normalizeQuizColorKey(entry.color) || 'indigo'}" aria-hidden="true"></span>
                <span>${escapeHtml(entry.name || 'Sans nom')}</span>
                ${entry.id === currentFolderId ? '<i class="fa-solid fa-check quiz-menu-check" aria-hidden="true"></i>' : ''}
            </button>
        `).join('');
        const swatches = QUIZ_COLORS.map(entry => `
            <button type="button" class="quiz-swatch${entry.key === ownColor ? ' is-selected' : ''}" data-menu="color" data-color="${entry.key}" aria-label="Couleur ${entry.label}" aria-pressed="${entry.key === ownColor ? 'true' : 'false'}" title="${entry.label}"></button>
        `).join('');

        const menu = document.createElement('div');
        menu.className = 'quiz-menu';
        menu.setAttribute('role', 'menu');
        menu.dataset.code = String(item.code);
        menu.innerHTML = `
            <p class="quiz-menu-label">Ranger dans</p>
            <button type="button" role="menuitemradio" aria-checked="${currentFolderId === null ? 'true' : 'false'}" class="quiz-menu-item" data-menu="move" data-folder-id="">
                <i class="fa-solid fa-house quiz-menu-icon" aria-hidden="true"></i><span>Accueil (hors dossier)</span>
                ${currentFolderId === null ? '<i class="fa-solid fa-check quiz-menu-check" aria-hidden="true"></i>' : ''}
            </button>
            ${folderRows}
            <button type="button" role="menuitem" class="quiz-menu-item" data-menu="move-new">
                <i class="fa-solid fa-folder-plus quiz-menu-icon" aria-hidden="true"></i><span>Nouveau dossier…</span>
            </button>
            <div class="quiz-menu-sep" role="separator"></div>
            <p class="quiz-menu-label">Couleur de la carte</p>
            <div class="quiz-swatches">
                <button type="button" class="quiz-swatch quiz-swatch-auto${ownColor ? '' : ' is-selected'}" data-menu="color" data-color=""${inheritedColor ? ` data-inherit="${inheritedColor}"` : ''} aria-label="Couleur automatique (celle du dossier)" aria-pressed="${ownColor ? 'false' : 'true'}" title="${folder ? 'Celle du dossier' : 'Par défaut'}"></button>
                ${swatches}
            </div>
            <div class="quiz-menu-sep" role="separator"></div>
            <p class="quiz-menu-label">Étiquettes</p>
            <div class="quiz-menu-tags"></div>
            <form class="quiz-menu-tag-form" autocomplete="off">
                <input type="text" class="quiz-menu-tag-input" maxlength="30" list="quizTagSuggestions" placeholder="Ajouter une étiquette" aria-label="Ajouter une étiquette">
                <button type="submit" class="quiz-menu-tag-add" aria-label="Ajouter l'étiquette" title="Ajouter"><i class="fa-solid fa-plus" aria-hidden="true"></i></button>
                <datalist id="quizTagSuggestions">${getAllHomeTags().map(tag => `<option value="${escapeHtml(tag.label)}"></option>`).join('')}</datalist>
            </form>
        `;
        renderQuizMenuTags(menu, item);
        document.body.appendChild(menu);
        quizMenuEl = menu;
        quizMenuAnchor = anchor;
        anchor.setAttribute('aria-expanded', 'true');

        const rect = anchor.getBoundingClientRect();
        const menuRect = menu.getBoundingClientRect();
        let left = rect.right - menuRect.width;
        left = Math.max(8, Math.min(left, window.innerWidth - menuRect.width - 8));
        let top = rect.bottom + 6;
        if (top + menuRect.height > window.innerHeight - 8 && rect.top - menuRect.height - 6 > 8) {
            top = rect.top - menuRect.height - 6;
        }
        menu.style.left = `${Math.round(left + window.scrollX)}px`;
        menu.style.top = `${Math.round(top + window.scrollY)}px`;
        menu.querySelector('.quiz-menu-item')?.focus();

        menu.addEventListener('click', event => {
            const removeBtn = event.target.closest('[data-tag-remove]');
            if (removeBtn) {
                const index = Number(removeBtn.dataset.tagRemove);
                const tags = getItemTags(item).filter((_, i) => i !== index);
                saveQuizTags(menu, item, tags);
                menu.querySelector('.quiz-menu-tag-input')?.focus();
                return;
            }
            const target = event.target.closest('[data-menu]');
            if (!target) {
                return;
            }
            const menuCode = menu.dataset.code;
            const kind = target.dataset.menu;
            closeQuizMenu();
            if (kind === 'move') {
                const folderId = target.dataset.folderId === '' ? null : Number(target.dataset.folderId);
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'move', code: menuCode, folderId });
                    await loadOwnedQuizzes();
                }, 'Déplacement impossible.');
            } else if (kind === 'move-new') {
                runHomeAction(() => createFolderWith([menuCode]), 'Création du dossier impossible.');
            } else if (kind === 'color') {
                const color = target.dataset.color || null;
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'set_color', code: menuCode, color });
                    await loadOwnedQuizzes();
                }, 'Changement de couleur impossible.');
            }
        });
    }

    function renderQuizMenuTags(menu, item) {
        const container = menu.querySelector('.quiz-menu-tags');
        if (!container) {
            return;
        }
        const tags = getItemTags(item);
        container.innerHTML = tags.length > 0
            ? tags.map((tag, index) => `
                <span class="quiz-menu-tag">${escapeHtml(tag)}<button type="button" data-tag-remove="${index}" aria-label="Retirer l'étiquette ${escapeHtml(tag)}" title="Retirer"><i class="fa-solid fa-xmark" aria-hidden="true"></i></button></span>
            `).join('')
            : '<span class="quiz-menu-tags-empty">Aucune étiquette</span>';
    }

    function saveQuizTags(menu, item, tags) {
        const previous = getItemTags(item);
        item.tags = tags;
        pendingHomeRender = true;
        renderQuizMenuTags(menu, item);
        organizeQuizzes({ action: 'set_tags', code: item.code, tags })
            .then(data => {
                if (Array.isArray(data.tags)) {
                    item.tags = data.tags;
                    if (quizMenuEl === menu) {
                        renderQuizMenuTags(menu, item);
                    }
                }
            })
            .catch(error => {
                item.tags = previous;
                if (quizMenuEl === menu) {
                    renderQuizMenuTags(menu, item);
                }
                alert(error.message || 'Enregistrement des étiquettes impossible.');
            });
    }

    document.addEventListener('submit', event => {
        const form = event.target.closest?.('.quiz-menu-tag-form');
        if (!form || !quizMenuEl || !quizMenuEl.contains(form)) {
            return;
        }
        event.preventDefault();
        const input = form.querySelector('.quiz-menu-tag-input');
        const value = String(input?.value || '').trim().replace(/^#+/, '').replace(/\s+/g, ' ').slice(0, 30);
        const item = getHomeItem(quizMenuEl.dataset.code);
        if (!value || !item) {
            return;
        }
        const tags = getItemTags(item);
        if (tags.some(tag => tagKey(tag) === tagKey(value))) {
            input.value = '';
            return;
        }
        if (tags.length >= 12) {
            alert('12 étiquettes au maximum par questionnaire.');
            return;
        }
        input.value = '';
        saveQuizTags(quizMenuEl, item, tags.concat(value));
    });

    document.addEventListener('click', event => {
        if (!quizMenuEl) {
            return;
        }
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [event.target];
        if (path.includes(quizMenuEl) || event.target.closest?.('[data-action="card-menu"]') === quizMenuAnchor) {
            return;
        }
        closeQuizMenu();
    });
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && quizMenuEl) {
            const anchor = quizMenuAnchor;
            closeQuizMenu();
            anchor?.focus();
        }
    });
    window.addEventListener('resize', closeQuizMenu);

    async function loadTrashQuizzes() {
        if (!trashQuizzesPanel || !trashQuizSelect) {
            return;
        }
        try {
            const response = await fetchApi('list_deleted_quizzes.php');
            const data = await response.json();
            if (!data.success || !Array.isArray(data.items) || data.items.length === 0) {
                trashQuizzesPanel.classList.add('hidden');
                return;
            }

            trashQuizSelect.innerHTML = data.items.map(item => {
                const title = String(item.title || '').trim() || '(sans titre)';
                const code = String(item.code || '').trim();
                return `<option value="${escapeHtml(code)}">${escapeHtml(title)} (${escapeHtml(code)})</option>`;
            }).join('');
            trashQuizzesPanel.classList.remove('hidden');
        } catch (_) {
            trashQuizzesPanel.classList.add('hidden');
        } finally {
            updateHomePanelDensity();
        }
    }

    async function loadQuizByCode(code) {
        if (!code) {
            return;
        }
        const resp = await fetchApi(`get_batch.php?code=${encodeURIComponent(code)}`);
        const data = await resp.json();
        if (!data.success) {
            throw new Error(data.error || 'Impossible de charger ce questionnaire.');
        }

        state.code = data.code;
        state.quizTitle = String(data.quizTitle || '');
        state.participantReportEnabled = normalizeParticipantReportEnabled(data.participantReportEnabled);
        state.requireParticipantName = normalizeRequireParticipantName(data.requireParticipantName);
        state.batch = normalizeBatchQuestionTiming(
            Array.isArray(data.batch) ? data.batch : [],
            Number.isInteger(data.currentIndex) ? data.currentIndex : 0,
            data.currentQuestionStartedAtMs
        );
        const rawCurrentIndex = Number.isInteger(data.currentIndex) ? data.currentIndex : 0;
        state.currentIndex = Math.max(0, Math.min(rawCurrentIndex, Math.max(0, state.batch.length - 1)));
        const wasLive = !!data.liveActive;
        state.liveActive = false;
        if (wasLive && state.code) {
            try {
                await fetchApi('set_live.php', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ code: state.code, liveActive: false })
                });
            } catch (_) {
                // On continue côté UI même si la fermeture serveur échoue.
            }
        }
        if (Array.isArray(state.batch) && state.batch[state.currentIndex] && typeof state.batch[state.currentIndex] === 'object') {
            state.batch[state.currentIndex].questionStartedAtMs = null;
        }
        // Réinitialise le contexte live/résultats pour éviter les effets de timer hérités d'une session précédente.
        state.revealCorrectAnswer = false;
        state.showParticipantResponses = true;
        state.participantResponsesVisibilityOverrides = {};
        state.currentResultsQuestionKey = null;
        state.latestResultsSnapshot = null;
        state.latestQuestionSignature = '';
        state.lastStatsSignature = null;
        state.resultsTotalQuestions = Math.max(1, state.batch.length);
        state.showingFinalReport = false;
        state.latestFinalReport = null;
        state.wordcloudScaleMode = 'compact';
        stopResultsQuestionTimer();
        const resultsTimerEl = document.getElementById('resultsQuestionTimer');
        if (resultsTimerEl) {
            resultsTimerEl.classList.add('hidden');
        }
        if (Number.isFinite(Number(data.serverNowMs))) {
            presenterServerOffsetMs = Number(data.serverNowMs) - Date.now();
        }
        renderBatchEditor(state.batch);
        if (quizTitleInput) {
            quizTitleInput.value = state.quizTitle;
        }
        if (participantReportEnabledInput) {
            participantReportEnabledInput.checked = state.participantReportEnabled;
        }
        if (requireParticipantNameInput) {
            requireParticipantNameInput.checked = state.requireParticipantName !== false;
        }

        safeSetLocalStorage(SESSION_CODE_KEY, state.code);
        saveBatchState();
        renderLiveQuestion();
    }

    async function deleteOwnedQuiz(code) {
        const resp = await fetchApi('delete_batch.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ code })
        });
        const data = await resp.json();
        if (!data.success) {
            throw new Error(data.error || 'Suppression impossible.');
        }
    }

    async function exportQuizMarkdownByCode(code) {
        const safeCode = String(code || '').trim();
        if (!safeCode) {
            throw new Error('Code manquant pour export.');
        }
        const resp = await fetchApi(`get_batch.php?code=${encodeURIComponent(safeCode)}`);
        const data = await resp.json();
        if (!data.success) {
            throw new Error(data.error || 'Export impossible.');
        }
        const markdown = buildQuizMarkdown(
            data.quizTitle || 'Questionnaire',
            data.code || safeCode,
            data.batch || [],
            data.participantReportEnabled
        );
        const filename = `${slugifyFilename(data.quizTitle || safeCode)}.md`;
        downloadTextFile(markdown, filename);
    }

    function escapeMd(value) {
        return String(value ?? '')
            .replace(/\\/g, '\\\\')
            .replace(/\|/g, '\\|')
            .replace(/`/g, '\\`')
            .trim();
    }

    function unescapeMd(value) {
        return String(value ?? '')
            .replace(/\\([\\|`])/g, '$1')
            .trim();
    }

    function buildQuizMarkdown(quizTitle, code, batch, participantReportEnabled = false) {
        const title = (quizTitle || '').trim() || 'Questionnaire';
        const lines = [];
        lines.push(`# ${escapeMd(title)}`);
        lines.push('');
        lines.push(`- Code: \`${escapeMd(code || '')}\``);
        lines.push(`- Nombre de questions: ${Array.isArray(batch) ? batch.length : 0}`);
        lines.push(`- Rapport participant: ${normalizeParticipantReportEnabled(participantReportEnabled) ? 'activé' : 'désactivé'}`);
        lines.push('');

        (batch || []).forEach((q, index) => {
            const qType = normalizeQuestionType(q.type);
            const participantResponsesVisible = normalizeParticipantResponsesVisibility(q.participantResponsesVisible);
            lines.push(`## Question ${index + 1}`);
            lines.push('');
            lines.push(escapeMd(extractQuestionPlainText(q.question || '')));
            lines.push('');

            if (qType === 'multiple') {
                const answers = Array.isArray(q.answers) ? q.answers : [];
                answers.forEach((answer, i) => {
                    const isCorrect = Number(q.correctIndex) === i;
                    lines.push(`- ${isCorrect ? '[x]' : '[ ]'} ${escapeMd(answer)}`);
                });
                lines.push('');
            } else if (qType === 'checkbox') {
                lines.push('- Type: cases à cocher');
                const answers = Array.isArray(q.answers) ? q.answers : [];
                let correctIndexes = Array.isArray(q.correctIndexes)
                    ? q.correctIndexes.map(value => parseInt(value, 10)).filter(value => Number.isInteger(value) && value >= 0)
                    : [];
                if (correctIndexes.length === 0 && Number.isInteger(q.correctIndex) && q.correctIndex >= 0) {
                    correctIndexes = [q.correctIndex];
                }
                answers.forEach((answer, i) => {
                    const isCorrect = correctIndexes.includes(i);
                    lines.push(`- ${isCorrect ? '[x]' : '[ ]'} ${escapeMd(answer)}`);
                });
                lines.push('');
            } else if (qType === 'open') {
                lines.push('- Type: question ouverte');
                if (normalizeOpenResponseFormat(q.responseFormat) === 'math') {
                    lines.push('- Format de réponse: mathématique');
                }
                lines.push('');
            } else if (qType === 'cloze') {
                lines.push('- Type: texte à trous');
                lines.push('- Texte à trous:');
                lines.push('```');
                lines.push(String(q.clozeText || '').trim());
                lines.push('```');
                lines.push('');
            } else if (qType === 'wordcloud') {
                lines.push('- Type: nuage de mots');
                lines.push('');
            } else if (qType === 'rating') {
                lines.push('- Type: notation en étoiles (1 à 5)');
                lines.push('');
            } else if (qType === 'ranking') {
                lines.push('- Type: classement');
                lines.push('- Éléments à classer:');
                lines.push('```');
                const rankingItems = Array.isArray(q.answers) ? q.answers : [];
                rankingItems.forEach(item => lines.push(String(item || '').trim()));
                lines.push('```');
                lines.push('');
            } else if (qType === 'video') {
                lines.push('- Type: vidéo YouTube');
                lines.push(`- URL vidéo: ${escapeMd(q.youtubeUrl || '')}`);
                if (normalizeVideoBoundarySec(q.videoStartSec) !== null) {
                    lines.push(`- Début vidéo (s): ${normalizeVideoBoundarySec(q.videoStartSec)}`);
                }
                if (normalizeVideoBoundarySec(q.videoEndSec) !== null) {
                    lines.push(`- Fin vidéo (s): ${normalizeVideoBoundarySec(q.videoEndSec)}`);
                }
                lines.push('');
            } else if (qType === 'labelimage') {
                const imageUrl = isValidQuestionImage(q.questionImage) ? String(q.questionImage).trim() : '';
                const zoom = normalizeQuestionImageZoom(q.questionImageZoom);
                const labels = normalizeLegendLabels(q.legendLabels)
                    .filter(label => label.text)
                    .map((label, labelIndex) => ({
                        id: String(label.id || `lbl${labelIndex + 1}`),
                        text: String(label.text || ''),
                        x: label.x === null ? null : Number(Number(label.x).toFixed(2)),
                        y: label.y === null ? null : Number(Number(label.y).toFixed(2))
                    }));
                lines.push('- Type: légender une image');
                lines.push(`- Image: ${escapeMd(imageUrl)}`);
                lines.push(`- Zoom image: ${Number(zoom).toFixed(2)}`);
                lines.push('- Étiquettes:');
                lines.push('```json');
                JSON.stringify(labels, null, 2).split('\n').forEach(line => lines.push(line));
                lines.push('```');
                lines.push('');
            }
            if (qType !== 'video' && !participantResponsesVisible) {
                lines.splice(lines.length - 1, 0, '- Réponses des participants: masquées');
            }
        });

        return `${lines.join('\n').trim()}\n`;
    }

    function parseQuizMarkdown(markdown) {
        const text = String(markdown || '').replace(/\r\n/g, '\n');
        const lines = text.split('\n');
        const titleLine = lines.find(line => /^#\s+/.test(line.trim()));
        const quizTitle = titleLine ? unescapeMd(titleLine.replace(/^#\s+/, '')) : 'Questionnaire importé';
        const reportLine = lines.find(line => /^-\s*rapport\s+participant\s*:/i.test(line.trim()));
        let participantReportEnabled = false;
        if (reportLine) {
            const reportMatch = reportLine.match(/^-\s*rapport\s+participant\s*:\s*(.+)$/i);
            if (reportMatch) {
                participantReportEnabled = normalizeParticipantReportEnabled(unescapeMd(reportMatch[1] || ''));
            }
        }
        const nameLine = lines.find(line => /^-\s*nom\s+participant\s*:/i.test(line.trim()));
        let requireParticipantName = true;
        if (nameLine) {
            const nameMatch = nameLine.match(/^-\s*nom\s+participant\s*:\s*(.+)$/i);
            if (nameMatch) {
                requireParticipantName = normalizeRequireParticipantName(unescapeMd(nameMatch[1] || ''));
            }
        }

        const questionHeaderIndexes = [];
        lines.forEach((line, idx) => {
            if (/^##\s+question\b/i.test(line.trim())) {
                questionHeaderIndexes.push(idx);
            }
        });

        if (questionHeaderIndexes.length === 0) {
            throw new Error("Aucune section 'Question' trouvée dans ce fichier Markdown.");
        }

        const batch = [];
        questionHeaderIndexes.forEach((startIdx, blockIndex) => {
            const endIdx = questionHeaderIndexes[blockIndex + 1] ?? lines.length;
            const blockLines = lines.slice(startIdx + 1, endIdx).map(line => line.trim());

            const questionLine = blockLines.find(line => line !== '' && !line.startsWith('-'));
            const question = unescapeMd(questionLine || '');
            if (!question) {
                return;
            }

            const bullets = blockLines.filter(line => /^-\s+/.test(line));
            const checklistAnswers = [];
            let checkedCount = 0;
            let correctIndex = 0;
            let checkboxCorrectIndexes = [];
            let explicitType = '';
            let responseFormat = 'text';
            let clozeText = '';
            let rankingItems = [];
            let youtubeUrl = '';
            let videoStartSec = null;
            let videoEndSec = null;
            let labelImageUrl = '';
            let labelImageZoom = 1;
            let labelImageLabels = [];
            let participantResponsesVisible = true;

            bullets.forEach(line => {
                const multipleMatch = line.match(/^-\s+\[([xX ])\]\s+(.+)$/);
                if (multipleMatch) {
                    const checked = multipleMatch[1].toLowerCase() === 'x';
                    const answer = unescapeMd(multipleMatch[2] || '');
                    if (answer) {
                        if (checked) {
                            correctIndex = checklistAnswers.length;
                            checkedCount += 1;
                            checkboxCorrectIndexes.push(checklistAnswers.length);
                        }
                        checklistAnswers.push(answer);
                    }
                    return;
                }

                const typeMatch = line.match(/^-\s*Type\s*:\s*(.+)$/i);
                if (typeMatch) {
                    explicitType = String(typeMatch[1] || '').toLowerCase();
                }

                const responseFormatMatch = line.match(/^-\s*(?:format|type)\s+de\s+r[ée]ponse\s*:\s*(.+)$/i)
                    || line.match(/^-\s*r[ée]ponse\s*:\s*(.+)$/i);
                if (responseFormatMatch) {
                    const rawResponseFormat = String(responseFormatMatch[1] || '').trim().toLowerCase();
                    if (
                        rawResponseFormat === 'math'
                        || rawResponseFormat === 'maths'
                        || rawResponseFormat === 'mathématique'
                        || rawResponseFormat === 'mathematique'
                        || rawResponseFormat === 'réponse mathématique'
                        || rawResponseFormat === 'reponse mathematique'
                        || rawResponseFormat === 'latex'
                    ) {
                        responseFormat = 'math';
                    }
                }

                const imageMatch = line.match(/^-\s*(?:URL\s*)?image\s*:\s*(.+)$/i);
                if (imageMatch) {
                    labelImageUrl = unescapeMd(imageMatch[1] || '');
                }

                const videoStartMatch = line.match(/^-\s*(?:d[ée]but|debut)\s*vid[ée]o(?:\s*\(s\))?\s*:\s*(.+)$/i);
                if (videoStartMatch) {
                    videoStartSec = normalizeVideoBoundarySec(unescapeMd(videoStartMatch[1] || ''));
                }

                const videoEndMatch = line.match(/^-\s*fin\s*vid[ée]o(?:\s*\(s\))?\s*:\s*(.+)$/i);
                if (videoEndMatch) {
                    videoEndSec = normalizeVideoBoundarySec(unescapeMd(videoEndMatch[1] || ''));
                }

                const zoomMatch = line.match(/^-\s*(?:zoom(?:\s+image)?|image\s+zoom)\s*:\s*(.+)$/i);
                if (zoomMatch) {
                    const zoomValue = Number(String(zoomMatch[1] || '').replace(',', '.'));
                    if (Number.isFinite(zoomValue)) {
                        labelImageZoom = normalizeQuestionImageZoom(zoomValue);
                    }
                }

                const participantResponsesMatch = line.match(/^-\s*r[ée]ponses?\s+des\s+participants\s*:\s*(.+)$/i)
                    || line.match(/^-\s*afficher\s+les\s+r[ée]ponses?\s+des\s+participants\s*:\s*(.+)$/i);
                if (participantResponsesMatch) {
                    participantResponsesVisible = normalizeParticipantResponsesVisibility(
                        unescapeMd(participantResponsesMatch[1] || '')
                    );
                }
            });

            const clozeSingleLine = blockLines.find(line => /^-\s*Texte\s*(a|à)\s*trous\s*:\s*(.+)$/i.test(line));
            if (clozeSingleLine) {
                const match = clozeSingleLine.match(/^-\s*Texte\s*(a|à)\s*trous\s*:\s*(.+)$/i);
                clozeText = unescapeMd(match?.[2] || '');
            } else {
                const clozeMarker = blockLines.findIndex(line => /^-\s*Texte\s*(a|à)\s*trous\s*:\s*$/i.test(line));
                if (clozeMarker !== -1 && blockLines[clozeMarker + 1] === '```') {
                    const endFence = blockLines.findIndex((line, idx) => idx > clozeMarker + 1 && line === '```');
                    if (endFence !== -1) {
                        clozeText = blockLines.slice(clozeMarker + 2, endFence).join('\n').trim();
                    }
                }
            }

            const videoSingleLine = blockLines.find(line => /^-\s*URL\s*vid[eé]o\s*:\s*(.+)$/i.test(line));
            if (videoSingleLine) {
                const match = videoSingleLine.match(/^-\s*URL\s*vid[eé]o\s*:\s*(.+)$/i);
                youtubeUrl = unescapeMd(match?.[1] || '');
            }

            const rankingSingleLine = blockLines.find(line => /^-\s*[ée]l[ée]ments?\s*[aà]\s*classer\s*:\s*(.+)$/i.test(line));
            if (rankingSingleLine) {
                const match = rankingSingleLine.match(/^-\s*[ée]l[ée]ments?\s*[aà]\s*classer\s*:\s*(.+)$/i);
                rankingItems = parseRankingLines(unescapeMd(match?.[1] || '').replace(/\s*\|\s*/g, '\n'));
            } else {
                const rankingMarker = blockLines.findIndex(line => /^-\s*[ée]l[ée]ments?\s*[aà]\s*classer\s*:\s*$/i.test(line));
                if (rankingMarker !== -1 && blockLines[rankingMarker + 1] === '```') {
                    const endFence = blockLines.findIndex((line, idx) => idx > rankingMarker + 1 && line === '```');
                    if (endFence !== -1) {
                        rankingItems = parseRankingLines(blockLines.slice(rankingMarker + 2, endFence).join('\n'));
                    }
                }
            }

            const labelsSingleLine = blockLines.find(line => /^-\s*[ée]tiquettes?\s*:\s*(.+)$/i.test(line));
            if (labelsSingleLine) {
                const match = labelsSingleLine.match(/^-\s*[ée]tiquettes?\s*:\s*(.+)$/i);
                const raw = unescapeMd(match?.[1] || '').replace(/\s*;\s*/g, '\n');
                labelImageLabels = parseLegendLabelsMarkdown(raw);
            } else {
                const labelsMarker = blockLines.findIndex(line => /^-\s*[ée]tiquettes?\s*:\s*$/i.test(line));
                if (labelsMarker !== -1 && /^```/.test(blockLines[labelsMarker + 1] || '')) {
                    const endFence = blockLines.findIndex((line, idx) => idx > labelsMarker + 1 && line === '```');
                    if (endFence !== -1) {
                        const raw = blockLines.slice(labelsMarker + 2, endFence).join('\n').trim();
                        labelImageLabels = parseLegendLabelsMarkdown(raw);
                    }
                }
            }

            const normalizedExplicitType = normalizeQuestionType(explicitType);
            const rankingHintInQuestion = /class(?:e|er|ez|ement)|ordre|chronolog/i.test(question);
            if (normalizedExplicitType === 'ranking' && rankingItems.length < 2 && checklistAnswers.length >= 2) {
                rankingItems = checklistAnswers.slice();
            }
            if (rankingItems.length < 2 && checklistAnswers.length >= 2 && checkedCount === 0 && rankingHintInQuestion) {
                rankingItems = checklistAnswers.slice();
            }

            if (normalizedExplicitType === 'wordcloud') {
                batch.push({ type: 'wordcloud', question, answers: [], correctIndex: null, participantResponsesVisible });
                return;
            }
            if (normalizedExplicitType === 'cloze') {
                batch.push({ type: 'cloze', question, clozeText, answers: [], correctIndex: null, participantResponsesVisible });
                return;
            }
            if (normalizedExplicitType === 'open') {
                batch.push({
                    type: 'open',
                    question,
                    answers: [],
                    correctIndex: null,
                    responseFormat: normalizeOpenResponseFormat(responseFormat),
                    participantResponsesVisible
                });
                return;
            }
            if (normalizedExplicitType === 'rating') {
                batch.push({ type: 'rating', question, answers: [], correctIndex: null, maxRating: 5, participantResponsesVisible });
                return;
            }
            if (normalizedExplicitType === 'ranking' || rankingItems.length >= 2) {
                batch.push({ type: 'ranking', question, answers: rankingItems, correctIndex: null, participantResponsesVisible });
                return;
            }
            if (normalizedExplicitType === 'video') {
                const parsedVideoRange = normalizeVideoRange(videoStartSec, videoEndSec);
                batch.push({
                    type: 'video',
                    question,
                    youtubeUrl,
                    videoStartSec: parsedVideoRange.startSec,
                    videoEndSec: parsedVideoRange.endSec,
                    answers: [],
                    correctIndex: null,
                    participantResponsesVisible: true
                });
                return;
            }
            if (normalizedExplicitType === 'labelimage') {
                batch.push({
                    type: 'labelimage',
                    question,
                    answers: [],
                    correctIndex: null,
                    questionImage: isValidQuestionImage(labelImageUrl) ? labelImageUrl : '',
                    questionImageZoom: normalizeQuestionImageZoom(labelImageZoom),
                    legendLabels: normalizeLegendLabels(labelImageLabels),
                    participantResponsesVisible
                });
                return;
            }
            if (normalizedExplicitType === 'checkbox') {
                if (checklistAnswers.length >= 2) {
                    batch.push({
                        type: 'checkbox',
                        question,
                        answers: checklistAnswers,
                        correctIndex: null,
                        correctIndexes: checkboxCorrectIndexes,
                        participantResponsesVisible
                    });
                    return;
                }
                batch.push({ type: 'open', question, answers: [], correctIndex: null, participantResponsesVisible });
                return;
            }

            if (checklistAnswers.length >= 2) {
                if (checkedCount > 1) {
                    batch.push({
                        type: 'checkbox',
                        question,
                        answers: checklistAnswers,
                        correctIndex: null,
                        correctIndexes: checkboxCorrectIndexes,
                        participantResponsesVisible
                    });
                    return;
                }
                if (correctIndex < 0 || correctIndex >= checklistAnswers.length) {
                    correctIndex = 0;
                }
                batch.push({
                    type: 'multiple',
                    question,
                    answers: checklistAnswers,
                    correctIndex,
                    participantResponsesVisible
                });
                return;
            }

            batch.push({ type: 'open', question, answers: [], correctIndex: null, participantResponsesVisible });
        });

        if (batch.length === 0) {
            throw new Error('Aucune question exploitable trouvée dans le fichier.');
        }

        return { quizTitle, batch, participantReportEnabled, requireParticipantName };
    }

    function slugifyFilename(value) {
        const base = String(value || 'questionnaire')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '');
        return base || 'questionnaire';
    }

    function downloadTextFile(content, filename) {
        const blob = new Blob([content], { type: 'text/markdown;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    function responseUrl(code) {
        const url = new URL('r.html', window.location.href);
        url.searchParams.set('c', code);
        return url.toString();
    }

    function responseEntryUrl() {
        return new URL('r.html', window.location.href).toString();
    }

    function buildQrCodeUrl(targetUrl) {
        const params = new URLSearchParams({
            text: targetUrl,
            size: '512',
            margin: '0',
            dark: '6366f1',
            light: '0000',
            ecLevel: 'M'
        });
        return `https://quickchart.io/qr?${params.toString()}`;
    }

    function ensureSessionCorner() {
        let corner = document.getElementById('sessionCorner');
        if (corner) {
            return corner;
        }

        corner = document.createElement('div');
        corner.id = 'sessionCorner';
        corner.className = 'session-corner hidden';
        corner.innerHTML = `
            <p class="session-corner-title"><i class="fa-solid fa-link" aria-hidden="true"></i>Session</p>
            <img id="sessionCornerQr" alt="QR session">
            <p class="session-corner-code-label">Code</p>
            <p id="sessionCornerCode" class="session-corner-code"></p>
        `;
        const codeEl = corner.querySelector('#sessionCornerCode');
        const codeLabelEl = corner.querySelector('.session-corner-code-label');
        const isMobileView = () => window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
        const toggleMobileQr = () => {
            if (!isMobileView()) {
                return;
            }
            corner.classList.toggle('is-expanded-mobile');
            if (codeEl) {
                codeEl.setAttribute('aria-expanded', corner.classList.contains('is-expanded-mobile') ? 'true' : 'false');
            }
        };
        if (codeEl) {
            codeEl.setAttribute('role', 'button');
            codeEl.setAttribute('tabindex', '0');
            codeEl.setAttribute('aria-expanded', 'false');
            codeEl.setAttribute('title', 'Afficher/masquer le QR code');
            codeEl.addEventListener('click', toggleMobileQr);
            codeEl.addEventListener('keydown', function(e) {
                if (e.key !== 'Enter' && e.key !== ' ') {
                    return;
                }
                e.preventDefault();
                toggleMobileQr();
            });
        }
        if (codeLabelEl) {
            codeLabelEl.addEventListener('click', toggleMobileQr);
        }
        document.body.appendChild(corner);
        return corner;
    }

    function isResultsTabActive() {
        const resultsTab = document.getElementById('resultsTab');
        return !!resultsTab && resultsTab.classList.contains('active');
    }

    function updateSessionCorner(code) {
        const corner = ensureSessionCorner();
        const qr = document.getElementById('sessionCornerQr');
        const codeEl = document.getElementById('sessionCornerCode');
        if (!corner || !qr || !codeEl) {
            return;
        }

        if (!code || !isResultsTabActive()) {
            corner.classList.remove('is-expanded-mobile');
            corner.classList.add('hidden');
            syncPresencePolling();
            return;
        }

        const url = responseUrl(code);
        qr.src = buildQrCodeUrl(url);
        codeEl.textContent = code;
        if (window.matchMedia && !window.matchMedia('(max-width: 640px)').matches) {
            corner.classList.remove('is-expanded-mobile');
            codeEl.setAttribute('aria-expanded', 'false');
        }
        corner.classList.remove('hidden');
        syncPresencePolling();
    }

    function ensureConnectedAudienceBadge() {
        let badge = document.getElementById('connectedAudienceBadge');
        if (badge) {
            return badge;
        }

        badge = document.createElement('div');
        badge.id = 'connectedAudienceBadge';
        badge.className = 'connected-audience-badge hidden';
        badge.setAttribute('aria-live', 'polite');
        badge.setAttribute('aria-label', 'Participants connectés');
        badge.innerHTML = `
            <i class="fa-solid fa-users" aria-hidden="true"></i>
            <span id="connectedAudienceCount">0</span>
        `;
        document.body.appendChild(badge);
        return badge;
    }

    function shouldShowConnectedAudienceBadge() {
        if (!state.code) {
            return false;
        }
        if (!editorPanel || editorPanel.classList.contains('hidden')) {
            return false;
        }
        const liveVisible = !!createSuccess && !createSuccess.classList.contains('hidden');
        return liveVisible || isResultsTabActive();
    }

    function updateConnectedAudienceBadge(count, isStale = false) {
        const badge = ensureConnectedAudienceBadge();
        if (!badge) {
            return;
        }
        if (!shouldShowConnectedAudienceBadge()) {
            badge.classList.add('hidden');
            badge.classList.remove('is-stale');
            return;
        }

        const countEl = document.getElementById('connectedAudienceCount');
        const safeCount = Math.max(0, Math.trunc(Number(count) || 0));
        if (countEl) {
            countEl.textContent = String(safeCount);
        }
        badge.classList.toggle('is-stale', !!isStale);
        badge.title = `${safeCount} participant(s) connecté(s) (activité ≤ ${PRESENCE_ACTIVE_WINDOW_SECONDS}s)`;
        badge.classList.remove('hidden');
    }

    async function refreshConnectedAudienceCount() {
        if (!shouldShowConnectedAudienceBadge() || !state.code) {
            updateConnectedAudienceBadge(0);
            return;
        }

        const code = String(state.code || '').trim();
        if (!code) {
            updateConnectedAudienceBadge(0);
            return;
        }

        try {
            const resp = await fetchApi(`get_presence_count.php?code=${encodeURIComponent(code)}`);
            const data = await resp.json();
            if (!data.success) {
                throw new Error(data.error || 'Impossible de récupérer la présence.');
            }
            if (state.code !== code) {
                return;
            }
            state.connectedParticipants = Math.max(0, Math.trunc(Number(data.connectedCount || 0)));
            updateConnectedAudienceBadge(state.connectedParticipants, false);
        } catch (_) {
            updateConnectedAudienceBadge(state.connectedParticipants, true);
        }
    }

    function stopPresencePolling() {
        if (presencePollTimer) {
            clearInterval(presencePollTimer);
            presencePollTimer = null;
        }
        lastPresencePollingCode = '';
    }

    function startPresencePolling() {
        if (presencePollTimer) {
            return;
        }
        presencePollTimer = setInterval(function() {
            refreshConnectedAudienceCount();
        }, PRESENCE_POLL_INTERVAL_MS);
    }

    function syncPresencePolling() {
        if (!shouldShowConnectedAudienceBadge()) {
            stopPresencePolling();
            lastPresencePollingCode = '';
            updateConnectedAudienceBadge(0);
            return;
        }
        const activeCode = String(state.code || '').trim();
        const mustRefreshNow = !presencePollTimer || activeCode !== lastPresencePollingCode;
        startPresencePolling();
        if (activeCode !== '') {
            lastPresencePollingCode = activeCode;
        }
        if (mustRefreshNow) {
            refreshConnectedAudienceCount();
        }
    }

    function generateCode() {
        return String(100000 + secureRandomInt(900000));
    }

    function getOrCreateSessionCode(forceNew = false) {
        let code = localStorage.getItem(SESSION_CODE_KEY);
        if (!code || forceNew) {
            const previousCode = code || '';
            code = generateCode();
            while (code === previousCode) {
                code = generateCode();
            }
            safeSetLocalStorage(SESSION_CODE_KEY, code);
        }
        return code;
    }

    function saveBatchState() {
        safeSetLocalStorage(BATCH_STATE_KEY, JSON.stringify({
            code: state.code,
            quizTitle: state.quizTitle,
            participantReportEnabled: !!state.participantReportEnabled,
            requireParticipantName: state.requireParticipantName !== false,
            batch: sanitizeBatchForLocalStorage(state.batch),
            currentIndex: state.currentIndex,
            liveActive: !!state.liveActive
        }));
    }

    function isMeaningfulDraftTitle(title) {
        return String(title || '').trim().length > 0;
    }

    function isMeaningfulDraftBatch(batch) {
        if (!Array.isArray(batch)) {
            return false;
        }
        return batch.some(item => {
            if (!item || typeof item !== 'object') {
                return false;
            }
            const question = extractQuestionPlainText(item.question || '');
            const type = normalizeQuestionType(item.type);
            if (question) {
                return true;
            }
            if (supportsQuestionImage(type) && String(item.questionImage || '').trim() !== '') {
                return true;
            }
            if (isChoiceQuestionType(type)) {
                return (Array.isArray(item.answers) ? item.answers : []).some(a => String(a || '').trim() !== '');
            }
            if (type === 'cloze') {
                return String(item.clozeText || '').trim() !== '';
            }
            if (type === 'ranking') {
                return (Array.isArray(item.answers) ? item.answers : parseRankingLines(item.rankingText || '')).length > 0;
            }
            if (type === 'video') {
                return String(item.youtubeUrl || '').trim() !== '';
            }
            if (type === 'labelimage') {
                return normalizeLegendLabels(item.legendLabels).some(label => label.text || (label.x !== null && label.y !== null));
            }
            return false;
        });
    }

    function hasMeaningfulDraftData(data) {
        if (!data || typeof data !== 'object') {
            return false;
        }
        return isMeaningfulDraftTitle(data.quizTitle) || isMeaningfulDraftBatch(data.batch);
    }

    function loadEditorDraft() {
        try {
            const raw = localStorage.getItem(EDITOR_DRAFT_KEY);
            if (!raw) {
                return null;
            }
            const parsed = JSON.parse(raw);
            if (!parsed || !Array.isArray(parsed.batch)) {
                return null;
            }
            return parsed;
        } catch (_) {
            return null;
        }
    }

    function clearEditorDraft() {
        localStorage.removeItem(EDITOR_DRAFT_KEY);
    }

    function collectDraftFromEditor() {
        const blocks = Array.from(batchQuestions.querySelectorAll('.batch-question-block'));
        const batch = blocks.map(block => {
            const question = getQuestionEditorHtml(block.querySelector('.batch-question-input'));
            const type = normalizeQuestionType(block.querySelector('.batch-question-type')?.value);
            const questionImage = supportsQuestionImage(type) ? getQuestionImageFromBlock(block) : '';
            const questionImageZoom = supportsQuestionImage(type) ? getQuestionImageZoomFromBlock(block) : 1;
            const responseFormat = normalizeOpenResponseFormat(block.querySelector('.batch-open-math-toggle')?.checked ? 'math' : 'text');
            const participantResponsesVisible = normalizeParticipantResponsesVisibility(block.querySelector('.batch-participant-responses-toggle')?.checked);

            if (!isChoiceQuestionType(type)) {
                const item = {
                    type,
                    question,
                    answers: [],
                    correctIndex: null,
                    participantResponsesVisible,
                    questionImage,
                    questionImageZoom
                };
                if (type === 'rating') {
                    item.maxRating = 5;
                }
                if (type === 'open') {
                    item.responseFormat = responseFormat;
                }
                if (type === 'cloze') {
                    item.clozeText = (block.querySelector('.batch-cloze-text')?.value || '').trim();
                }
                if (type === 'ranking') {
                    item.answers = collectRankingItemsFromBlock(block);
                }
                if (type === 'video') {
                    item.youtubeUrl = (block.querySelector('.batch-video-url')?.value || '').trim();
                    const draftVideoRange = normalizeVideoRange(
                        block.querySelector('.batch-video-start-sec')?.value,
                        block.querySelector('.batch-video-end-sec')?.value
                    );
                    item.videoStartSec = draftVideoRange.startSec;
                    item.videoEndSec = draftVideoRange.endSec;
                }
                if (type === 'labelimage') {
                    item.legendLabels = collectLegendLabelsFromBlock(block);
                }
                return item;
            }

            const answers = Array.from(block.querySelectorAll('.batch-answer-input')).map(input => input.value || '');
            const isPollMode = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
            if (type === 'multiple') {
                const checked = block.querySelector('.correct-marker-input:checked');
                const correctIndex = checked ? parseInt(checked.value, 10) : 0;
                return {
                    type: 'multiple',
                    question,
                    answers,
                    isPollMode,
                    correctIndex: isPollMode ? null : (Number.isInteger(correctIndex) ? correctIndex : 0),
                    participantResponsesVisible,
                    questionImage,
                    questionImageZoom
                };
            }
            return {
                type: 'checkbox',
                question,
                answers,
                isPollMode,
                correctIndex: null,
                correctIndexes: isPollMode ? [] : Array.from(block.querySelectorAll('.correct-marker-input:checked'))
                    .map(input => parseInt(input.value, 10))
                    .filter(index => Number.isInteger(index) && index >= 0),
                participantResponsesVisible,
                questionImage,
                questionImageZoom
            };
        });

        return {
            code: state.code || '',
            quizTitle: (quizTitleInput?.value || '').trim(),
            participantReportEnabled: normalizeParticipantReportEnabled(participantReportEnabledInput?.checked),
            requireParticipantName: normalizeRequireParticipantName(requireParticipantNameInput?.checked),
            batch,
            updatedAt: new Date().toISOString()
        };
    }

    function saveEditorDraft(force = false) {
        if (!questionForm || questionForm.classList.contains('hidden')) {
            return;
        }

        const draft = collectDraftFromEditor();
        if (!force && !hasMeaningfulDraftData(draft)) {
            return;
        }

        if (!hasMeaningfulDraftData(draft)) {
            clearEditorDraft();
            return;
        }

        const safeDraft = {
            ...draft,
            batch: sanitizeBatchForLocalStorage(draft.batch)
        };
        safeSetLocalStorage(EDITOR_DRAFT_KEY, JSON.stringify(safeDraft));
    }

    function scheduleEditorDraftSave() {
        if (draftSaveTimer) {
            clearTimeout(draftSaveTimer);
        }
        draftSaveTimer = setTimeout(() => {
            saveEditorDraft();
            draftSaveTimer = null;
        }, 300);
    }

    async function syncEditorToServer(options = {}) {
        const force = !!options.force;
        if (!questionForm || questionForm.classList.contains('hidden')) {
            return;
        }
        if (isSubmittingBatch) {
            return;
        }

        const quizTitle = (quizTitleInput?.value || '').trim();
        if (!quizTitle) {
            return;
        }

        const draft = collectDraftFromEditor();
        if (!hasMeaningfulDraftData(draft)) {
            return;
        }

        const collected = collectBatchFromEditor();
        const hasValidBatch = !collected.error && Array.isArray(collected.batch) && collected.batch.length > 0;
        const draftMode = !hasValidBatch;
        const batchToSave = hasValidBatch ? collected.batch : [];
        if (!draftMode && !force && hasInlineQuestionImage(batchToSave)) {
            return;
        }

        state.code = state.code || getOrCreateSessionCode();
        state.quizTitle = quizTitle;
        state.participantReportEnabled = normalizeParticipantReportEnabled(participantReportEnabledInput?.checked);
        state.requireParticipantName = normalizeRequireParticipantName(requireParticipantNameInput?.checked);
        if (!draftMode) {
            state.batch = batchToSave;
            state.currentIndex = Math.max(0, Math.min(state.currentIndex || 0, state.batch.length - 1));
        } else {
            state.currentIndex = 0;
            state.liveActive = false;
        }

        try {
            const payload = {
                mode: 'batch',
                code: state.code,
                quizTitle: state.quizTitle,
                participantReportEnabled: !!state.participantReportEnabled,
                requireParticipantName: state.requireParticipantName !== false,
                batch: batchToSave,
                currentIndex: state.currentIndex,
                liveActive: draftMode ? false : !!state.liveActive,
                resetAllResponses: false,
                draftMode
            };
            const resp = await fetchApi('save_question.php', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            const data = await resp.json();
            if (!data.success) {
                throw new Error(data.error || 'Sauvegarde brouillon impossible.');
            }
            saveBatchState();
        } catch (_) {
            // Le brouillon local reste la sauvegarde de secours.
        }
    }

    function scheduleServerDraftSave() {
        if (serverDraftSaveTimer) {
            clearTimeout(serverDraftSaveTimer);
        }
        serverDraftSaveTimer = setTimeout(() => {
            syncEditorToServer();
            serverDraftSaveTimer = null;
        }, 900);
    }

    function applyEditorDraft(draft) {
        if (!draft || !Array.isArray(draft.batch)) {
            return false;
        }

        state.code = String(draft.code || '').trim() || null;
        state.runId = Array.isArray(draft.batch) && draft.batch[0] && typeof draft.batch[0] === 'object'
            ? String(draft.batch[0].runId || '').trim() || null
            : null;
        state.quizTitle = String(draft.quizTitle || '').trim();
        state.participantReportEnabled = normalizeParticipantReportEnabled(draft.participantReportEnabled);
        state.requireParticipantName = normalizeRequireParticipantName(draft.requireParticipantName);
        state.batch = normalizeBatchQuestionTiming(draft.batch);
        state.currentIndex = 0;
        state.liveActive = false;
        state.revealCorrectAnswer = false;
        state.showParticipantResponses = true;
        state.participantResponsesVisibilityOverrides = {};
        state.currentResultsQuestionKey = null;
        state.latestResultsSnapshot = null;
        state.latestQuestionSignature = '';
        state.lastStatsSignature = null;
        state.resultsTotalQuestions = 1;
        state.showingFinalReport = false;
        state.latestFinalReport = null;
        state.wordcloudScaleMode = 'compact';

        localStorage.removeItem(SESSION_CODE_KEY);
        localStorage.removeItem(BATCH_STATE_KEY);

        renderBatchEditor(state.batch);
        if (quizTitleInput) {
            quizTitleInput.value = state.quizTitle;
        }
        if (participantReportEnabledInput) {
            participantReportEnabledInput.checked = state.participantReportEnabled;
        }
        if (requireParticipantNameInput) {
            requireParticipantNameInput.checked = state.requireParticipantName !== false;
        }
        return true;
    }

    function captureEditorRange(editor) {
        const selection = window.getSelection();
        if (!editor || !selection || selection.rangeCount === 0) {
            return null;
        }
        const range = selection.getRangeAt(0);
        if (!editor.contains(range.commonAncestorContainer)) {
            return null;
        }
        return range.cloneRange();
    }

    function insertTextIntoInputLike(element, text, selectionStart = null, selectionEnd = null) {
        if (!element) {
            return;
        }
        const start = Number.isInteger(selectionStart) ? selectionStart : Number(element.selectionStart ?? element.value.length);
        const end = Number.isInteger(selectionEnd) ? selectionEnd : Number(element.selectionEnd ?? start);
        const before = String(element.value || '').slice(0, start);
        const after = String(element.value || '').slice(end);
        const nextValue = `${before}${text}${after}`;
        element.value = nextValue;
        const nextCursor = before.length + text.length;
        if (typeof element.setSelectionRange === 'function') {
            element.setSelectionRange(nextCursor, nextCursor);
        }
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        element.focus();
    }

    function insertTextIntoEditor(editor, text, savedRange = null) {
        if (!editor) {
            return;
        }
        const range = savedRange || captureEditorRange(editor);
        editor.focus();
        const selection = window.getSelection();

        if (!range || !selection) {
            editor.appendChild(document.createTextNode(text));
            normalizeQuestionEditorMarkup(editor);
            editor.dispatchEvent(new Event('input', { bubbles: true }));
            return;
        }

        range.deleteContents();
        const textNode = document.createTextNode(text);
        range.insertNode(textNode);
        const nextRange = document.createRange();
        nextRange.setStartAfter(textNode);
        nextRange.collapse(true);
        selection.removeAllRanges();
        selection.addRange(nextRange);
        normalizeQuestionEditorMarkup(editor);
        editor.dispatchEvent(new Event('input', { bubbles: true }));
    }

    function updateMathInsertPreview() {
        if (!mathInsertPreview || !mathInsertField) {
            return;
        }
        const latex = String(mathInsertField.value || '').trim();
        if (!latex) {
            mathInsertPreview.innerHTML = '<p class="math-preview-placeholder">Aucune formule pour le moment.</p>';
            return;
        }
        mathInsertPreview.textContent = `\\(${latex}\\)`;
        renderMathInElementSafe(mathInsertPreview);
    }

    function openMathInsertModal(target) {
        if (!mathInsertModal || !mathInsertField) {
            return;
        }
        pendingMathInsertionTarget = target;
        mathInsertModal.classList.remove('hidden');
        mathInsertModal.setAttribute('aria-hidden', 'false');
        mathInsertField.value = '';
        updateMathInsertPreview();
        mathInsertField.focus();
        if (window.mathVirtualKeyboard && typeof window.mathVirtualKeyboard.show === 'function') {
            window.mathVirtualKeyboard.show();
        }
    }

    function closeMathInsertModal() {
        if (!mathInsertModal || !mathInsertField) {
            return;
        }
        mathInsertModal.classList.add('hidden');
        mathInsertModal.setAttribute('aria-hidden', 'true');
        if (window.mathVirtualKeyboard && typeof window.mathVirtualKeyboard.hide === 'function') {
            window.mathVirtualKeyboard.hide();
        }
        mathInsertField.value = '';
        pendingMathInsertionTarget = null;
    }

    function applyMathInsertion() {
        if (!pendingMathInsertionTarget || !mathInsertField) {
            closeMathInsertModal();
            return;
        }
        const latex = String(mathInsertField.value || '').trim();
        if (!latex) {
            return;
        }
        const insertion = `\\(${latex}\\)`;
        if (pendingMathInsertionTarget.kind === 'editor') {
            insertTextIntoEditor(
                pendingMathInsertionTarget.element,
                insertion,
                pendingMathInsertionTarget.range || captureEditorRange(pendingMathInsertionTarget.element)
            );
        } else if (pendingMathInsertionTarget.kind === 'input') {
            insertTextIntoInputLike(
                pendingMathInsertionTarget.element,
                insertion,
                pendingMathInsertionTarget.start,
                pendingMathInsertionTarget.end
            );
        }
        closeMathInsertModal();
    }

    function syncQuestionEditorPlaceholder(editor) {
        if (!editor) {
            return;
        }
        if (editor.innerHTML === '<br>' || editor.innerHTML === '<div><br></div>') {
            editor.innerHTML = '';
        }
        editor.classList.toggle('is-empty', extractQuestionPlainText(editor.innerHTML) === '');
    }

    function setQuestionEditorContent(editor, value) {
        if (!editor) {
            return;
        }
        editor.innerHTML = sanitizeQuestionRichTextHtml(value);
        syncQuestionEditorPlaceholder(editor);
    }

    function normalizeQuestionEditorMarkup(editor) {
        if (!editor) {
            return;
        }
        const sanitized = sanitizeQuestionRichTextHtml(editor.innerHTML);
        if (editor.innerHTML !== sanitized) {
            editor.innerHTML = sanitized;
        }
        syncQuestionEditorPlaceholder(editor);
    }

    function getQuestionEditorHtml(editor) {
        if (!editor) {
            return '';
        }
        return sanitizeQuestionRichTextHtml(editor.innerHTML);
    }

    function ensureQuestionFormatToolbar() {
        if (questionFormatToolbar) {
            return questionFormatToolbar;
        }

        const toolbar = document.createElement('div');
        toolbar.className = 'question-format-toolbar hidden';
        toolbar.setAttribute('role', 'toolbar');
        toolbar.setAttribute('aria-label', 'Mise en forme de la question');
        toolbar.innerHTML = `
            <button type="button" class="secondary-btn question-format-toolbar-btn" data-command="bold" aria-label="Gras" title="Gras (Ctrl/Cmd+B)">
                <i class="fa-solid fa-bold" aria-hidden="true"></i>
            </button>
            <button type="button" class="secondary-btn question-format-toolbar-btn" data-command="italic" aria-label="Italique" title="Italique (Ctrl/Cmd+I)">
                <i class="fa-solid fa-italic" aria-hidden="true"></i>
            </button>
            <button type="button" class="secondary-btn question-format-toolbar-btn" data-command="underline" aria-label="Souligné" title="Souligné (Ctrl/Cmd+U)">
                <i class="fa-solid fa-underline" aria-hidden="true"></i>
            </button>
            <span class="question-format-toolbar-divider" aria-hidden="true"></span>
            <button type="button" class="secondary-btn question-format-toolbar-btn" data-command="insertOrderedList" aria-label="Liste numérotée" title="Liste numérotée">
                <i class="fa-solid fa-list-ol" aria-hidden="true"></i>
            </button>
            <button type="button" class="secondary-btn question-format-toolbar-btn" data-command="insertUnorderedList" aria-label="Liste à puces" title="Liste à puces">
                <i class="fa-solid fa-list-ul" aria-hidden="true"></i>
            </button>
        `;

        toolbar.addEventListener('mousedown', function(event) {
            event.preventDefault();
        });
        toolbar.addEventListener('click', function(event) {
            const button = event.target.closest('[data-command]');
            if (!button || !activeQuestionEditor) {
                return;
            }
            activeQuestionEditor.focus();
            try {
                document.execCommand('styleWithCSS', false, false);
            } catch (_) {}
            document.execCommand(button.dataset.command, false, null);
            syncQuestionEditorPlaceholder(activeQuestionEditor);
            window.requestAnimationFrame(refreshQuestionFormatToolbar);
        });

        document.body.appendChild(toolbar);
        questionFormatToolbar = toolbar;
        return toolbar;
    }

    function hideQuestionFormatToolbar() {
        if (questionFormatToolbar) {
            questionFormatToolbar.classList.add('hidden');
        }
    }

    function isSelectionInsideQuestionEditor(editor) {
        if (!editor) {
            return false;
        }
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) {
            return false;
        }
        const range = selection.getRangeAt(0);
        return editor.contains(range.commonAncestorContainer);
    }

    function refreshQuestionFormatToolbar() {
        const toolbar = ensureQuestionFormatToolbar();
        if (!activeQuestionEditor || !isSelectionInsideQuestionEditor(activeQuestionEditor)) {
            hideQuestionFormatToolbar();
            return;
        }

        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
            hideQuestionFormatToolbar();
            return;
        }

        const range = selection.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        if (!rect || (rect.width === 0 && rect.height === 0)) {
            hideQuestionFormatToolbar();
            return;
        }

        toolbar.classList.remove('hidden');
        const toolbarRect = toolbar.getBoundingClientRect();
        const preferredTop = rect.top - toolbarRect.height - 12;
        const top = preferredTop >= 8 ? preferredTop : rect.bottom + 12;
        const left = Math.min(
            Math.max(8, rect.left + (rect.width / 2) - (toolbarRect.width / 2)),
            window.innerWidth - toolbarRect.width - 8
        );
        toolbar.style.top = `${top}px`;
        toolbar.style.left = `${left}px`;

        toolbar.querySelectorAll('[data-command]').forEach(button => {
            const command = button.dataset.command;
            let isActive = false;
            if (command) {
                try {
                    isActive = document.queryCommandState(command);
                } catch (_) {
                    isActive = false;
                }
            }
            button.classList.toggle('is-active', isActive);
        });
    }

    function handleQuestionEditorShortcut(event) {
        const isModifierPressed = event.ctrlKey || event.metaKey;
        if (!isModifierPressed || event.altKey) {
            return;
        }

        const key = String(event.key || '').toLowerCase();
        if (key !== 'b' && key !== 'i' && key !== 'u') {
            return;
        }

        event.preventDefault();
        try {
            document.execCommand('styleWithCSS', false, false);
        } catch (_) {}
        if (key === 'b') {
            document.execCommand('bold', false, null);
        } else if (key === 'i') {
            document.execCommand('italic', false, null);
        } else if (key === 'u') {
            document.execCommand('underline', false, null);
        }
        syncQuestionEditorPlaceholder(event.currentTarget);
        window.requestAnimationFrame(refreshQuestionFormatToolbar);
    }

    function setupQuestionRichTextEditor(block, value) {
        const editor = block.querySelector('.batch-question-input');
        if (!editor) {
            return;
        }

        setQuestionEditorContent(editor, value);
        editor.addEventListener('focus', function() {
            activeQuestionEditor = editor;
            syncQuestionEditorPlaceholder(editor);
        });
        editor.addEventListener('input', function() {
            syncQuestionEditorPlaceholder(editor);
        });
        editor.addEventListener('mouseup', function() {
            activeQuestionEditor = editor;
            window.requestAnimationFrame(refreshQuestionFormatToolbar);
        });
        editor.addEventListener('keyup', function() {
            activeQuestionEditor = editor;
            window.requestAnimationFrame(refreshQuestionFormatToolbar);
        });
        editor.addEventListener('keydown', handleQuestionEditorShortcut);
        editor.addEventListener('blur', function() {
            window.setTimeout(function() {
                normalizeQuestionEditorMarkup(editor);
                if (!isSelectionInsideQuestionEditor(editor)) {
                    hideQuestionFormatToolbar();
                }
            }, 0);
        });
    }

    function createQuestionBlock(data = {}) {
        const uid = `q${Date.now()}${Math.floor(Math.random() * 10000)}`;
        const question = data.question || '';
        const questionHtml = sanitizeQuestionRichTextHtml(question);
        const responseFormat = normalizeOpenResponseFormat(data.responseFormat);
        const type = normalizeQuestionType(data.type);
        const participantResponsesVisible = normalizeParticipantResponsesVisibility(
            Object.prototype.hasOwnProperty.call(data || {}, 'participantResponsesVisible')
                ? data.participantResponsesVisible
                : data.showParticipantResponses
        );
        const questionImage = isValidQuestionImage(data.questionImage) ? String(data.questionImage).trim() : '';
        const questionImageZoom = normalizeQuestionImageZoom(data.questionImageZoom);
        const canUseImage = supportsQuestionImage(type);
        const isChoiceType = isChoiceQuestionType(type);
        const isLabelImage = type === 'labelimage';
        const isPollMode = isChoiceType && !!(data.isPollMode);
        const providedAnswers = Array.isArray(data.answers) ? data.answers : [];
        const answers = providedAnswers.map(value => String(value || '')).slice(0, MAX_MULTIPLE_ANSWERS);
        const safeCorrectIndex = Number.isInteger(data.correctIndex) ? data.correctIndex : 0;
        const correctIndex = safeCorrectIndex >= 0 && safeCorrectIndex < Math.max(answers.length, 2) ? safeCorrectIndex : 0;
        const providedCorrectIndexes = Array.isArray(data.correctIndexes) ? data.correctIndexes : [];
        let correctIndexes = providedCorrectIndexes
            .map(value => parseInt(value, 10))
            .filter(index => Number.isInteger(index) && index >= 0 && index < Math.max(answers.length, 2));
        if (type === 'checkbox' && correctIndexes.length === 0 && Number.isInteger(data.correctIndex) && data.correctIndex >= 0) {
            correctIndexes = [data.correctIndex];
        }
        const clozeText = String(data.clozeText ?? '');
        const rankingText = typeof data.rankingText === 'string'
            ? String(data.rankingText)
            : (Array.isArray(data.answers) ? data.answers.map(item => String(item || '').trim()).filter(Boolean).join('\n') : '');
        const rankingItems = parseRankingLines(rankingText);
        const youtubeUrl = String(data.youtubeUrl ?? '');
        const videoRange = normalizeVideoRange(data.videoStartSec, data.videoEndSec);
        const videoStartSec = videoRange.startSec;
        const videoEndSec = videoRange.endSec;
        const legendLabels = normalizeLegendLabels(data.legendLabels);
        const timeLimitSec = normalizeQuestionTimeLimit(data.timeLimitSec);
        const timeLimitOptionsHtml = QUESTION_TIME_LIMIT_OPTIONS.map(seconds => {
            const label = seconds < 60
                ? `${seconds} secondes`
                : (seconds % 60 === 0
                    ? `${Math.trunc(seconds / 60)} minute${seconds === 60 ? '' : 's'}`
                    : `${Math.trunc(seconds / 60)} min ${seconds % 60} s`);
            return `<option value="${seconds}" ${timeLimitSec === seconds ? 'selected' : ''}>${label}</option>`;
        }).join('');
        const clozeTextSafe = clozeText
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
        const youtubeUrlSafe = youtubeUrl
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
        const videoStartSafe = formatVideoBoundaryInput(videoStartSec);
        const videoEndSafe = formatVideoBoundaryInput(videoEndSec);
        const questionImageSafe = String(questionImage)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;');
        const block = document.createElement('div');
        block.className = 'batch-question-block';
        block.dataset.uid = uid;
        block.dataset.type = type;
        block.dataset.questionImageZoom = String(questionImageZoom);

        block.innerHTML = `
            <div class="batch-question-header">
                <div class="batch-question-header-left">
                    <button type="button" class="secondary-btn icon-only-btn drag-question-handle" draggable="true" aria-label="Déplacer la question" title="Glisser pour déplacer">
                        <i class="fa-solid fa-grip-vertical" aria-hidden="true"></i>
                    </button>
                    <h3 class="batch-question-title"><i class="fa-solid fa-circle-question" aria-hidden="true"></i> Question</h3>
                </div>
                <div class="batch-question-actions">
                    <button type="button" class="secondary-btn move-up-btn icon-only-btn" aria-label="Monter la question" title="Monter">
                        <i class="fa-solid fa-arrow-up" aria-hidden="true"></i>
                    </button>
                    <button type="button" class="secondary-btn move-down-btn icon-only-btn" aria-label="Descendre la question" title="Descendre">
                        <i class="fa-solid fa-arrow-down" aria-hidden="true"></i>
                    </button>
                    <button type="button" class="secondary-btn remove-question-btn icon-only-btn" aria-label="Supprimer la question" title="Supprimer la question">
                        <i class="fa-solid fa-trash" aria-hidden="true"></i>
                    </button>
                </div>
            </div>

            <div class="form-group compact-question-input-row">
                <div class="batch-question-editor-wrap">
                    <button type="button" class="secondary-btn icon-only-btn open-math-editor-btn question-math-insert-btn" data-target-kind="question" aria-label="Insérer une formule dans la question" title="Insérer une formule">
                        <span class="math-tool-icon" aria-hidden="true">∑</span>
                    </button>
                    <div
                    class="batch-question-input"
                    contenteditable="true"
                    role="textbox"
                    aria-multiline="true"
                    aria-label="Intitulé de la question"
                    data-placeholder="Intitulé de la question"
                    spellcheck="true"
                >${questionHtml}</div>
                </div>
            </div>

            <div class="question-settings-grid" role="group" aria-label="Réglages de la question">
                <div class="form-group question-type-row">
                    <label class="q-chip q-chip-select" for="type-${uid}" title="Type de question">
                        <i class="fa-solid fa-shapes q-chip-icon" aria-hidden="true"></i>
                        <select id="type-${uid}" class="batch-question-type" aria-label="Type de question">
                            <option value="multiple" ${type === 'multiple' ? 'selected' : ''}>Choix unique</option>
                            <option value="checkbox" ${type === 'checkbox' ? 'selected' : ''}>Cases à cocher</option>
                            <option value="ranking" ${type === 'ranking' ? 'selected' : ''}>Classement (ordre)</option>
                            <option value="labelimage" ${type === 'labelimage' ? 'selected' : ''}>Légender une image</option>
                            <option value="rating" ${type === 'rating' ? 'selected' : ''}>Note (1 à 5 étoiles)</option>
                            <option value="open" ${type === 'open' ? 'selected' : ''}>Question ouverte</option>
                            <option value="wordcloud" ${type === 'wordcloud' ? 'selected' : ''}>Nuage de mots</option>
                            <option value="cloze" ${type === 'cloze' ? 'selected' : ''}>Texte à trous</option>
                            <option value="video" ${type === 'video' ? 'selected' : ''}>Vidéo YouTube</option>
                        </select>
                        <i class="fa-solid fa-chevron-down q-chip-caret" aria-hidden="true"></i>
                    </label>
                </div>

                <div class="form-group question-timer-row ${type === 'video' ? 'hidden' : ''}">
                    <label class="q-chip q-chip-select" for="timer-${uid}" title="Temps de réponse">
                        <i class="fa-regular fa-clock q-chip-icon" aria-hidden="true"></i>
                        <select id="timer-${uid}" class="batch-time-limit-select" aria-label="Temps de réponse" ${type === 'video' ? 'disabled' : ''}>
                            ${timeLimitOptionsHtml}
                        </select>
                        <i class="fa-solid fa-chevron-down q-chip-caret" aria-hidden="true"></i>
                    </label>
                </div>

                <div class="form-group question-image-toggle-row ${canUseImage && !isLabelImage ? '' : 'hidden'}">
                    <button type="button" class="q-chip toggle-question-image-fields-btn" aria-label="Ajouter une image à la question" title="Ajouter une image sous l'intitulé">
                        <i class="fa-regular fa-image q-chip-icon" aria-hidden="true"></i>
                        <span>Image</span>
                    </button>
                </div>

                <div class="form-group question-participant-responses-row ${type === 'video' ? 'hidden' : ''}">
                    <label class="q-switch" title="Afficher les réponses des participants pendant la question">
                        <input type="checkbox" class="batch-participant-responses-toggle" role="switch" ${participantResponsesVisible ? 'checked' : ''}>
                        <span class="q-switch-track" aria-hidden="true"></span>
                        <span class="q-switch-label">Afficher les réponses</span>
                    </label>
                </div>
            </div>

            <div class="form-group question-image-fields ${(canUseImage && questionImage && !isLabelImage) ? '' : 'hidden'}">
                <label for="image-${uid}">Insérer une image</label>
                <input id="image-${uid}" type="file" class="batch-question-image-input" accept="image/png,image/jpeg,image/webp,image/gif">
                <input type="hidden" class="batch-question-image-data" value="${questionImageSafe}">
                <div class="batch-question-image-preview ${questionImage ? '' : 'hidden'}">
                    <img class="batch-question-image-preview-img" alt="Aperçu de l'image de question">
                    <div class="question-image-zoom-controls" aria-label="Contrôles de zoom de l'image">
                        <button type="button" class="secondary-btn icon-only-btn question-image-zoom-btn" data-action="out" aria-label="Zoom arrière" title="Zoom arrière">
                            <i class="fa-solid fa-magnifying-glass-minus" aria-hidden="true"></i>
                        </button>
                        <span class="question-image-zoom-value" aria-live="polite">100%</span>
                        <button type="button" class="secondary-btn icon-only-btn question-image-zoom-btn" data-action="in" aria-label="Zoom avant" title="Zoom avant">
                            <i class="fa-solid fa-magnifying-glass-plus" aria-hidden="true"></i>
                        </button>
                    </div>
                    <button type="button" class="clear-question-image-btn" aria-label="Supprimer l'image" title="Supprimer l'image">
                        <i class="fa-solid fa-trash" aria-hidden="true"></i>
                    </button>
                </div>
            </div>

            <div class="question-multiple-fields ${!isChoiceType ? 'hidden' : ''}">
                <div class="responses-possibles-header">
                    <h4 class="responses-possibles-heading">Réponses possibles</h4>
                    <div class="question-poll-mode-row">
                        <label class="q-switch" title="Aucune réponse n'est considérée comme correcte">
                            <input type="checkbox" class="batch-poll-mode-toggle" role="switch" ${isPollMode ? 'checked' : ''}>
                            <span class="q-switch-track" aria-hidden="true"></span>
                            <span class="q-switch-label">Sondage <span class="q-switch-hint">sans bonne réponse</span></span>
                        </label>
                    </div>
                </div>
                <div class="batch-multiple-builder">
                    <div class="batch-multiple-items"></div>
                    <button type="button" class="secondary-btn add-multiple-option-btn">
                        <i class="fa-solid fa-circle-plus" aria-hidden="true"></i>Ajouter une option
                    </button>
                </div>
            </div>

            <div class="question-open-fields ${isChoiceType ? 'hidden' : ''}">
                <p class="open-question-help ${getOpenQuestionHelpText(type) ? '' : 'hidden'}">${getOpenQuestionHelpText(type)}</p>
                <div class="form-group question-open-response-row ${type === 'open' ? '' : 'hidden'}">
                    <label class="inline-checkbox-label">
                        <input type="checkbox" class="batch-open-math-toggle" ${responseFormat === 'math' ? 'checked' : ''}>
                        <span>Réponse mathématique</span>
                    </label>
                </div>
                <div class="question-cloze-fields ${type !== 'cloze' ? 'hidden' : ''}">
                    <label for="cloze-${uid}">Texte à trous</label>
                    <textarea id="cloze-${uid}" class="batch-cloze-text" rows="8" placeholder="Exemple : Le masque de la mort [rouge] est une nouvelle de {{Poe, Stevenson, Dickens}}" ${type === 'cloze' ? 'required' : ''}>${clozeTextSafe}</textarea>
                    <p class="cloze-example-label">Exemple :</p>
                    <p class="cloze-example-text">Le masque de la mort [rouge] est une nouvelle de {{Poe, Stevenson, Dickens}}</p>
                </div>
                <div class="question-ranking-fields ${type !== 'ranking' ? 'hidden' : ''}">
                    <label>Éléments à classer</label>
                    <div class="batch-ranking-builder">
                        <div class="batch-ranking-items"></div>
                        <button type="button" class="secondary-btn add-ranking-item-btn">
                            <i class="fa-solid fa-circle-plus" aria-hidden="true"></i>Ajouter un élément
                        </button>
                    </div>
                    <p class="cloze-example-label">Astuce :</p>
                    <p class="cloze-example-text">L'ordre saisi ici correspond à l'ordre attendu.</p>
                </div>
                <div class="question-video-fields ${type !== 'video' ? 'hidden' : ''}">
                    <label for="video-${uid}">URL YouTube</label>
                    <input id="video-${uid}" type="url" class="batch-video-url" placeholder="https://www.youtube.com/watch?v=..." value="${youtubeUrlSafe}" ${type === 'video' ? 'required' : ''}>
                    <div class="video-range-row">
                        <div class="video-range-field">
                            <label for="video-start-${uid}">Début (mm:ss ou secondes)</label>
                            <input id="video-start-${uid}" type="text" class="batch-video-start-sec" inputmode="text" placeholder="Ex : 1:30" value="${videoStartSafe}">
                        </div>
                        <div class="video-range-field">
                            <label for="video-end-${uid}">Fin (mm:ss ou secondes)</label>
                            <input id="video-end-${uid}" type="text" class="batch-video-end-sec" inputmode="text" placeholder="Ex : 2:10" value="${videoEndSafe}">
                        </div>
                    </div>
                    <p class="video-range-help">Optionnel : définissez un extrait à lire (début/fin). Format accepté : <code>mm:ss</code> (ex. <code>1:30</code>) ou secondes (ex. <code>90</code>).</p>
                </div>
                <div class="question-labelimage-fields ${type !== 'labelimage' ? 'hidden' : ''}">
                    <div class="question-labelimage-image-fields">
                        <label for="labelimage-${uid}">Image à légender</label>
                        <div class="question-labelimage-image-row">
                            <input id="labelimage-${uid}" type="file" class="batch-question-image-input" accept="image/png,image/jpeg,image/webp,image/gif">
                            <button type="button" class="secondary-btn icon-only-btn clear-labelimage-btn ${questionImage ? '' : 'hidden'}" aria-label="Supprimer l'image à légender" title="Supprimer l'image">
                                <i class="fa-solid fa-trash" aria-hidden="true"></i>
                            </button>
                        </div>
                    </div>
                    <label>Étiquettes à placer</label>
                    <div class="labelimage-editor">
                        <div class="labelimage-canvas-wrap">
                            <div class="legend-editor-canvas is-empty">
                                <img class="legend-editor-image" alt="Image à légender">
                                <div class="legend-editor-overlay"></div>
                                <p class="legend-editor-empty">Ajoutez une image puis cliquez dessus pour placer les points.</p>
                            </div>
                            <p class="legend-editor-instruction">Sélectionnez une étiquette puis cliquez sur l'image.</p>
                        </div>
                        <div class="labelimage-sidebar">
                            <div class="batch-legend-label-items"></div>
                            <button type="button" class="secondary-btn add-legend-label-btn">
                                <i class="fa-solid fa-circle-plus" aria-hidden="true"></i>Ajouter une étiquette
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        setupQuestionRichTextEditor(block, question);

        setupMultipleChoiceEditor(block, uid, answers, correctIndex, correctIndexes);
        updateChoiceEditorMode(block, type);
        setupRankingEditor(block, rankingItems);
        setupLegendEditor(block, legendLabels);
        updateQuestionImagePreview(block);
        setupQuestionImageZoomControls(block);

        return block;
    }

    function updateQuestionBlockTitles() {
        const blocks = Array.from(batchQuestions.querySelectorAll('.batch-question-block'));
        blocks.forEach((block, index) => {
            const title = block.querySelector('.batch-question-title');
            const removeBtn = block.querySelector('.remove-question-btn');
            const upBtn = block.querySelector('.move-up-btn');
            const downBtn = block.querySelector('.move-down-btn');
            title.textContent = `Question ${index + 1}`;
            removeBtn.classList.toggle('hidden', blocks.length === 1);
            if (upBtn) {
                upBtn.disabled = index === 0;
            }
            if (downBtn) {
                downBtn.disabled = index === blocks.length - 1;
            }
        });
    }

    function getDropAfterQuestionBlock(y) {
        const candidateBlocks = Array.from(batchQuestions.querySelectorAll('.batch-question-block'))
            .filter(block => block !== draggedQuestionBlock);

        for (const block of candidateBlocks) {
            const rect = block.getBoundingClientRect();
            const middle = rect.top + (rect.height / 2);
            if (y < middle) {
                return block;
            }
        }
        return null;
    }

    function clearQuestionDragState() {
        batchQuestions.classList.remove('drag-active');
        if (draggedQuestionBlock) {
            draggedQuestionBlock.classList.remove('is-dragging');
            draggedQuestionBlock = null;
        }
    }

    function renderBatchEditor(batch = []) {
        batchQuestions.innerHTML = '';
        if (!Array.isArray(batch) || batch.length === 0) {
            batchQuestions.appendChild(createQuestionBlock());
        } else {
            batch.forEach(item => batchQuestions.appendChild(createQuestionBlock(item)));
        }
        updateQuestionBlockTitles();
        updateLiveParticipantResponsesButton();
    }

    function collectBatchFromEditor() {
        const blocks = Array.from(batchQuestions.querySelectorAll('.batch-question-block'));
        const batch = [];

        for (const block of blocks) {
            const question = getQuestionEditorHtml(block.querySelector('.batch-question-input'));
            const type = normalizeQuestionType(block.querySelector('.batch-question-type')?.value);
            const questionImage = supportsQuestionImage(type) ? getQuestionImageFromBlock(block) : '';
            const questionImageZoom = supportsQuestionImage(type) ? getQuestionImageZoomFromBlock(block) : 1;
            const responseFormat = normalizeOpenResponseFormat(block.querySelector('.batch-open-math-toggle')?.checked ? 'math' : 'text');
            const participantResponsesVisible = normalizeParticipantResponsesVisibility(block.querySelector('.batch-participant-responses-toggle')?.checked);
            const timeLimitSec = type === 'video'
                ? DEFAULT_QUESTION_TIME_LIMIT_SEC
                : normalizeQuestionTimeLimit(block.querySelector('.batch-time-limit-select')?.value);

            if (!extractQuestionPlainText(question)) {
                return { error: "Merci de remplir l'intitulé de chaque question." };
            }

            if (!isChoiceQuestionType(type)) {
                const clozeText = (block.querySelector('.batch-cloze-text')?.value || '').trim();
                const rankingItems = collectRankingItemsFromBlock(block);
                const youtubeUrl = (block.querySelector('.batch-video-url')?.value || '').trim();
                const videoStartRaw = (block.querySelector('.batch-video-start-sec')?.value || '').trim();
                const videoEndRaw = (block.querySelector('.batch-video-end-sec')?.value || '').trim();
                const hasVideoStart = videoStartRaw !== '';
                const hasVideoEnd = videoEndRaw !== '';
                const videoStartParsed = hasVideoStart ? normalizeVideoBoundarySec(videoStartRaw) : null;
                const videoEndParsed = hasVideoEnd ? normalizeVideoBoundarySec(videoEndRaw) : null;
                const legendLabels = normalizeLegendLabels(collectLegendLabelsFromBlock(block));
                if (type === 'cloze' && !clozeText) {
                    return { error: 'Merci de renseigner le texte à trous pour chaque question de ce type.' };
                }
                if (type === 'ranking') {
                    if (rankingItems.length < 2) {
                        return { error: 'Chaque question de classement doit contenir au moins 2 éléments (une ligne par élément).' };
                    }
                    const unique = new Set(rankingItems.map(item => item.toLowerCase()));
                    if (unique.size !== rankingItems.length) {
                        return { error: 'Les éléments à classer doivent être uniques pour chaque question de classement.' };
                    }
                }
                if (type === 'video') {
                    const videoId = extractYouTubeVideoId(youtubeUrl);
                    if (!videoId) {
                        return { error: 'Merci de renseigner une URL YouTube valide pour chaque question vidéo.' };
                    }
                    if (hasVideoStart && videoStartParsed === null) {
                        return { error: 'Le temps de début vidéo doit être au format mm:ss (ex. 1:30) ou en secondes.' };
                    }
                    if (hasVideoEnd && videoEndParsed === null) {
                        return { error: 'Le temps de fin vidéo doit être au format mm:ss (ex. 2:10) ou en secondes.' };
                    }
                    if (videoStartParsed !== null && videoEndParsed !== null && videoEndParsed > 0 && videoStartParsed > 0 && videoEndParsed <= videoStartParsed) {
                        return { error: 'Le temps de fin vidéo doit être supérieur au temps de début.' };
                    }
                }
                if (type === 'labelimage') {
                    if (!questionImage) {
                        return { error: 'Chaque question "Légender une image" doit contenir une image.' };
                    }
                    const namedLabels = legendLabels.filter(label => label.text);
                    if (namedLabels.length < 1) {
                        return { error: 'Ajoutez au moins une étiquette pour chaque question "Légender une image".' };
                    }
                    if (namedLabels.some(label => label.x === null || label.y === null)) {
                        return { error: 'Chaque étiquette doit être placée sur l’image.' };
                    }
                }

                const openQuestion = {
                    type,
                    question,
                    answers: [],
                    correctIndex: null,
                    maxRating: type === 'rating' ? 5 : null,
                    participantResponsesVisible,
                    timeLimitSec,
                    questionImage,
                    questionImageZoom
                };
                if (type === 'open') {
                    openQuestion.responseFormat = responseFormat;
                }
                if (type === 'cloze') {
                    openQuestion.clozeText = clozeText;
                }
                if (type === 'ranking') {
                    openQuestion.answers = rankingItems;
                }
                if (type === 'video') {
                    openQuestion.youtubeUrl = youtubeUrl;
                    const normalizedRange = normalizeVideoRange(videoStartParsed, videoEndParsed);
                    openQuestion.videoStartSec = normalizedRange.startSec;
                    openQuestion.videoEndSec = normalizedRange.endSec;
                }
                if (type === 'labelimage') {
                    openQuestion.legendLabels = legendLabels.filter(label => label.text);
                }
                batch.push(openQuestion);
                continue;
            }

            const allAnswers = Array.from(block.querySelectorAll('.batch-answer-input')).map(input => input.value.trim());
            const requiredAnswers = allAnswers.slice(0, 2);
            if (requiredAnswers.some(a => !a)) {
                return { error: 'Chaque question doit avoir au moins 2 réponses.' };
            }

            const indexedAnswers = allAnswers.map((answer, index) => ({ index, answer })).filter(item => item.answer !== '');
            const answers = indexedAnswers.map(item => item.answer);
            if (answers.length < 2) {
                return { error: 'Chaque question doit avoir au moins 2 réponses.' };
            }
            const isPollMode = block.querySelector('.batch-poll-mode-toggle')?.checked ?? false;
            if (type === 'multiple') {
                const checked = block.querySelector('.correct-marker-input:checked');
                const correctIndex = checked ? parseInt(checked.value, 10) : 0;
                const normalizedCorrectIndex = indexedAnswers.findIndex(item => item.index === correctIndex);
                if (!isPollMode && (!Number.isInteger(normalizedCorrectIndex) || normalizedCorrectIndex < 0 || normalizedCorrectIndex >= answers.length)) {
                    return { error: 'La bonne réponse sélectionnée ne correspond pas aux réponses renseignées.' };
                }

                batch.push({
                    type: 'multiple',
                    question,
                    answers,
                    isPollMode,
                    correctIndex: isPollMode ? null : normalizedCorrectIndex,
                    participantResponsesVisible,
                    timeLimitSec,
                    questionImage,
                    questionImageZoom
                });
            } else {
                const rawCorrectIndexes = Array.from(block.querySelectorAll('.correct-marker-input:checked'))
                    .map(input => parseInt(input.value, 10))
                    .filter(index => Number.isInteger(index) && index >= 0);
                const normalizedCorrectIndexes = Array.from(new Set(rawCorrectIndexes
                    .map(index => indexedAnswers.findIndex(item => item.index === index))
                    .filter(index => Number.isInteger(index) && index >= 0 && index < answers.length)));
                if (!isPollMode && normalizedCorrectIndexes.length < 1) {
                    return { error: 'Sélectionnez au moins une réponse correcte pour chaque question à cases à cocher.' };
                }
                batch.push({
                    type: 'checkbox',
                    question,
                    answers,
                    isPollMode,
                    correctIndex: null,
                    correctIndexes: isPollMode ? [] : normalizedCorrectIndexes,
                    participantResponsesVisible,
                    timeLimitSec,
                    questionImage,
                    questionImageZoom
                });
            }
        }

        if (batch.length === 0) {
            return { error: 'Ajoutez au moins une question.' };
        }

        return { batch };
    }

    function renderLiveQuestion() {
        if (!state.batch.length) {
            return;
        }

        const q = state.batch[state.currentIndex];
        q.timeLimitSec = normalizeQuestionTimeLimit(q.timeLimitSec);
        q.questionStartedAtMs = normalizeQuestionStartedAtMs(q.questionStartedAtMs);
        document.getElementById('batchProgressText').textContent = `Question ${state.currentIndex + 1} / ${state.batch.length}`;
        renderFormattedQuestion(document.getElementById('createdQuestionText'), q.question);
        const createdQuestionText = document.getElementById('createdQuestionText');
        let createdImageWrap = document.getElementById('createdQuestionImageWrap');
        if (!createdImageWrap && createdQuestionText && createdQuestionText.parentElement) {
            createdImageWrap = document.createElement('div');
            createdImageWrap.id = 'createdQuestionImageWrap';
            createdImageWrap.className = 'question-image-display hidden';
            createdImageWrap.innerHTML = '<img id="createdQuestionImage" alt="Image de la question" decoding="async">';
            createdQuestionText.insertAdjacentElement('afterend', createdImageWrap);
        }
        const createdImage = document.getElementById('createdQuestionImage');
        const imageSrc = isValidQuestionImage(q.questionImage) ? String(q.questionImage).trim() : '';
        const imageZoom = normalizePublicQuestionImageZoom(q.questionImageZoom);
        if (createdImageWrap && createdImage) {
            createdImage.decoding = 'async';
            if (imageSrc) {
                createdImage.src = imageSrc;
                createdImageWrap.classList.remove('hidden');
                applyQuestionImageSizing(createdImageWrap, createdImage);
                applyPublicQuestionImageZoom(createdImageWrap, createdImage, imageZoom);
            } else {
                createdImage.removeAttribute('src');
                createdImage.style.transform = '';
                createdImageWrap.classList.add('hidden');
                createdImageWrap.classList.remove('is-landscape-full');
                createdImageWrap.classList.remove('is-portrait-large');
            }
        }

        const answersList = document.getElementById('createdAnswersList');
        const answersTitle = answersList?.previousElementSibling;
        let mediaPreview = document.getElementById('createdMediaPreview');
        if (!mediaPreview && answersList && answersList.parentElement) {
            mediaPreview = document.createElement('div');
            mediaPreview.id = 'createdMediaPreview';
            mediaPreview.className = 'created-media-preview';
            answersList.insertAdjacentElement('afterend', mediaPreview);
        }
        answersList.innerHTML = '';
        if (answersTitle) {
            answersTitle.classList.remove('hidden');
        }
        answersList.classList.remove('hidden');
        if (mediaPreview) {
            mediaPreview.innerHTML = '';
            mediaPreview.classList.add('hidden');
        }
        const qType = normalizeQuestionType(q.type);
        const responseFormat = normalizeOpenResponseFormat(q.responseFormat);
        const participantResponsesVisible = normalizeParticipantResponsesVisibility(q.participantResponsesVisible);
        if (qType === 'open') {
            const li = document.createElement('li');
            li.textContent = responseFormat === 'math'
                ? 'Question ouverte (réponse mathématique)'
                : 'Question ouverte (réponse libre)';
            answersList.appendChild(li);
        } else if (qType === 'cloze') {
            const typeLi = document.createElement('li');
            typeLi.textContent = 'Texte à trous (réponse libre)';
            answersList.appendChild(typeLi);

            const textLi = document.createElement('li');
            textLi.className = 'cloze-preview-item';
            textLi.textContent = maskClozeTemplate(q.clozeText || '');
            answersList.appendChild(textLi);
        } else if (qType === 'wordcloud') {
            const li = document.createElement('li');
            li.textContent = 'Nuage de mots (mots-clés libres)';
            answersList.appendChild(li);
        } else if (qType === 'rating') {
            const li = document.createElement('li');
            li.textContent = 'Notation de 1 à 5 étoiles';
            answersList.appendChild(li);
        } else if (qType === 'ranking') {
            const typeLi = document.createElement('li');
            typeLi.textContent = 'Classement (ordre par glisser-déposer)';
            answersList.appendChild(typeLi);
        } else if (qType === 'video') {
            const li = document.createElement('li');
            li.textContent = 'Vidéo YouTube (aucune réponse attendue)';
            answersList.appendChild(li);
            const rangeText = describeVideoRange(q.videoStartSec, q.videoEndSec);
            if (rangeText) {
                const rangeLi = document.createElement('li');
                rangeLi.textContent = rangeText;
                answersList.appendChild(rangeLi);
            }

            if (mediaPreview) {
                const embedUrl = buildYouTubeEmbedUrl(q.youtubeUrl || '', q.videoStartSec, q.videoEndSec);
                if (embedUrl) {
                    mediaPreview.innerHTML = '';
                    const wrap = document.createElement('div');
                    wrap.className = 'created-video-wrap';
                    wrap.appendChild(createYouTubeIframe(embedUrl, 'Aperçu vidéo YouTube'));
                    mediaPreview.appendChild(wrap);
                } else {
                    mediaPreview.innerHTML = `<p class="created-media-error">${escapeHtml(q.youtubeUrl || 'URL vidéo non valide')}</p>`;
                }
                mediaPreview.classList.remove('hidden');
            }
        } else if (qType === 'labelimage') {
            if (answersTitle) {
                answersTitle.classList.add('hidden');
            }
            answersList.classList.add('hidden');
        } else {
            (Array.isArray(q.answers) ? q.answers : []).forEach(answer => {
                const li = document.createElement('li');
                renderMathText(li, answer);
                answersList.appendChild(li);
            });
        }
        renderMathInElementSafe(answersList);

        const correctAnswerText = document.getElementById('correctAnswerText');
        correctAnswerText.textContent = '';
        correctAnswerText.classList.add('hidden');

        renderAccessCodeDisplay(state.code);
        updateLiveParticipantResponsesButton();

        const urlComplet = responseUrl(state.code);
        const urlSimple = responseEntryUrl();
        const reponseURL = document.getElementById('reponseURL');
        reponseURL.innerHTML = `
            <div class="response-link-block primary-link-block">
                <p>URL pour répondre à cette question</p>
                <a href="${escapeHtml(urlComplet)}" target="_blank" rel="noopener noreferrer">${escapeHtml(urlComplet)}</a>
            </div>
            <div class="response-link-block">
                <p>Page simple (saisie du code)</p>
                <a href="${escapeHtml(urlSimple)}" target="_blank" rel="noopener noreferrer">${escapeHtml(urlSimple)}</a>
            </div>
        `;
        animateStagger(answersList.parentElement, '#createdAnswersList li');
        document.getElementById('qrCodeImage').src = buildQrCodeUrl(urlComplet);

        const prevBtn = document.getElementById('prevQuestionBtn');
        const nextBtn = document.getElementById('nextQuestionBtn');
        if (prevBtn) {
            prevBtn.disabled = state.currentIndex <= 0;
        }
        if (nextBtn) {
            nextBtn.disabled = state.currentIndex >= state.batch.length - 1;
        }

        document.getElementById('viewResultsBtn').dataset.code = state.code;
        document.getElementById('resultsCode').value = state.code;
        updateSessionCorner(state.code);
        updatePresenterLiveVisibility();

        // Cache locale de la question active
        questions[state.code] = {
            type: qType,
            question: q.question,
            questionImage: keepImageOnlyIfLightStorage(imageSrc),
            answers: q.answers,
            correctIndex: q.correctIndex,
            correctIndexes: Array.isArray(q.correctIndexes) ? q.correctIndexes : [],
            maxRating: q.maxRating || 5,
            responseFormat,
            participantResponsesVisible,
            timeLimitSec: q.timeLimitSec,
            questionStartedAtMs: q.questionStartedAtMs,
            clozeText: q.clozeText || '',
            youtubeUrl: q.youtubeUrl || '',
            videoStartSec: normalizeVideoRange(q.videoStartSec, q.videoEndSec).startSec,
            videoEndSec: normalizeVideoRange(q.videoStartSec, q.videoEndSec).endSec,
            questionIndex: state.currentIndex,
            totalQuestions: state.batch.length,
            created: new Date().toISOString()
        };
        responses[state.code] = {};
        safeSetLocalStorage('questions', JSON.stringify(questions));
        safeSetLocalStorage('responses', JSON.stringify(responses));
        safeSetLocalStorage('lastCreatedCode', state.code);
    }

    function updatePresenterLiveVisibility() {
        const summary = document.querySelector('#createSuccess .question-summary');
        const banner = document.getElementById('liveStatusBanner');
        const prevBtn = document.getElementById('prevQuestionBtn');
        const nextBtn = document.getElementById('nextQuestionBtn');
        if (summary) {
            summary.classList.toggle('hidden', !state.liveActive);
        }
        if (prevBtn) {
            prevBtn.classList.toggle('hidden', !state.liveActive);
        }
        if (nextBtn) {
            nextBtn.classList.toggle('hidden', !state.liveActive);
        }
        if (banner) {
            banner.classList.toggle('is-live', !!state.liveActive);
            banner.innerHTML = state.liveActive
                ? 'Session en direct'
                : 'En attente du lancement live<span class="loading-dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>';
        }
        refreshLiveQuestionTimer();
    }

    function showLiveView() {
        homePanel?.classList.add('hidden');
        editorPanel?.classList.remove('hidden');
        questionForm.classList.add('hidden');
        createSuccess.classList.remove('hidden');
        createTabTitle.classList.add('hidden');
        tabsNav.classList.add('hidden');
        updateLiveParticipantResponsesButton();
        syncPresencePolling();
    }

    function showBuilderView() {
        homePanel?.classList.add('hidden');
        editorPanel?.classList.remove('hidden');
        questionForm.classList.remove('hidden');
        createSuccess.classList.add('hidden');
        createTabTitle.classList.remove('hidden');
        tabsNav.classList.add('hidden');
        stopLiveQuestionTimer();
        syncPresencePolling();
    }

    function showHomeView() {
        homePanel?.classList.remove('hidden');
        editorPanel?.classList.add('hidden');
        tabsNav.classList.add('hidden');
        stopLiveQuestionTimer();
        syncPresencePolling();
    }

    async function applyParticipantResponsesVisibilityToEntireBatch(visible) {
        const targetVisible = !!visible;
        const previousBatch = Array.isArray(state.batch) ? state.batch.map(item => (item && typeof item === 'object' ? { ...item } : item)) : [];
        const previousOverrides = { ...state.participantResponsesVisibilityOverrides };
        const previousShowParticipantResponses = state.showParticipantResponses;

        state.batch = (Array.isArray(state.batch) ? state.batch : []).map(item => {
            if (!item || typeof item !== 'object') {
                return item;
            }
            if (normalizeQuestionType(item.type) === 'video') {
                return { ...item, participantResponsesVisible: true };
            }
            return { ...item, participantResponsesVisible: targetVisible };
        });
        state.participantResponsesVisibilityOverrides = {};
        state.showParticipantResponses = targetVisible;

        syncParticipantResponsesTogglesFromState();
        saveBatchState();
        renderLiveQuestion();

        try {
            if (state.code) {
                await publishCurrentQuestion();
            }

            if (document.getElementById('resultsTab')?.classList.contains('active')) {
                document.getElementById('resultsForm')?.dispatchEvent(new Event('submit'));
            }

            showSiteNotice(
                targetVisible
                    ? 'Les réponses des participants sont désormais affichées par défaut.'
                    : 'Les réponses des participants sont désormais masquées par défaut.'
            );
        } catch (error) {
            state.batch = previousBatch;
            state.participantResponsesVisibilityOverrides = previousOverrides;
            state.showParticipantResponses = previousShowParticipantResponses;
            syncParticipantResponsesTogglesFromState();
            saveBatchState();
            renderLiveQuestion();
            throw error;
        }
    }

    async function publishCurrentQuestion(options = {}) {
        const resetAllResponses = !!options.resetAllResponses;
        if (!state.runId) {
            state.runId = generateRunId();
        }
        state.batch = normalizeBatchQuestionTiming(batchWithRunId(state.batch, state.runId));
        const payload = {
            mode: 'batch',
            code: state.code,
            quizTitle: state.quizTitle,
            participantReportEnabled: !!state.participantReportEnabled,
            requireParticipantName: state.requireParticipantName !== false,
            batch: state.batch,
            currentIndex: state.currentIndex,
            liveActive: !!state.liveActive,
            resetAllResponses
        };

        const resp = await fetchApi('save_question.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        let data = null;
        const rawText = await resp.text();
        try {
            data = rawText ? JSON.parse(rawText) : {};
        } catch (_) {
            throw new Error(rawText || 'Réponse serveur invalide.');
        }
        if (!data.success) {
            throw new Error(data.error || 'Impossible de publier la question');
        }
        if (Number.isFinite(Number(data.serverNowMs))) {
            presenterServerOffsetMs = Number(data.serverNowMs) - Date.now();
        }
        if (Array.isArray(state.batch) && state.batch[state.currentIndex] && typeof state.batch[state.currentIndex] === 'object') {
            state.batch[state.currentIndex].timeLimitSec = normalizeQuestionTimeLimit(data.timeLimitSec ?? state.batch[state.currentIndex].timeLimitSec);
            state.batch[state.currentIndex].questionStartedAtMs = normalizeQuestionStartedAtMs(data.questionStartedAtMs);
        }
        return data;
    }

    async function advanceToNextQuestion() {
        if (state.currentIndex >= state.batch.length - 1) {
            return false;
        }

        state.currentIndex += 1;
        try {
            await publishCurrentQuestion();
            saveBatchState();
            renderLiveQuestion();

            if (document.getElementById('resultsTab').classList.contains('active')) {
                document.getElementById('resultsForm').dispatchEvent(new Event('submit'));
            }
            return true;
        } catch (error) {
            state.currentIndex -= 1;
            alert(error.message || 'Impossible de passer à la question suivante.');
            return false;
        }
    }

    async function advanceToPreviousQuestion() {
        if (state.currentIndex <= 0) {
            return false;
        }

        state.currentIndex -= 1;
        try {
            await publishCurrentQuestion();
            saveBatchState();
            renderLiveQuestion();

            if (document.getElementById('resultsTab').classList.contains('active')) {
                document.getElementById('resultsForm').dispatchEvent(new Event('submit'));
            }
            return true;
        } catch (error) {
            state.currentIndex += 1;
            alert(error.message || 'Impossible de revenir à la question précédente.');
            return false;
        }
    }

    async function ensureSessionLive() {
        if (!state.code) {
            return;
        }
        const activeQuestion = Array.isArray(state.batch) ? state.batch[state.currentIndex] : null;
        const activeType = normalizeQuestionType(activeQuestion?.type);
        const startedAtMs = normalizeQuestionStartedAtMs(activeQuestion?.questionStartedAtMs);
        const timeLimitSec = normalizeQuestionTimeLimit(activeQuestion?.timeLimitSec);
        const missingStart = !!state.liveActive && activeType !== 'video' && !startedAtMs;
        const expiredStart = !!state.liveActive
            && activeType !== 'video'
            && !!startedAtMs
            && ((Date.now() + presenterServerOffsetMs) >= (startedAtMs + (timeLimitSec * 1000)));
        if (state.liveActive && !missingStart && !expiredStart) {
            return;
        }

        const resp = await fetchApi('set_live.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ code: state.code, liveActive: true })
        });
        const data = await resp.json();
        if (!data.success) {
            throw new Error(data.error || "Impossible d'activer la session en direct.");
        }

        if (Number.isFinite(Number(data.serverNowMs))) {
            presenterServerOffsetMs = Number(data.serverNowMs) - Date.now();
        }
        state.liveActive = true;
        if (Array.isArray(state.batch) && state.batch[state.currentIndex] && typeof state.batch[state.currentIndex] === 'object') {
            state.batch[state.currentIndex].timeLimitSec = normalizeQuestionTimeLimit(data.timeLimitSec ?? state.batch[state.currentIndex].timeLimitSec);
            state.batch[state.currentIndex].questionStartedAtMs = normalizeQuestionStartedAtMs(data.questionStartedAtMs);
        }
        saveBatchState();
        updatePresenterLiveVisibility();
    }

    function setupTabs() {
        const tabBtns = document.querySelectorAll('.tab-btn');
        const tabs = document.querySelectorAll('.tab');

        tabBtns.forEach(btn => {
            btn.addEventListener('click', async function() {
                tabBtns.forEach(b => b.classList.remove('active'));
                tabs.forEach(t => t.classList.remove('active'));

                this.classList.add('active');
                const tabId = this.id.replace('Btn', 'Tab');
                const targetTab = document.getElementById(tabId);
                targetTab.classList.add('active');
                targetTab.classList.add('tab-enter');
                setTimeout(() => targetTab.classList.remove('tab-enter'), 260);

                if (tabId === 'resultsTab') {
                    try {
                        await ensureSessionLive();
                    } catch (error) {
                        alert(error.message || "Impossible d'activer la session.");
                        tabBtns.forEach(b => b.classList.remove('active'));
                        tabs.forEach(t => t.classList.remove('active'));
                        document.getElementById('createTab')?.classList.add('active');
                        return;
                    }
                    startResultsPolling();
                } else {
                    stopResultsPolling();
                }
                updateSessionCorner(state.code || localStorage.getItem(SESSION_CODE_KEY));
            });
        });
    }

    function stopResultsPolling() {
        if (resultsPollTimer) {
            clearInterval(resultsPollTimer);
            resultsPollTimer = null;
        }
        stopResultsQuestionTimer();
        const resultsTimerEl = document.getElementById('resultsQuestionTimer');
        if (resultsTimerEl) {
            resultsTimerEl.classList.add('hidden');
        }
    }

    function startResultsPolling() {
        if (resultsPollTimer) {
            return;
        }
        resultsPollTimer = setInterval(async function() {
            const resultsTab = document.getElementById('resultsTab');
            if (!resultsTab.classList.contains('active')) {
                return;
            }
            if (state.showingFinalReport) {
                return;
            }

            const code = document.getElementById('resultsCode').value.trim();
            if (!code) {
                return;
            }

            try {
                await refreshResultsForCode(code);
            } catch (_) {
                // On évite les alertes répétitives pendant le polling.
            }
        }, RESULTS_POLL_INTERVAL_MS);
    }

    function clearResultsLabelImageOverlay() {
        const wrap = document.getElementById('resultsQuestionImageWrap');
        if (!wrap) {
            return;
        }
        wrap.classList.remove('results-labelmap-wrap');
        const existing = wrap.querySelector('.results-labelmap-overlay');
        if (existing) {
            if (existing.__resizeObserver && typeof existing.__resizeObserver.disconnect === 'function') {
                existing.__resizeObserver.disconnect();
            }
            existing.remove();
        }
    }

    function renderResultsLabelImageOverlay(questionData, rawResponses) {
        const wrap = document.getElementById('resultsQuestionImageWrap');
        const image = document.getElementById('resultsQuestionImage');
        if (!wrap || !image || !String(image.getAttribute('src') || '').trim()) {
            return {};
        }

        clearResultsLabelImageOverlay();

        const labels = normalizeLegendLabels(questionData.legendLabels).filter(label => label.text);
        if (labels.length === 0) {
            return {};
        }

        const responses = Array.isArray(rawResponses) ? rawResponses : [];
        const tolerance = 18; // pourcentage de largeur/hauteur
        const counts = {};
        const placementGroups = {};
        labels.forEach(label => { counts[label.id] = 0; });
        labels.forEach(label => { placementGroups[label.id] = []; });

        responses.forEach(entry => {
            const placements = Array.isArray(entry) ? entry : [];
            placements.forEach(p => {
                const id = String(p?.id || '');
                const x = Number(p?.x);
                const y = Number(p?.y);
                if (!placementGroups[id] || !Number.isFinite(x) || !Number.isFinite(y)) {
                    return;
                }
                placementGroups[id].push({
                    x: Math.max(0, Math.min(100, x)),
                    y: Math.max(0, Math.min(100, y))
                });
            });
        });

        const markerAnchors = {};
        labels.forEach((label, index) => {
            const hasTarget = Number.isFinite(Number(label.x)) && Number.isFinite(Number(label.y));
            if (hasTarget) {
                markerAnchors[label.id] = {
                    x: Number(label.x),
                    y: Number(label.y),
                    fromTarget: true
                };
                return;
            }
            const group = placementGroups[label.id] || [];
            if (group.length > 0) {
                const sum = group.reduce((acc, point) => ({
                    x: acc.x + point.x,
                    y: acc.y + point.y
                }), { x: 0, y: 0 });
                markerAnchors[label.id] = {
                    x: sum.x / group.length,
                    y: sum.y / group.length,
                    fromTarget: false
                };
                return;
            }
            markerAnchors[label.id] = {
                x: 12 + ((index % 6) * 12),
                y: 12 + (Math.floor(index / 6) * 10),
                fromTarget: false
            };
        });

        responses.forEach(entry => {
            const placements = Array.isArray(entry) ? entry : [];
            labels.forEach(label => {
                const placed = placements.find(p => String(p?.id || '') === label.id);
                if (!placed) {
                    return;
                }
                const x = Number(placed.x);
                const y = Number(placed.y);
                if (!Number.isFinite(x) || !Number.isFinite(y)) {
                    return;
                }
                const anchor = markerAnchors[label.id];
                if (!anchor) {
                    return;
                }
                if (!anchor.fromTarget) {
                    counts[label.id] += 1;
                    return;
                }
                const dx = x - Number(anchor.x);
                const dy = y - Number(anchor.y);
                const dist = Math.sqrt((dx * dx) + (dy * dy));
                if (dist <= tolerance) {
                    counts[label.id] += 1;
                }
            });
        });

        const overlay = document.createElement('div');
        overlay.className = 'results-labelmap-overlay';

        const syncOverlayBounds = () => {
            const wrapRect = wrap.getBoundingClientRect();
            const imageRect = image.getBoundingClientRect();
            if (wrapRect.width <= 0 || wrapRect.height <= 0 || imageRect.width <= 0 || imageRect.height <= 0) {
                overlay.style.left = '0';
                overlay.style.top = '0';
                overlay.style.width = '100%';
                overlay.style.height = '100%';
                return;
            }
            const left = Math.max(0, imageRect.left - wrapRect.left);
            const top = Math.max(0, imageRect.top - wrapRect.top);
            overlay.style.left = `${left}px`;
            overlay.style.top = `${top}px`;
            overlay.style.width = `${imageRect.width}px`;
            overlay.style.height = `${imageRect.height}px`;
        };

        syncOverlayBounds();
        requestAnimationFrame(syncOverlayBounds);
        if (!image.complete || Number(image.naturalWidth || 0) <= 0) {
            image.addEventListener('load', syncOverlayBounds, { once: true });
        }
        if (typeof ResizeObserver === 'function') {
            const resizeObserver = new ResizeObserver(() => {
                syncOverlayBounds();
            });
            resizeObserver.observe(wrap);
            resizeObserver.observe(image);
            overlay.__resizeObserver = resizeObserver;
        }

        labels.forEach((label, index) => {
            const marker = document.createElement('div');
            marker.className = 'results-labelmap-marker';
            const anchor = markerAnchors[label.id] || { x: 50, y: 50 };
            const safeX = Math.max(4, Math.min(96, Number(anchor.x)));
            const safeY = Math.max(4, Math.min(96, Number(anchor.y)));
            marker.style.left = `${safeX}%`;
            marker.style.top = `${safeY}%`;
            marker.title = `${index + 1}. ${label.text} - ${counts[label.id] || 0}`;
            marker.innerHTML = `
                <span class="results-labelmap-tag">${escapeHtml(label.text || `Étiquette ${index + 1}`)}</span>
                <span class="results-labelmap-count-badge">${index + 1}</span>
            `;
            overlay.appendChild(marker);
        });

        wrap.classList.add('results-labelmap-wrap');
        wrap.appendChild(overlay);
        return counts;
    }

    function displayResults(questionData, responseData, meta = {}) {
        const questionType = normalizeQuestionType(questionData.type);
        const statsContainer = document.getElementById('resultsStats');
        const isLargeWordcloud = state.wordcloudScaleMode === 'large';
        const showParticipantResponses = state.showParticipantResponses !== false;
        const signature = questionType === 'video'
            ? JSON.stringify({
                q: questionData.question || '',
                qi: questionData.questionImage || '',
                qz: normalizePublicQuestionImageZoom(questionData.questionImageZoom),
                t: questionType,
                y: questionData.youtubeUrl || '',
                ys: normalizeVideoRange(questionData.videoStartSec, questionData.videoEndSec).startSec,
                ye: normalizeVideoRange(questionData.videoStartSec, questionData.videoEndSec).endSec
            })
            : JSON.stringify({
                q: questionData.question || '',
                qi: questionData.questionImage || '',
                qz: normalizePublicQuestionImageZoom(questionData.questionImageZoom),
                t: questionType,
                y: questionData.youtubeUrl || '',
                ys: normalizeVideoRange(questionData.videoStartSec, questionData.videoEndSec).startSec,
                ye: normalizeVideoRange(questionData.videoStartSec, questionData.videoEndSec).endSec,
                l: questionData.legendLabels || [],
                r: responseData || {},
                m: meta || {},
                reveal: state.revealCorrectAnswer,
                large: isLargeWordcloud,
                showParticipantResponses,
                checkboxResultsMetric: questionType === 'checkbox' ? state.checkboxResultsMetric : null
            });
        if (state.lastStatsSignature === signature) {
            return;
        }
        state.lastStatsSignature = signature;
        statsContainer.innerHTML = '';
        clearResultsLabelImageOverlay();

        if (questionType === 'video') {
            const info = document.createElement('p');
            info.innerHTML = "<strong>Question vidéo</strong> : aucune réponse n'est attendue.";
            statsContainer.appendChild(info);

            const embedUrl = buildYouTubeEmbedUrl(questionData.youtubeUrl || '', questionData.videoStartSec, questionData.videoEndSec);
            const watchUrl = buildYouTubeWatchUrl(questionData.youtubeUrl || '', questionData.videoStartSec, questionData.videoEndSec);
            if (embedUrl) {
                const wrap = document.createElement('div');
                wrap.className = 'results-video-wrap';
                wrap.appendChild(createYouTubeIframe(embedUrl, 'Vidéo YouTube'));
                statsContainer.appendChild(wrap);
                const rangeText = describeVideoRange(questionData.videoStartSec, questionData.videoEndSec);
                if (rangeText) {
                    const rangeEl = document.createElement('p');
                    rangeEl.className = 'results-empty-line';
                    rangeEl.textContent = rangeText;
                    statsContainer.appendChild(rangeEl);
                }
                if (watchUrl) {
                    const fallback = document.createElement('p');
                    fallback.className = 'video-fallback-link';
                    fallback.innerHTML = `Si la vidéo ne se lance pas, <a href="${escapeHtml(watchUrl)}" target="_blank" rel="noopener noreferrer">ouvrez-la sur YouTube</a>.`;
                    statsContainer.appendChild(fallback);
                }
            } else {
                const invalid = document.createElement('p');
                invalid.textContent = 'URL vidéo non valide.';
                statsContainer.appendChild(invalid);
            }

            document.getElementById('resultsContent').classList.remove('hidden');
            renderMathInElementSafe(statsContainer);
            return;
        }

        if (questionType === 'labelimage') {
            const labelResponses = Array.isArray(meta.labelImageResponses) ? meta.labelImageResponses : [];
            const totalLabelResponses = Number.isInteger(meta.totalLabelImageResponses) ? meta.totalLabelImageResponses : labelResponses.length;
            const labels = normalizeLegendLabels(questionData.legendLabels).filter(label => label.text);
            const countsByLabelId = state.revealCorrectAnswer
                ? renderResultsLabelImageOverlay(questionData, showParticipantResponses ? labelResponses : [])
                : {};

            if (labels.length > 0) {
                const labelsInfo = document.createElement('p');
                labelsInfo.className = 'results-total-line';
                labelsInfo.innerHTML = `<strong>Étiquettes à placer</strong> : ${labels.length}`;
                statsContainer.appendChild(labelsInfo);
            }

            if (!showParticipantResponses) {
                appendParticipantResponsesHiddenMessage(statsContainer);
            } else if (totalLabelResponses === 0) {
                const empty = document.createElement('p');
                empty.className = 'results-empty-line';
                empty.textContent = "Aucune réponse pour l'instant.";
                statsContainer.appendChild(empty);
            } else {
                const totalEl = document.createElement('p');
                totalEl.className = 'results-total-line';
                totalEl.innerHTML = `<strong>Total des réponses</strong> : ${totalLabelResponses}`;
                statsContainer.appendChild(totalEl);
                if (!state.revealCorrectAnswer) {
                    const hint = document.createElement('p');
                    hint.className = 'results-empty-line';
                    hint.textContent = "Cliquez sur « Afficher la bonne réponse » pour afficher les emplacements.";
                    statsContainer.appendChild(hint);
                }
            }

            if (state.revealCorrectAnswer && labels.length > 0) {
                const legendList = document.createElement('div');
                legendList.className = 'results-labelmap-legend';
                labels.forEach((label, index) => {
                    const count = Number(countsByLabelId[label.id] || 0);
                    const item = document.createElement('div');
                    item.className = 'results-labelmap-legend-item';
                    if (showParticipantResponses) {
                        const percentage = totalLabelResponses > 0 ? Math.round((count / totalLabelResponses) * 100) : 0;
                        item.innerHTML = `
                            <span class="results-labelmap-legend-index">${index + 1}</span>
                            <span class="results-labelmap-legend-text">${escapeHtml(label.text)}</span>
                            <span class="results-labelmap-legend-count">${count} (${percentage}%)</span>
                        `;
                    } else {
                        item.innerHTML = `
                            <span class="results-labelmap-legend-index">${index + 1}</span>
                            <span class="results-labelmap-legend-text">${escapeHtml(label.text)}</span>
                        `;
                    }
                    legendList.appendChild(item);
                });
                statsContainer.appendChild(legendList);
            }

            document.getElementById('resultsContent').classList.remove('hidden');
            renderMathInElementSafe(statsContainer);
            return;
        }

        if (questionType === 'open' || questionType === 'wordcloud' || questionType === 'cloze') {
            const openResponses = Array.isArray(meta.openResponses) ? meta.openResponses : [];
            const totalOpen = Number.isInteger(meta.totalOpenResponses) ? meta.totalOpenResponses : openResponses.length;

            if (questionType === 'cloze') {
                if (state.revealCorrectAnswer) {
                    const clozeCorrect = document.createElement('div');
                    clozeCorrect.className = 'open-response-item correct-response-item reveal-item cloze-preview-item';
                    clozeCorrect.innerHTML = `<strong>Bonne réponse :</strong> ${buildClozeCorrectHtml(questionData.clozeText || '')}`;
                    statsContainer.appendChild(clozeCorrect);
                } else {
                    const clozeContext = document.createElement('div');
                    clozeContext.className = 'open-response-item cloze-preview-item';
                    clozeContext.innerHTML = `<strong>Texte à trous :</strong> ${escapeHtml(maskClozeTemplate(questionData.clozeText || ''))}`;
                    statsContainer.appendChild(clozeContext);
                }
            }

            if (!showParticipantResponses) {
                appendParticipantResponsesHiddenMessage(statsContainer);
            } else if (totalOpen === 0) {
                const empty = document.createElement('p');
                empty.className = 'results-empty-line';
                empty.textContent = "Aucune réponse pour l'instant.";
                statsContainer.appendChild(empty);
            } else {
                const totalEl = document.createElement('p');
                totalEl.className = 'results-total-line';
                totalEl.innerHTML = `<strong>Total des réponses</strong> : ${totalOpen}`;
                statsContainer.appendChild(totalEl);

                if (questionType === 'wordcloud') {
                    let keywords = buildKeywordCounts(openResponses);
                    if (keywords.length === 0) keywords = buildKeywordCounts(openResponses, true);
                    if (keywords.length === 0) keywords = buildKeywordCounts(openResponses, true, 1);
                    if (keywords.length === 0) {
                        const noWords = document.createElement('p');
                        noWords.textContent = 'Pas assez de mots exploitables pour générer un nuage.';
                        statsContainer.appendChild(noWords);
                    } else {
                        const cloud = document.createElement('div');
                        cloud.className = `wordcloud-container${isLargeWordcloud ? ' large' : ''}`;
                        const maxCount = keywords[0].count || 1;
                        keywords.slice(0, 60).forEach(item => {
                            const term = document.createElement('span');
                            term.className = 'wordcloud-term';
                            const visual = getWordCloudVisual(item.word, item.count, maxCount, isLargeWordcloud);
                            term.style.fontSize = `${visual.size}px`;
                            term.style.color = visual.color;
                            term.style.fontWeight = String(visual.weight);
                            term.title = `${item.word}: ${item.count}`;
                            term.textContent = item.word;
                            cloud.appendChild(term);
                        });
                        statsContainer.appendChild(cloud);
                    }
                } else {
                    const list = document.createElement('div');
                    list.className = 'open-responses-list';
                    openResponses.forEach((text, index) => {
                        const row = document.createElement('div');
                        row.className = 'open-response-item';
                        const label = document.createElement('strong');
                        label.textContent = `${index + 1}. `;
                        const value = document.createElement('span');
                        value.textContent = String(text || '');
                        row.appendChild(label);
                        row.appendChild(value);
                        list.appendChild(row);
                    });
                    statsContainer.appendChild(list);
                }
            }

            document.getElementById('resultsContent').classList.remove('hidden');
            renderMathInElementSafe(statsContainer);
            return;
        }

        if (questionType === 'ranking') {
            const rankingCounts = meta.rankingCounts && typeof meta.rankingCounts === 'object' ? meta.rankingCounts : {};
            const totalRankingResponses = Number.isInteger(meta.totalRankingResponses)
                ? meta.totalRankingResponses
                : Object.values(rankingCounts).reduce((sum, count) => sum + Number(count || 0), 0);
            const expectedOrder = Array.isArray(questionData.answers)
                ? questionData.answers.map(item => String(item || '').trim()).filter(Boolean)
                : [];
            const expectedOrderText = expectedOrder.join(' \u2192 ');

            if (!showParticipantResponses) {
                if (state.revealCorrectAnswer && expectedOrderText) {
                    const expectedEl = document.createElement('div');
                    expectedEl.className = 'open-response-item correct-response-item reveal-item';
                    expectedEl.innerHTML = `<strong>Ordre attendu :</strong> ${escapeHtml(expectedOrderText)}`;
                    statsContainer.appendChild(expectedEl);
                }
                appendParticipantResponsesHiddenMessage(statsContainer);
            } else if (totalRankingResponses === 0) {
                if (state.revealCorrectAnswer && expectedOrderText) {
                    const expectedEl = document.createElement('div');
                    expectedEl.className = 'open-response-item correct-response-item reveal-item';
                    expectedEl.innerHTML = `<strong>Ordre attendu :</strong> ${escapeHtml(expectedOrderText)}`;
                    statsContainer.appendChild(expectedEl);
                }
                const empty = document.createElement('p');
                empty.className = 'results-empty-line';
                empty.textContent = "Aucune réponse pour l'instant.";
                statsContainer.appendChild(empty);
            } else {
                const totalEl = document.createElement('p');
                totalEl.className = 'results-total-line';
                totalEl.innerHTML = `<strong>Total des réponses</strong> : ${totalRankingResponses}`;
                statsContainer.appendChild(totalEl);

                if (state.revealCorrectAnswer && expectedOrderText) {
                    const expectedEl = document.createElement('div');
                    expectedEl.className = 'open-response-item correct-response-item';
                    expectedEl.innerHTML = `<strong>Ordre attendu :</strong> ${escapeHtml(expectedOrderText)}`;
                    statsContainer.appendChild(expectedEl);
                }

                const rows = Object.entries(rankingCounts)
                    .sort((a, b) => Number(b[1] || 0) - Number(a[1] || 0))
                    .slice(0, 12);

                const list = document.createElement('div');
                list.className = 'open-responses-list';
                rows.forEach(([order, count], index) => {
                    const row = document.createElement('div');
                    const isExpectedOrder = state.revealCorrectAnswer && expectedOrderText && String(order || '') === expectedOrderText;
                    row.className = `open-response-item${isExpectedOrder ? ' correct-response-item' : ''}`;
                    row.innerHTML = `<strong>${index + 1}.</strong> ${escapeHtml(order)} <em>(${Number(count || 0)} vote(s))</em>`;
                    list.appendChild(row);
                });
                statsContainer.appendChild(list);
            }

            document.getElementById('resultsContent').classList.remove('hidden');
            return;
        }

        if (questionType === 'rating') {
            if (!showParticipantResponses) {
                appendParticipantResponsesHiddenMessage(statsContainer);
                document.getElementById('resultsContent').classList.remove('hidden');
                return;
            }

            const maxRating = Number.isInteger(meta.maxRating) ? meta.maxRating : 5;
            const ratingCounts = meta.ratingCounts && typeof meta.ratingCounts === 'object' ? meta.ratingCounts : {};
            const totalRatings = Number.isInteger(meta.totalRatings) ? meta.totalRatings : 0;
            const avgRating = Number(meta.avgRating || 0);
            const roundedAvg = Math.max(0, Math.min(maxRating, Math.round(avgRating)));
            const accentColor = getRatingAccentColor(avgRating, maxRating);
            const averageStars = Array.from({ length: maxRating }, (_, index) => (
                `<span class="rating-avg-star${index < roundedAvg ? ' is-on' : ''}">★</span>`
            )).join('');
            const rows = [];

            for (let rating = maxRating; rating >= 1; rating -= 1) {
                const count = Number(ratingCounts[String(rating)] || 0);
                const percentage = totalRatings > 0 ? Math.round((count / totalRatings) * 100) : 0;
                rows.push(`
                    <div class="rating-level-row">
                        <p class="rating-level-label">Niveau ${rating}</p>
                        <div class="rating-level-bar">
                            <div class="rating-level-fill" style="width: ${percentage}%;"></div>
                        </div>
                        <p class="rating-level-count">${count}</p>
                    </div>
                `);
            }

            const dashboard = document.createElement('div');
            dashboard.className = 'rating-dashboard';
            dashboard.style.setProperty('--rating-accent', accentColor);
            dashboard.innerHTML = `
                <div class="rating-dashboard-avg">
                    <p class="rating-avg-value">${avgRating.toFixed(2)}</p>
                    <p class="rating-avg-label">Évaluation moyenne</p>
                    <p class="rating-avg-stars">${averageStars}</p>
                    <p class="rating-avg-votes">${totalRatings} vote(s)</p>
                </div>
                <div class="rating-dashboard-dist">
                    ${rows.join('')}
                </div>
            `;
            statsContainer.appendChild(dashboard);
            document.getElementById('resultsContent').classList.remove('hidden');
            return;
        }

        const total = Object.values(responseData).reduce((sum, count) => sum + Number(count || 0), 0);
        const correctIndex = Number.isInteger(meta.correctIndex) ? meta.correctIndex :
            (Number.isInteger(questionData.correctIndex) ? questionData.correctIndex : null);
        const correctIndexes = Array.isArray(meta.correctIndexes)
            ? meta.correctIndexes.map(value => parseInt(value, 10)).filter(value => Number.isInteger(value) && value >= 0)
            : (Array.isArray(questionData.correctIndexes)
                ? questionData.correctIndexes.map(value => parseInt(value, 10)).filter(value => Number.isInteger(value) && value >= 0)
                : []);

        if (!showParticipantResponses) {
            questionData.answers.forEach((answer, index) => {
                const isCorrect = state.revealCorrectAnswer
                    && (questionType === 'checkbox' ? correctIndexes.includes(index) : correctIndex === index);

                const resultItem = document.createElement('div');
                resultItem.className = `result-item${isCorrect ? ' correct-result' : ''}`;
                resultItem.innerHTML = `
                    <div class="result-answer-line">
                        <div class="result-answer-main">
                            <strong>${escapeHtml(answer)}</strong>
                            ${isCorrect ? '<span class="correct-icon-tag" title="Bonne réponse"><i class="fa-solid fa-circle-check" aria-hidden="true"></i></span>' : ''}
                        </div>
                    </div>
                `;
                statsContainer.appendChild(resultItem);
            });
            appendParticipantResponsesHiddenMessage(statsContainer);
            document.getElementById('resultsContent').classList.remove('hidden');
            renderMathInElementSafe(statsContainer);
            return;
        }

        if (total === 0) {
            statsContainer.innerHTML = '<p class="results-empty-line">Aucune réponse pour l\'instant.</p>';
        }

        questionData.answers.forEach((answer, index) => {
            const count = Number(responseData[index] || responseData[String(index)] || 0);
            const percentage = total ? Math.round((count / total) * 100) : 0;
            const isCorrect = state.revealCorrectAnswer
                && (questionType === 'checkbox' ? correctIndexes.includes(index) : correctIndex === index);
            const showCheckboxCount = questionType === 'checkbox' && state.checkboxResultsMetric !== 'percent';
            const metricText = showCheckboxCount ? String(count) : `${percentage}%`;
            const metricTitle = questionType === 'checkbox'
                ? (showCheckboxCount
                    ? `Cliquer pour afficher le pourcentage (${percentage}%)`
                    : `Cliquer pour afficher le nombre de sélections (${count})`)
                : `${count} réponse(s)`;
            const metricHtml = questionType === 'checkbox'
                ? `<button type="button" class="result-answer-percent result-answer-metric-toggle" title="${escapeHtml(metricTitle)}" aria-label="${escapeHtml(metricTitle)}">${escapeHtml(metricText)}</button>`
                : `<span class="result-answer-percent" title="${escapeHtml(metricTitle)}">${escapeHtml(metricText)}</span>`;

            const resultItem = document.createElement('div');
            resultItem.className = `result-item${isCorrect ? ' correct-result' : ''}`;
            resultItem.innerHTML = `
                <div class="result-answer-line">
                    <div class="result-answer-main">
                        <strong>${escapeHtml(answer)}</strong>
                        ${isCorrect ? '<span class="correct-icon-tag" title="Bonne réponse"><i class="fa-solid fa-circle-check" aria-hidden="true"></i></span>' : ''}
                    </div>
                    ${metricHtml}
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: ${percentage}%;"></div>
                </div>
            `;
            resultItem.querySelector('.result-answer-metric-toggle')?.addEventListener('click', function() {
                state.checkboxResultsMetric = state.checkboxResultsMetric === 'count' ? 'percent' : 'count';
                state.lastStatsSignature = null;
                if (state.latestResultsSnapshot) {
                    displayResults(
                        state.latestResultsSnapshot.questionData,
                        state.latestResultsSnapshot.responseData,
                        state.latestResultsSnapshot.meta
                    );
                }
            });
            statsContainer.appendChild(resultItem);
        });

        const totalEl = document.createElement('p');
        totalEl.className = 'results-total-line';
        totalEl.innerHTML = `<strong>${questionType === 'checkbox' ? 'Total des sélections' : 'Total des réponses'}</strong> : ${total}`;
        statsContainer.appendChild(totalEl);

        document.getElementById('resultsContent').classList.remove('hidden');
        renderMathInElementSafe(statsContainer);
    }

    function updateResultsNavigationControls() {
        const livePrevBtn = document.getElementById('prevFromResultsBtn');
        const liveNextBtn = document.getElementById('nextFromResultsBtn');
        const finalReportBtn = document.getElementById('showFinalReportBtn');
        const exportCsvBtn = document.getElementById('exportCsvBtn');
        const toggleWordcloudSizeBtn = document.getElementById('toggleWordcloudSizeBtn');
        const toggleParticipantResponsesBtn = document.getElementById('toggleParticipantResponsesBtn');
        const revealCorrectBtn = document.getElementById('revealCorrectBtn');
        const hasMultiple = state.resultsTotalQuestions > 1;
        const isFinalReportMode = !!(state.showingFinalReport && state.latestFinalReport);
        const currentQuestionType = normalizeQuestionType(state.latestResultsSnapshot?.questionData?.type);
        const isWordcloudQuestion = currentQuestionType === 'wordcloud';
        const canToggleParticipantResponses = !!state.latestResultsSnapshot && currentQuestionType !== 'video';

        const canGoBackLive = state.batch.length > 0 && state.currentIndex > 0;
        const canAdvanceLive = state.batch.length > 0 && state.currentIndex < state.batch.length - 1;
        if (livePrevBtn) {
            livePrevBtn.disabled = !canGoBackLive;
            livePrevBtn.classList.toggle('hidden', isFinalReportMode);
        }
        if (liveNextBtn) {
            liveNextBtn.disabled = !canAdvanceLive;
            liveNextBtn.classList.toggle('hidden', isFinalReportMode);
        }
        if (finalReportBtn) {
            finalReportBtn.classList.toggle('hidden', isFinalReportMode || !(hasMultiple && !canAdvanceLive));
        }
        if (toggleWordcloudSizeBtn) {
            toggleWordcloudSizeBtn.classList.toggle('hidden', isFinalReportMode || !isWordcloudQuestion);
        }
        if (toggleParticipantResponsesBtn) {
            toggleParticipantResponsesBtn.classList.toggle('hidden', isFinalReportMode || !canToggleParticipantResponses);
            setParticipantResponsesButtonLabel(toggleParticipantResponsesBtn, state.showParticipantResponses !== false);
        }
        if (revealCorrectBtn && isFinalReportMode) {
            revealCorrectBtn.classList.add('hidden');
        }
        if (exportCsvBtn) {
            exportCsvBtn.classList.toggle('hidden', !isFinalReportMode);
        }
        setWordcloudButtonLabel(toggleWordcloudSizeBtn, state.wordcloudScaleMode === 'large');
    }

    function escapeCsvValue(value) {
        const text = String(value ?? '');
        if (text.includes('"') || text.includes(',') || text.includes('\n')) {
            return `"${text.replace(/"/g, '""')}"`;
        }
        return text;
    }

    function escapeHtml(value) {
        return String(value ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function buildClozeFilledText(template, values) {
        let blankIndex = 0;
        return String(template ?? '').replace(/\[[^\]]*\]|\{\{[^}]*\}\}/g, function() {
            const value = String(values[blankIndex] ?? '').trim();
            blankIndex += 1;
            return value;
        });
    }

    function maskClozeTemplate(template) {
        return String(template ?? '').replace(/\[[^\]]*\]|\{\{[^}]*\}\}/g, '_____');
    }

    function extractClozeExpectedAnswers(template) {
        const values = [];
        String(template ?? '').replace(/\[([^\]]*)\]|\{\{([^}]*)\}\}/g, function(_, square, curly) {
            values.push(String(square ?? curly ?? '').trim());
            return _;
        });
        return values;
    }

    function buildClozeCorrectHtml(template) {
        const raw = String(template ?? '');
        const pattern = /\[([^\]]*)\]|\{\{([^}]*)\}\}/g;
        let cursor = 0;
        let html = '';
        let match = pattern.exec(raw);

        while (match) {
            if (match.index > cursor) {
                html += escapeHtml(raw.slice(cursor, match.index));
            }
            const expected = String(match[1] ?? match[2] ?? '').trim();
            html += `<strong>${escapeHtml(expected)}</strong>`;
            cursor = match.index + match[0].length;
            match = pattern.exec(raw);
        }

        if (cursor < raw.length) {
            html += escapeHtml(raw.slice(cursor));
        }

        return html;
    }

    function renderClozeInputs(container, template) {
        const raw = String(template ?? '');
        container.innerHTML = '';
        const pattern = /\[[^\]]*\]|\{\{[^}]*\}\}/g;
        let cursor = 0;
        let blankIndex = 0;
        let match = pattern.exec(raw);

        while (match) {
            if (match.index > cursor) {
                container.appendChild(document.createTextNode(raw.slice(cursor, match.index)));
            }

            const wrap = document.createElement('span');
            wrap.className = 'math-enabled-input-wrap cloze-blank-input-wrap';
            const input = document.createElement('input');
            input.type = 'text';
            input.className = 'cloze-blank-input';
            input.dataset.blankIndex = String(blankIndex);
            input.placeholder = '...';
            input.required = true;
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'secondary-btn icon-only-btn open-math-editor-btn inline-math-insert-btn';
            button.setAttribute('aria-label', `Insérer une formule dans le trou ${blankIndex + 1}`);
            button.setAttribute('title', 'Insérer une formule');
            button.innerHTML = '<span class="math-tool-icon" aria-hidden="true">∑</span>';
            wrap.appendChild(input);
            wrap.appendChild(button);
            container.appendChild(wrap);

            blankIndex += 1;
            cursor = match.index + match[0].length;
            match = pattern.exec(raw);
        }

        if (cursor < raw.length) {
            container.appendChild(document.createTextNode(raw.slice(cursor)));
        }

        return blankIndex;
    }

    function shuffleArray(values) {
        const copy = Array.isArray(values) ? values.slice() : [];
        for (let i = copy.length - 1; i > 0; i -= 1) {
            const j = Math.floor(Math.random() * (i + 1));
            [copy[i], copy[j]] = [copy[j], copy[i]];
        }
        return copy;
    }

    function renderRankingSortableList(container, items) {
        const safeItems = Array.isArray(items) ? items.map(item => String(item || '').trim()).filter(item => item !== '') : [];
        container.innerHTML = '';
        if (safeItems.length < 2) {
            return 0;
        }

        const list = document.createElement('ul');
        list.className = 'ranking-sort-list';
        list.id = 'rankingSortList';

        let shuffled = shuffleArray(safeItems);
        if (safeItems.length > 1 && shuffled.join('\n') === safeItems.join('\n')) {
            for (let tries = 0; tries < 5; tries += 1) {
                shuffled = shuffleArray(safeItems);
                if (shuffled.join('\n') !== safeItems.join('\n')) {
                    break;
                }
            }
            if (shuffled.join('\n') === safeItems.join('\n')) {
                shuffled.push(shuffled.shift());
            }
        }

        shuffled.forEach(item => {
            const row = document.createElement('li');
            row.className = 'ranking-sort-item';
            row.draggable = false;
            row.dataset.value = item;
            row.innerHTML = `
                <span class="ranking-sort-handle" draggable="true" role="button" aria-label="Déplacer cet élément" title="Glisser pour déplacer"><i class="fa-solid fa-grip-lines"></i></span>
                <input type="text" class="ranking-sort-input" value="${escapeHtml(item)}" readonly>
            `;
            list.appendChild(row);
        });

        let dragged = null;
        list.addEventListener('dragstart', function(e) {
            const handle = e.target.closest('.ranking-sort-handle');
            if (!handle) {
                e.preventDefault();
                return;
            }
            const item = handle.closest('.ranking-sort-item');
            if (!item) {
                return;
            }
            dragged = item;
            item.classList.add('is-dragging');
            if (e.dataTransfer) {
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', 'move');
            }
        });

        list.addEventListener('dragover', function(e) {
            e.preventDefault();
            const item = e.target.closest('.ranking-sort-item');
            if (!item || item === dragged) {
                return;
            }
            const rect = item.getBoundingClientRect();
            const before = (e.clientY - rect.top) < (rect.height / 2);
            if (before) {
                list.insertBefore(dragged, item);
            } else {
                list.insertBefore(dragged, item.nextElementSibling);
            }
        });

        list.addEventListener('dragend', function() {
            if (dragged) {
                dragged.classList.remove('is-dragging');
            }
            dragged = null;
        });

        let touchDragged = null;
        list.addEventListener('touchstart', function(e) {
            const handle = e.target.closest('.ranking-sort-handle');
            if (!handle) {
                return;
            }
            const item = handle.closest('.ranking-sort-item');
            if (!item) {
                return;
            }
            touchDragged = item;
            item.classList.add('is-dragging');
        }, { passive: true });

        list.addEventListener('touchmove', function(e) {
            if (!touchDragged) {
                return;
            }
            e.preventDefault();
            const touch = e.touches && e.touches[0];
            if (!touch) {
                return;
            }
            const target = document.elementFromPoint(touch.clientX, touch.clientY);
            const overItem = target?.closest('.ranking-sort-item');
            if (!overItem || overItem === touchDragged || !list.contains(overItem)) {
                return;
            }
            const rect = overItem.getBoundingClientRect();
            const before = (touch.clientY - rect.top) < (rect.height / 2);
            if (before) {
                list.insertBefore(touchDragged, overItem);
            } else {
                list.insertBefore(touchDragged, overItem.nextElementSibling);
            }
        }, { passive: false });

        list.addEventListener('touchend', function() {
            if (touchDragged) {
                touchDragged.classList.remove('is-dragging');
            }
            touchDragged = null;
        });

        // Fallback robuste: tri au pointer (souris + tactile) sans dépendre du drag HTML natif.
        let pointerDragged = null;
        const onPointerMove = (event) => {
            if (!pointerDragged) {
                return;
            }
            const target = document.elementFromPoint(event.clientX, event.clientY);
            const overItem = target?.closest('.ranking-sort-item');
            if (!overItem || overItem === pointerDragged || !list.contains(overItem)) {
                return;
            }
            const rect = overItem.getBoundingClientRect();
            const before = (event.clientY - rect.top) < (rect.height / 2);
            if (before) {
                list.insertBefore(pointerDragged, overItem);
            } else {
                list.insertBefore(pointerDragged, overItem.nextElementSibling);
            }
        };
        const clearPointerDrag = () => {
            if (pointerDragged) {
                pointerDragged.classList.remove('is-dragging');
            }
            pointerDragged = null;
            document.removeEventListener('pointermove', onPointerMove);
            document.removeEventListener('pointerup', clearPointerDrag);
            document.removeEventListener('pointercancel', clearPointerDrag);
        };
        list.addEventListener('pointerdown', function(event) {
            const handle = event.target.closest('.ranking-sort-handle');
            if (!handle) {
                return;
            }
            const item = handle.closest('.ranking-sort-item');
            if (!item) {
                return;
            }
            event.preventDefault();
            pointerDragged = item;
            pointerDragged.classList.add('is-dragging');
            document.addEventListener('pointermove', onPointerMove);
            document.addEventListener('pointerup', clearPointerDrag);
            document.addEventListener('pointercancel', clearPointerDrag);
        });

        container.appendChild(list);
        return safeItems.length;
    }

    function getRankingOrderFromDom() {
        return Array.from(document.querySelectorAll('#rankingSortList .ranking-sort-item'))
            .map(node => String(node.dataset.value || '').trim())
            .filter(Boolean);
    }

    function renderLabelImageComposer(container, imageSrc, rawLabels) {
        if (!container) {
            return { getPlacements: () => [], requiredCount: 0 };
        }
        const labels = normalizeLegendLabels(rawLabels).filter(label => label.text);
        const shuffledLabels = shuffleArray(labels);
        const labelById = Object.fromEntries(labels.map(label => [label.id, label]));
        const slots = labels.map((label, index) => {
            const referenceX = Number.isFinite(Number(label.x))
                ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(label.x)))
                : null;
            const referenceY = Number.isFinite(Number(label.y))
                ? Math.max(LEGEND_MARKER_MIN_PERCENT, Math.min(LEGEND_MARKER_MAX_PERCENT, Number(label.y)))
                : null;
            const fallback = getDefaultLegendMarkerPosition(index);
            return {
                id: `slot${index + 1}`,
                x: referenceX !== null ? referenceX : fallback.x,
                y: referenceY !== null ? referenceY : fallback.y
            };
        });
        const slotById = Object.fromEntries(slots.map(slot => [slot.id, slot]));
        const labelAssignments = {};
        const slotAssignments = {};
        let activeId = shuffledLabels[0]?.id || '';
        let dragState = null;
        let skipNextOverlayClick = false;
        const DRAG_SLOT_SNAP_DISTANCE_PX = 68;

        container.innerHTML = `
            <div class="labelimage-player">
                <div class="labelimage-player-canvas-wrap">
                    <div class="labelimage-player-canvas">
                        <img class="labelimage-player-image" alt="Image à légender">
                        <div class="labelimage-player-overlay"></div>
                    </div>
                    <p class="labelimage-player-help">Sélectionnez une étiquette puis cliquez sur un emplacement pointillé. Vous pouvez aussi glisser-déposer une étiquette déjà placée.</p>
                </div>
                <div class="labelimage-player-labels"></div>
            </div>
        `;
        const imageEl = container.querySelector('.labelimage-player-image');
        const labelsEl = container.querySelector('.labelimage-player-labels');
        const canvas = container.querySelector('.labelimage-player-canvas');
        const overlay = container.querySelector('.labelimage-player-overlay');
        if (!imageEl || !labelsEl || !canvas || !overlay) {
            return { getPlacements: () => [], requiredCount: labels.length };
        }
        imageEl.src = String(imageSrc || '');

        const getNextUnplacedLabel = () => shuffledLabels.find(label => !labelAssignments[label.id]) || null;
        const assignLabelToSlot = (labelId, slotId) => {
            const safeLabelId = String(labelId || '').trim();
            const safeSlotId = String(slotId || '').trim();
            if (!safeLabelId || !safeSlotId || !slotById[safeSlotId]) {
                return;
            }
            const oldSlotId = labelAssignments[safeLabelId];
            if (oldSlotId && oldSlotId !== safeSlotId) {
                delete slotAssignments[oldSlotId];
            }
            const displacedLabelId = slotAssignments[safeSlotId];
            if (displacedLabelId && displacedLabelId !== safeLabelId) {
                delete labelAssignments[displacedLabelId];
            }
            slotAssignments[safeSlotId] = safeLabelId;
            labelAssignments[safeLabelId] = safeSlotId;
        };
        const moveAssignedLabelToSlot = (sourceSlotId, targetSlotId) => {
            const safeSourceSlotId = String(sourceSlotId || '').trim();
            const safeTargetSlotId = String(targetSlotId || '').trim();
            const draggedLabelId = String(slotAssignments[safeSourceSlotId] || '').trim();
            if (!safeSourceSlotId || !safeTargetSlotId || !draggedLabelId || !slotById[safeTargetSlotId]) {
                return;
            }
            if (safeSourceSlotId === safeTargetSlotId) {
                return;
            }
            const targetLabelId = String(slotAssignments[safeTargetSlotId] || '').trim();
            if (targetLabelId && targetLabelId !== draggedLabelId) {
                slotAssignments[safeSourceSlotId] = targetLabelId;
                labelAssignments[targetLabelId] = safeSourceSlotId;
            } else {
                delete slotAssignments[safeSourceSlotId];
            }
            slotAssignments[safeTargetSlotId] = draggedLabelId;
            labelAssignments[draggedLabelId] = safeTargetSlotId;
        };
        const getSlotClientPoint = (slotId) => {
            const slot = slotById[String(slotId || '').trim()];
            if (!slot) {
                return null;
            }
            const geometry = getLegendImageGeometry(canvas, imageEl);
            if (!geometry) {
                return null;
            }
            return {
                x: geometry.imageRect.left + ((slot.x / 100) * geometry.imageRect.width),
                y: geometry.imageRect.top + ((slot.y / 100) * geometry.imageRect.height)
            };
        };
        const findClosestSlotId = (clientX, clientY) => {
            let bestSlotId = '';
            let bestDistance = Number.POSITIVE_INFINITY;
            slots.forEach(slot => {
                const point = getSlotClientPoint(slot.id);
                if (!point) {
                    return;
                }
                const distance = Math.hypot(clientX - point.x, clientY - point.y);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestSlotId = slot.id;
                }
            });
            return bestDistance <= DRAG_SLOT_SNAP_DISTANCE_PX ? bestSlotId : '';
        };
        const findOverlayMarkerBySlotId = (slotId) => Array.from(overlay.querySelectorAll('.labelimage-player-marker'))
            .find(node => String(node.dataset.slotId || '') === String(slotId || '')) || null;
        const clearDropTargetState = () => {
            overlay.querySelectorAll('.labelimage-player-marker.is-drop-target').forEach(node => node.classList.remove('is-drop-target'));
        };
        const setDropTargetState = (slotId) => {
            clearDropTargetState();
            const node = findOverlayMarkerBySlotId(slotId);
            if (node) {
                node.classList.add('is-drop-target');
            }
        };
        const destroyDragState = () => {
            if (!dragState) {
                return;
            }
            dragState.ghost?.remove();
            document.removeEventListener('pointermove', onDragMove);
            document.removeEventListener('pointerup', onDragEnd);
            document.removeEventListener('pointercancel', onDragEnd);
            canvas.classList.remove('is-dragging');
            clearDropTargetState();
            dragState = null;
        };
        const updateDragVisual = (clientX, clientY) => {
            if (!dragState) {
                return;
            }
            dragState.ghost.style.left = `${clientX + 14}px`;
            dragState.ghost.style.top = `${clientY + 14}px`;
            const hoveredSlotId = findClosestSlotId(clientX, clientY);
            dragState.hoveredSlotId = hoveredSlotId;
            setDropTargetState(hoveredSlotId);
        };
        function onDragMove(e) {
            updateDragVisual(e.clientX, e.clientY);
        }
        function onDragEnd() {
            if (!dragState) {
                return;
            }
            const { sourceSlotId, hoveredSlotId, labelId } = dragState;
            destroyDragState();
            if (hoveredSlotId) {
                moveAssignedLabelToSlot(sourceSlotId, hoveredSlotId);
                activeId = labelId;
            }
            skipNextOverlayClick = true;
            refresh();
        }
        const startMarkerDrag = (sourceSlotId, labelId, clientX, clientY) => {
            const safeSourceSlotId = String(sourceSlotId || '').trim();
            const safeLabelId = String(labelId || '').trim();
            const text = String(labelById[safeLabelId]?.text || '').trim();
            if (!safeSourceSlotId || !safeLabelId || !text) {
                return;
            }
            destroyDragState();
            const ghost = document.createElement('div');
            ghost.className = 'labelimage-player-drag-chip';
            ghost.textContent = text;
            document.body.appendChild(ghost);
            dragState = {
                sourceSlotId: safeSourceSlotId,
                labelId: safeLabelId,
                hoveredSlotId: safeSourceSlotId,
                ghost
            };
            canvas.classList.add('is-dragging');
            activeId = safeLabelId;
            updateDragVisual(clientX, clientY);
            document.addEventListener('pointermove', onDragMove);
            document.addEventListener('pointerup', onDragEnd);
            document.addEventListener('pointercancel', onDragEnd);
        };

        const refresh = () => {
            labelsEl.innerHTML = '';
            overlay.innerHTML = '';
            shuffledLabels.forEach((label, index) => {
                const button = document.createElement('button');
                button.type = 'button';
                button.className = `labelimage-label-btn${activeId === label.id ? ' is-active' : ''}${labelAssignments[label.id] ? ' is-placed' : ''}`;
                button.dataset.labelId = label.id;
                button.innerHTML = `<span class="labelimage-label-num">${index + 1}</span><span>${escapeHtml(label.text)}</span>`;
                labelsEl.appendChild(button);
            });

            slots.forEach((slot, index) => {
                const assignedLabelId = String(slotAssignments[slot.id] || '');
                const isAssigned = assignedLabelId !== '';
                const assignedLabelText = isAssigned ? String(labelById[assignedLabelId]?.text || '') : '';
                const marker = document.createElement('button');
                marker.type = 'button';
                marker.className = `labelimage-player-marker${isAssigned ? ' is-assigned' : ' is-placeholder'}`;
                if (isAssigned && activeId === assignedLabelId) {
                    marker.classList.add('is-current');
                }
                marker.dataset.slotId = slot.id;
                if (isAssigned && assignedLabelText) {
                    const text = document.createElement('span');
                    text.className = 'labelimage-player-marker-text';
                    text.textContent = assignedLabelText;
                    marker.appendChild(text);
                    marker.setAttribute('aria-label', `Emplacement ${index + 1}: ${assignedLabelText}`);
                } else {
                    marker.setAttribute('aria-label', `Emplacement ${index + 1}`);
                }
                placeLegendMarker(marker, slot.x, slot.y, canvas, imageEl);
                marker.title = isAssigned
                    ? `Emplacement ${index + 1}: ${assignedLabelText || 'occupé'}`
                    : `Emplacement ${index + 1}`;
                overlay.appendChild(marker);
            });
        };

        labelsEl.addEventListener('click', function(e) {
            const btn = e.target.closest('.labelimage-label-btn');
            if (!btn) {
                return;
            }
            activeId = String(btn.dataset.labelId || '');
            refresh();
        });

        overlay.addEventListener('click', function(e) {
            if (skipNextOverlayClick) {
                skipNextOverlayClick = false;
                return;
            }
            const marker = e.target.closest('.labelimage-player-marker');
            if (!marker) {
                return;
            }
            const slotId = String(marker.dataset.slotId || '').trim();
            if (!slotId) {
                return;
            }
            if (activeId) {
                assignLabelToSlot(activeId, slotId);
                const nextMissing = getNextUnplacedLabel();
                if (nextMissing) {
                    activeId = nextMissing.id;
                }
            } else {
                activeId = String(slotAssignments[slotId] || '');
            }
            refresh();
        });
        overlay.addEventListener('pointerdown', function(e) {
            const marker = e.target.closest('.labelimage-player-marker.is-assigned');
            if (!marker) {
                return;
            }
            const sourceSlotId = String(marker.dataset.slotId || '').trim();
            const labelId = String(slotAssignments[sourceSlotId] || '').trim();
            if (!sourceSlotId || !labelId) {
                return;
            }
            e.preventDefault();
            startMarkerDrag(sourceSlotId, labelId, e.clientX, e.clientY);
        });

        canvas.addEventListener('click', function(e) {
            if (e.target.closest('.labelimage-player-marker')) {
                return;
            }
        });

        imageEl.addEventListener('load', refresh);
        refresh();
        return {
            requiredCount: labels.length,
            getPlacements: () => labels
                .filter(label => labelAssignments[label.id] && slotById[labelAssignments[label.id]])
                .map(label => ({
                    id: label.id,
                    x: Number(slotById[labelAssignments[label.id]].x),
                    y: Number(slotById[labelAssignments[label.id]].y)
                }))
        };
    }

    function collectQuestionResponsesForCsv(item) {
        const type = normalizeQuestionType(item.type);
        let collectedResponses = [];

        if (type === 'open' || type === 'wordcloud' || type === 'cloze' || type === 'labelimage' || type === 'ranking') {
            collectedResponses = (Array.isArray(item.openResponses) ? item.openResponses : [])
                .map(text => String(text || '').trim())
                .filter(Boolean);
        } else if (type === 'video') {
            collectedResponses = [];
        } else if (type === 'rating') {
            const ratingCounts = item.results && typeof item.results === 'object' ? item.results : {};
            const maxRating = Number.isInteger(item.maxRating) && item.maxRating >= 2 ? item.maxRating : 5;
            for (let rating = 1; rating <= maxRating; rating += 1) {
                const count = Number(ratingCounts[String(rating)] || 0);
                for (let i = 0; i < count; i += 1) {
                    collectedResponses.push(String(rating));
                }
            }
        } else {
            const answers = Array.isArray(item.answers) ? item.answers : [];
            answers.forEach((answer, index) => {
                const count = Number((item.results && (item.results[index] ?? item.results[String(index)])) || 0);
                for (let i = 0; i < count; i += 1) {
                    collectedResponses.push(String(answer || '').trim());
                }
            });
        }

        return collectedResponses;
    }

    function buildParticipantRosterForCsv(report) {
        const roster = [];
        const knownKeys = new Set();
        const usedLabels = new Set();

        (Array.isArray(report?.questions) ? report.questions : []).forEach(item => {
            const entries = Array.isArray(item?.participantResponses) ? item.participantResponses : [];
            entries.forEach((entry, index) => {
                const key = String(entry?.participantKey || '').trim() || `participant-${roster.length + index + 1}`;
                if (knownKeys.has(key)) {
                    return;
                }
                knownKeys.add(key);

                const rawName = String(entry?.participantName || '').trim();
                const fallbackBase = `participant_${roster.length + 1}`;
                const baseLabel = rawName || fallbackBase;
                let label = baseLabel;
                let duplicateIndex = 2;
                while (usedLabels.has(label)) {
                    label = `${baseLabel} (${duplicateIndex})`;
                    duplicateIndex += 1;
                }
                usedLabels.add(label);
                roster.push({ key, label });
            });
        });

        return roster;
    }

    function buildFinalReportCsvAnonymous(report) {
        const responsesByQuestion = report.questions.map(item => collectQuestionResponsesForCsv(item));
        const maxParticipants = responsesByQuestion.reduce((max, responses) => Math.max(max, responses.length), 0);
        const participantHeaders = Array.from({ length: maxParticipants }, (_, index) => `participant_${index + 1}`);
        const headers = ['question', ...participantHeaders];
        const rows = [headers.map(escapeCsvValue).join(',')];

        report.questions.forEach((item, questionIndex) => {
            const collectedResponses = responsesByQuestion[questionIndex] || [];
            const participantColumns = participantHeaders.map((_, participantIndex) => collectedResponses[participantIndex] || '');
            rows.push([
                extractQuestionPlainText(item.question || ''),
                ...participantColumns
            ].map(escapeCsvValue).join(','));
        });

        return rows.join('\n');
    }

    function buildFinalReportCsv(report) {
        const participantRoster = buildParticipantRosterForCsv(report);
        if (participantRoster.length === 0) {
            return buildFinalReportCsvAnonymous(report);
        }

        const headers = ['question', ...participantRoster.map(entry => entry.label)];
        const rows = [headers.map(escapeCsvValue).join(',')];

        report.questions.forEach(item => {
            const responseMap = new Map();
            const participantEntries = Array.isArray(item?.participantResponses) ? item.participantResponses : [];
            participantEntries.forEach(entry => {
                const key = String(entry?.participantKey || '').trim();
                if (!key) {
                    return;
                }
                const text = String(entry?.responseText || '').trim();
                if (!text) {
                    return;
                }
                if (responseMap.has(key)) {
                    responseMap.set(key, `${responseMap.get(key)} | ${text}`);
                    return;
                }
                responseMap.set(key, text);
            });

            rows.push([
                extractQuestionPlainText(item?.question || ''),
                ...participantRoster.map(entry => responseMap.get(entry.key) || '')
            ].map(escapeCsvValue).join(','));
        });

        return rows.join('\n');
    }

    function downloadCsv(report) {
        if (!report || !Array.isArray(report.questions) || report.questions.length === 0) {
            return;
        }

        const csv = buildFinalReportCsv(report);
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const date = new Date();
        const stamp = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        const filename = `audience-bilan-${report.code || 'session'}-${stamp}.csv`;

        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    function renderFinalReport(data) {
        const reportEl = document.getElementById('finalReport');
        const resultsContent = document.getElementById('resultsContent');
        const resultsTimerEl = document.getElementById('resultsQuestionTimer');
        if (resultsTimerEl) {
            resultsTimerEl.classList.add('hidden');
        }
        stopResultsQuestionTimer();
        if (!data || !Array.isArray(data.questions) || data.questions.length === 0) {
            reportEl.classList.add('hidden');
            reportEl.innerHTML = '';
            resultsContent.classList.remove('report-mode');
            state.showingFinalReport = false;
            state.latestFinalReport = null;
            updateResultsNavigationControls();
            return;
        }

        const reportQuestions = data.questions;

        const cards = reportQuestions.map(item => {
            const total = Number(item.total || 0);
            const type = normalizeQuestionType(item.type);
            let rows = '';
            const isLargeWordcloud = state.wordcloudScaleMode === 'large';

            if (type === 'open' || type === 'cloze' || type === 'labelimage') {
                const openResponses = Array.isArray(item.openResponses) ? item.openResponses : [];
                const clozeContext = type === 'cloze'
                    ? `<div class="final-report-answer cloze-preview-item"><strong>Texte à trous :</strong><br>${escapeHtml(maskClozeTemplate(item.clozeText || ''))}</div>`
                    : '';
                const legendContext = type === 'labelimage'
                    ? `<div class="final-report-answer"><strong>Étiquettes :</strong> ${normalizeLegendLabels(item.legendLabels).filter(label => label.text).map(label => escapeHtml(label.text)).join(' | ') || 'Aucune'}</div>`
                    : '';
                rows = `${clozeContext}${legendContext}${openResponses.length
                    ? openResponses.map((text, index) => `
                        <div class="final-report-answer">
                            <div><strong>${index + 1}.</strong> ${escapeHtml(text)}</div>
                        </div>
                    `).join('')
                    : '<p>Aucune réponse</p>'}`;
            } else if (type === 'wordcloud') {
                const keywords = buildKeywordCounts(item.openResponses || []);
                if (keywords.length === 0) {
                    rows = '<p>Aucun mot-clé exploitable.</p>';
                } else {
                    const maxCount = keywords[0].count || 1;
                    const cloud = keywords.slice(0, 40).map(entry => {
                        const visual = getWordCloudVisual(entry.word, entry.count, maxCount, isLargeWordcloud);
                        return `<span class="wordcloud-term" title="${escapeHtml(entry.word)}: ${entry.count}" style="font-size:${visual.size}px;color:${visual.color};font-weight:${visual.weight}">${escapeHtml(entry.word)}</span>`;
                    }).join('');
                    rows = `<div class="wordcloud-container reveal-item${isLargeWordcloud ? ' large' : ''}">${cloud}</div>`;
                }
            } else if (type === 'ranking') {
                const rankingCounts = item.rankingCounts && typeof item.rankingCounts === 'object' ? item.rankingCounts : {};
                const entries = Object.entries(rankingCounts)
                    .sort((a, b) => Number(b[1] || 0) - Number(a[1] || 0))
                    .slice(0, 12);
                rows = `
                    ${entries.length
                        ? entries.map(([order, count], idx) => `
                            <div class="final-report-answer">
                                <div><strong>${idx + 1}.</strong> ${escapeHtml(order)}</div>
                                <div>${Number(count || 0)} vote(s)</div>
                            </div>
                        `).join('')
                        : '<p>Aucune réponse</p>'}
                `;
            } else if (type === 'video') {
                const embedUrl = buildYouTubeEmbedUrl(item.youtubeUrl || '', item.videoStartSec, item.videoEndSec);
                const rangeText = describeVideoRange(item.videoStartSec, item.videoEndSec);
                rows = `
                    <div class="final-report-answer">
                        <div><strong>Vidéo YouTube</strong> (aucune réponse attendue)</div>
                        ${rangeText ? `<div>${escapeHtml(rangeText)}</div>` : ''}
                        <div>${embedUrl ? `<a href="${escapeHtml(embedUrl)}" target="_blank" rel="noopener noreferrer">${escapeHtml(embedUrl)}</a>` : 'URL non valide'}</div>
                    </div>
                `;
            } else if (type === 'rating') {
                const maxRating = Number.isInteger(item.maxRating) ? item.maxRating : 5;
                const avg = Number(item.avgRating || 0);
                const roundedAvg = Math.max(0, Math.min(maxRating, Math.round(avg)));
                const accentColor = getRatingAccentColor(avg, maxRating);
                const averageStars = Array.from({ length: maxRating }, (_, index) => (
                    `<span class="rating-avg-star${index < roundedAvg ? ' is-on' : ''}">★</span>`
                )).join('');
                const distribution = [];
                for (let rating = maxRating; rating >= 1; rating -= 1) {
                    const count = Number((item.results && item.results[String(rating)]) || 0);
                    const pct = total > 0 ? Math.round((count / total) * 100) : 0;
                    distribution.push(`
                        <div class="rating-level-row">
                            <p class="rating-level-label">Niveau ${rating}</p>
                            <div class="rating-level-bar">
                                <div class="rating-level-fill" style="width: ${pct}%;"></div>
                            </div>
                            <p class="rating-level-count">${count}</p>
                        </div>
                    `);
                }
                rows = `
                    <div class="rating-dashboard reveal-item" style="--rating-accent:${accentColor};">
                        <div class="rating-dashboard-avg">
                            <p class="rating-avg-value">${avg.toFixed(2)}</p>
                            <p class="rating-avg-label">Évaluation moyenne</p>
                            <p class="rating-avg-stars">${averageStars}</p>
                            <p class="rating-avg-votes">${total} vote(s)</p>
                        </div>
                        <div class="rating-dashboard-dist">
                            ${distribution.join('')}
                        </div>
                    </div>
                `;
            } else {
                const answers = Array.isArray(item.answers) ? item.answers : ['', '', ''];
                const correctIndexes = Array.isArray(item.correctIndexes)
                    ? item.correctIndexes.map(value => parseInt(value, 10)).filter(value => Number.isInteger(value) && value >= 0)
                    : [];
                rows = answers.map((answer, index) => {
                    const count = Number((item.results && (item.results[index] ?? item.results[String(index)])) || 0);
                    const pct = total ? Math.round((count / total) * 100) : 0;
                    const isCorrect = type === 'checkbox' ? correctIndexes.includes(index) : item.correctIndex === index;
                    return `
                        <div class="final-report-answer ${isCorrect ? 'is-correct' : ''}">
                            <div><strong>${escapeHtml(answer)}</strong>${isCorrect ? ' <span class="correct-tag">Bonne réponse</span>' : ''}</div>
                            <div>${count} ${type === 'checkbox' ? 'sélection(s)' : 'vote(s)'} - ${pct}%</div>
                        </div>
                    `;
                }).join('');
            }

            return `
                <article class="final-report-card reveal-item">
                    <h4>Question ${item.questionIndex + 1}</h4>
                    <div class="final-report-question formatted-question">${sanitizeQuestionRichTextHtml(item.question)}</div>
                    <div class="final-report-answers">${rows}</div>
                    <p class="final-report-total">${type === 'checkbox' ? 'Total sélections' : 'Total réponses'}: ${total}</p>
                </article>
            `;
        }).join('');

        reportEl.innerHTML = `
            <h3>Bilan final du lot</h3>
            <div class="final-report-grid">${cards}</div>
        `;
        renderMathInElementSafe(reportEl);
        const toggleWordcloudSizeBtn = document.getElementById('toggleWordcloudSizeBtn');
        const hasWordcloud = reportQuestions.some(item => normalizeQuestionType(item.type) === 'wordcloud');
        toggleWordcloudSizeBtn.classList.toggle('hidden', !hasWordcloud);
        reportEl.classList.remove('hidden');
        animateStagger(reportEl);
        resultsContent.classList.add('report-mode');
        updateResultsHelpText(null);
        state.showingFinalReport = true;
        state.latestFinalReport = data;
        updateResultsNavigationControls();
        stopResultsPolling();
    }

    async function refreshResultsForCode(code, questionIndex = null) {
        let qPath = `get_question.php?code=${encodeURIComponent(code)}`;
        if (Number.isInteger(questionIndex)) {
            qPath += `&questionIndex=${questionIndex}`;
        }
        if (state.latestQuestionSignature) {
            qPath += `&signature=${encodeURIComponent(state.latestQuestionSignature)}`;
        }

        const qResp = await fetchApi(qPath);
        const qData = await qResp.json();
        if (!qData.success) {
            throw new Error(qData.error || 'Code invalide');
        }
        if (qData.waiting) {
            throw new Error(qData.message || "La session n'est pas encore en direct.");
        }
        if (qData.unchanged && state.latestResultsSnapshot) {
            const cached = state.latestResultsSnapshot.questionData || {};
            const cachedIndex = Number.isInteger(qData.questionIndex)
                ? qData.questionIndex
                : Number.isInteger(state.latestResultsSnapshot.meta?.questionIndex)
                    ? state.latestResultsSnapshot.meta.questionIndex
                    : null;
            if (qData.signature) {
                state.latestQuestionSignature = String(qData.signature);
            }
            if (Number.isInteger(qData.totalQuestions)) {
                state.resultsTotalQuestions = qData.totalQuestions || 1;
            }
            const resultsQuestionMeta = document.getElementById('resultsQuestionMeta');
            if (resultsQuestionMeta && Number.isInteger(cachedIndex) && state.resultsTotalQuestions > 1) {
                resultsQuestionMeta.textContent = `Question ${cachedIndex + 1}/${state.resultsTotalQuestions}`;
                resultsQuestionMeta.classList.remove('hidden');
            } else if (resultsQuestionMeta) {
                resultsQuestionMeta.textContent = '';
                resultsQuestionMeta.classList.add('hidden');
            }
            updateResultsNavigationControls();
            updateSessionCorner(code);
        }

        let rPath = `get_results.php?code=${encodeURIComponent(code)}`;
        if (Number.isInteger(questionIndex)) {
            rPath += `&questionIndex=${questionIndex}`;
        } else if (qData.unchanged && state.latestResultsSnapshot && Number.isInteger(state.latestResultsSnapshot.meta?.questionIndex)) {
            rPath += `&questionIndex=${state.latestResultsSnapshot.meta.questionIndex}`;
        }

        const rResp = await fetchApi(rPath);
        const rData = await rResp.json();
        const effectiveQuestionIndex = qData.unchanged && state.latestResultsSnapshot && Number.isInteger(state.latestResultsSnapshot.meta?.questionIndex)
            ? state.latestResultsSnapshot.meta.questionIndex
            : qData.questionIndex;
        const questionKey = `${code}:${effectiveQuestionIndex}`;
        const previousQuestionKey = state.currentResultsQuestionKey;
        const revealBtn = document.getElementById('revealCorrectBtn');
        const toggleWordcloudSizeBtn = document.getElementById('toggleWordcloudSizeBtn');

        const resultsQuestionMeta = document.getElementById('resultsQuestionMeta');
        const totalQuestions = Number.isInteger(qData.totalQuestions) ? qData.totalQuestions : (state.resultsTotalQuestions || 1);
        if (totalQuestions > 1) {
            resultsQuestionMeta.textContent = `Question ${effectiveQuestionIndex + 1}/${totalQuestions}`;
            resultsQuestionMeta.classList.remove('hidden');
        } else {
            resultsQuestionMeta.textContent = '';
            resultsQuestionMeta.classList.add('hidden');
        }
        if (!qData.unchanged) {
            renderFormattedQuestion(document.getElementById('resultsQuestionText'), qData.question);
        }
        const resultsQuestionImageWrap = document.getElementById('resultsQuestionImageWrap');
        const resultsQuestionImage = document.getElementById('resultsQuestionImage');
        const resultsImageSrc = qData.unchanged
            ? String(state.latestResultsSnapshot?.questionData?.questionImage || '')
            : (isValidQuestionImage(qData.questionImage) ? String(qData.questionImage).trim() : '');
        const resultsImageZoom = qData.unchanged
            ? normalizePublicQuestionImageZoom(state.latestResultsSnapshot?.questionData?.questionImageZoom)
            : normalizePublicQuestionImageZoom(qData.questionImageZoom);
        if (!qData.unchanged && resultsQuestionImageWrap && resultsQuestionImage) {
            resultsQuestionImage.decoding = 'async';
            if (resultsImageSrc) {
                resultsQuestionImage.src = resultsImageSrc;
                resultsQuestionImageWrap.classList.remove('hidden');
                applyQuestionImageSizing(resultsQuestionImageWrap, resultsQuestionImage);
                applyPublicQuestionImageZoom(resultsQuestionImageWrap, resultsQuestionImage, resultsImageZoom);
            } else {
                resultsQuestionImage.removeAttribute('src');
                resultsQuestionImage.style.transform = '';
                resultsQuestionImageWrap.classList.add('hidden');
                resultsQuestionImageWrap.classList.remove('is-landscape-full');
                resultsQuestionImageWrap.classList.remove('is-portrait-large');
            }
        }
        updateResultsHelpText(qData.unchanged ? state.latestResultsSnapshot?.questionData?.type : qData.type);
        state.resultsTotalQuestions = totalQuestions || 1;
        updateResultsNavigationControls();
        updateSessionCorner(code);

        const resolvedType = qData.unchanged
            ? normalizeQuestionType(state.latestResultsSnapshot?.questionData?.type)
            : normalizeQuestionType(qData.type);
        const resolvedQuestion = qData.unchanged
            ? String(state.latestResultsSnapshot?.questionData?.question || '')
            : qData.question;
        const resolvedAnswers = qData.unchanged
            ? (Array.isArray(state.latestResultsSnapshot?.questionData?.answers) ? state.latestResultsSnapshot.questionData.answers : [])
            : qData.answers;
        const resolvedCorrectIndex = qData.unchanged
            ? state.latestResultsSnapshot?.questionData?.correctIndex
            : qData.correctIndex;
        const resolvedCorrectIndexes = qData.unchanged
            ? (Array.isArray(state.latestResultsSnapshot?.questionData?.correctIndexes) ? state.latestResultsSnapshot.questionData.correctIndexes : [])
            : (Array.isArray(qData.correctIndexes) ? qData.correctIndexes : []);
        const resolvedMaxRating = qData.unchanged
            ? (Number.isInteger(state.latestResultsSnapshot?.questionData?.maxRating) ? state.latestResultsSnapshot.questionData.maxRating : 5)
            : (Number.isInteger(qData.maxRating) ? qData.maxRating : 5);
        const resolvedCloze = qData.unchanged
            ? String(state.latestResultsSnapshot?.questionData?.clozeText || '')
            : String(qData.clozeText || '');
        const resolvedYouTube = qData.unchanged
            ? String(state.latestResultsSnapshot?.questionData?.youtubeUrl || '')
            : String(qData.youtubeUrl || '');
        const resolvedVideoStartSec = qData.unchanged
            ? normalizeVideoRange(
                state.latestResultsSnapshot?.questionData?.videoStartSec,
                state.latestResultsSnapshot?.questionData?.videoEndSec
            ).startSec
            : normalizeVideoRange(qData.videoStartSec, qData.videoEndSec).startSec;
        const resolvedVideoEndSec = qData.unchanged
            ? normalizeVideoRange(
                state.latestResultsSnapshot?.questionData?.videoStartSec,
                state.latestResultsSnapshot?.questionData?.videoEndSec
            ).endSec
            : normalizeVideoRange(qData.videoStartSec, qData.videoEndSec).endSec;
        const resolvedLegendLabels = qData.unchanged
            ? normalizeLegendLabels(state.latestResultsSnapshot?.questionData?.legendLabels)
            : normalizeLegendLabels(qData.legendLabels);
        const resolvedParticipantResponsesVisible = qData.unchanged
            ? normalizeParticipantResponsesVisibility(state.latestResultsSnapshot?.questionData?.participantResponsesVisible)
            : normalizeParticipantResponsesVisibility(qData.participantResponsesVisible);
        const resolvedTimeLimitSec = qData.unchanged
            ? normalizeQuestionTimeLimit(state.latestResultsSnapshot?.questionData?.timeLimitSec)
            : normalizeQuestionTimeLimit(qData.timeLimitSec);
        const resolvedQuestionStartedAtMs = qData.unchanged
            ? normalizeQuestionStartedAtMs(state.latestResultsSnapshot?.questionData?.questionStartedAtMs)
            : normalizeQuestionStartedAtMs(qData.questionStartedAtMs);
        const resolvedServerNowMs = Number.isFinite(Number(qData.serverNowMs))
            ? Number(qData.serverNowMs)
            : Date.now();

        const snapshot = {
            questionData: {
                type: resolvedType,
                question: resolvedQuestion,
                questionImage: resultsImageSrc,
                questionImageZoom: resultsImageZoom,
                answers: resolvedAnswers,
                correctIndex: resolvedCorrectIndex,
                correctIndexes: resolvedCorrectIndexes,
                maxRating: resolvedMaxRating,
                clozeText: resolvedCloze,
                youtubeUrl: resolvedYouTube,
                videoStartSec: resolvedVideoStartSec,
                videoEndSec: resolvedVideoEndSec,
                legendLabels: resolvedLegendLabels,
                participantResponsesVisible: resolvedParticipantResponsesVisible,
                timeLimitSec: resolvedTimeLimitSec,
                questionStartedAtMs: resolvedQuestionStartedAtMs
            },
            responseData: rData.success && rData.results ? rData.results : {},
            meta: {
                questionIndex: Number.isInteger(effectiveQuestionIndex) ? effectiveQuestionIndex : 0,
                correctIndex: Number.isInteger(rData.correctIndex) ? rData.correctIndex : resolvedCorrectIndex,
                correctIndexes: Array.isArray(rData.correctIndexes) ? rData.correctIndexes : resolvedCorrectIndexes,
                openResponses: Array.isArray(rData.openResponses) ? rData.openResponses : [],
                totalOpenResponses: Number.isInteger(rData.totalOpenResponses) ? rData.totalOpenResponses : 0,
                rankingCounts: rData.rankingCounts && typeof rData.rankingCounts === 'object' ? rData.rankingCounts : {},
                totalRankingResponses: Number.isInteger(rData.totalRankingResponses) ? rData.totalRankingResponses : 0,
                ratingCounts: rData.ratingCounts && typeof rData.ratingCounts === 'object' ? rData.ratingCounts : {},
                totalRatings: Number.isInteger(rData.totalRatings) ? rData.totalRatings : 0,
                avgRating: Number(rData.avgRating || 0),
                maxRating: Number.isInteger(rData.maxRating) ? rData.maxRating : resolvedMaxRating,
                labelImageResponses: Array.isArray(rData.labelImageResponses) ? rData.labelImageResponses : [],
                totalLabelImageResponses: Number.isInteger(rData.totalLabelImageResponses) ? rData.totalLabelImageResponses : 0
            }
        };
        if (previousQuestionKey !== questionKey) {
            state.revealCorrectAnswer = false;
            state.currentResultsQuestionKey = questionKey;
            state.lastStatsSignature = null;
            state.showParticipantResponses = Object.prototype.hasOwnProperty.call(state.participantResponsesVisibilityOverrides, questionKey)
                ? normalizeParticipantResponsesVisibility(state.participantResponsesVisibilityOverrides[questionKey])
                : resolvedParticipantResponsesVisible;
        } else if (!Object.prototype.hasOwnProperty.call(state.participantResponsesVisibilityOverrides, questionKey)) {
            state.showParticipantResponses = resolvedParticipantResponsesVisible;
        }
        state.latestResultsSnapshot = snapshot;
        if (qData.signature) {
            state.latestQuestionSignature = String(qData.signature);
        }
        toggleWordcloudSizeBtn.classList.toggle('hidden', snapshot.questionData.type !== 'wordcloud');
        if (resolvedType === 'video') {
            stopResultsQuestionTimer();
            const resultsTimerEl = document.getElementById('resultsQuestionTimer');
            if (resultsTimerEl) {
                resultsTimerEl.classList.add('hidden');
            }
        } else {
            startResultsQuestionTimer(resolvedTimeLimitSec, resolvedQuestionStartedAtMs, resolvedServerNowMs);
        }

        const canRevealMultiple = snapshot.questionData.type === 'multiple'
            && (Number.isInteger(snapshot.meta.correctIndex) || Number.isInteger(snapshot.questionData.correctIndex));
        const canRevealCheckbox = snapshot.questionData.type === 'checkbox'
            && ((Array.isArray(snapshot.meta.correctIndexes) && snapshot.meta.correctIndexes.length > 0)
                || (Array.isArray(snapshot.questionData.correctIndexes) && snapshot.questionData.correctIndexes.length > 0));
        const canRevealRanking = snapshot.questionData.type === 'ranking'
            && Array.isArray(snapshot.questionData.answers)
            && snapshot.questionData.answers.filter(item => String(item || '').trim()).length >= 2;
        const canRevealLabelImage = snapshot.questionData.type === 'labelimage'
            && normalizeLegendLabels(snapshot.questionData.legendLabels).some(label =>
                Number.isFinite(Number(label.x)) && Number.isFinite(Number(label.y))
            );
        const canRevealCloze = snapshot.questionData.type === 'cloze'
            && extractClozeExpectedAnswers(snapshot.questionData.clozeText || '').length > 0;

        if (canRevealMultiple || canRevealCheckbox || canRevealRanking || canRevealLabelImage || canRevealCloze) {
            revealBtn.classList.remove('hidden');
            revealBtn.disabled = state.revealCorrectAnswer;
            setRevealButtonLabel(revealBtn, state.revealCorrectAnswer);
        } else {
            revealBtn.classList.add('hidden');
        }

        displayResults(snapshot.questionData, snapshot.responseData, snapshot.meta);
        if (!state.showingFinalReport) {
            document.getElementById('resultsContent').classList.remove('report-mode');
            document.getElementById('finalReport').classList.add('hidden');
            state.latestFinalReport = null;
            state.wordcloudScaleMode = 'compact';
            updateResultsNavigationControls();
        }
    }

    function setupPresenterHandlers() {
        document.getElementById('codeDisplay')?.addEventListener('click', async function(event) {
            const copyBtn = event.target.closest('.code-copy-btn');
            if (!copyBtn) {
                return;
            }
            const code = String(copyBtn.dataset.code || state.code || '').trim();
            if (!code) {
                return;
            }
            const iconEl = copyBtn.querySelector('i');
            copyBtn.disabled = true;
            const copied = await copyTextToClipboard(code);
            copyBtn.disabled = false;
            copyBtn.classList.toggle('is-copied', copied);
            if (iconEl) {
                iconEl.className = copied
                    ? 'fa-solid fa-check'
                    : 'fa-solid fa-xmark';
            }
            copyBtn.title = copied ? 'Code copié !' : 'Copie impossible';
            copyBtn.setAttribute('aria-label', copyBtn.title);
            if (codeCopyFeedbackTimer) {
                clearTimeout(codeCopyFeedbackTimer);
                codeCopyFeedbackTimer = null;
            }
            codeCopyFeedbackTimer = setTimeout(() => {
                copyBtn.classList.remove('is-copied');
                if (iconEl) {
                    iconEl.className = 'fa-regular fa-copy';
                }
                copyBtn.title = "Copier le code d'accès";
                copyBtn.setAttribute('aria-label', copyBtn.title);
                codeCopyFeedbackTimer = null;
            }, 1600);
        });

        startNewQuizBtn?.addEventListener('click', function() {
            state.code = null;
            state.runId = null;
            state.quizTitle = '';
            state.participantReportEnabled = false;
            state.requireParticipantName = true;
            state.batch = [];
            state.currentIndex = 0;
            state.liveActive = false;
            state.latestQuestionSignature = '';
            localStorage.removeItem(SESSION_CODE_KEY);
            localStorage.removeItem(BATCH_STATE_KEY);
            renderBatchEditor();
            if (quizTitleInput) {
                quizTitleInput.value = '';
            }
            if (participantReportEnabledInput) {
                participantReportEnabledInput.checked = false;
            }
            if (requireParticipantNameInput) {
                requireParticipantNameInput.checked = true;
            }
            showBuilderView();
        });

        backHomeBtn?.addEventListener('click', async function() {
            saveEditorDraft(true);
            await syncEditorToServer({ force: true });
            showHomeView();
            loadOwnedQuizzes();
        });

        importQuizMdBtn?.addEventListener('click', function() {
            openImportMarkdownModal();
        });

        importQuizMdInput?.addEventListener('change', async function() {
            const file = this.files && this.files[0];
            if (!file) {
                return;
            }

            try {
                const markdown = await file.text();
                const parsed = applyImportedMarkdown(markdown);
                closeImportMarkdownModal();
                if (importMarkdownTextarea) {
                    importMarkdownTextarea.value = '';
                }
                showSiteNotice(`Import réussi : ${parsed.batch.length} question(s) chargée(s).`, 'success');
            } catch (error) {
                showSiteNotice(error.message || 'Import impossible.', 'error');
            } finally {
                this.value = '';
            }
        });

        const answerOptionsContainer = document.getElementById('answerOptions');
        answerOptionsContainer?.addEventListener('mousedown', function(event) {
            if (event.target.closest('.open-math-editor-btn')) {
                event.preventDefault();
            }
        });
        answerOptionsContainer?.addEventListener('click', function(event) {
            const mathBtn = event.target.closest('.open-math-editor-btn');
            if (!mathBtn) {
                return;
            }
            const textInput = mathBtn.closest('.math-enabled-input-wrap')?.querySelector('input[type="text"], textarea');
            if (!textInput) {
                return;
            }
            openMathInsertModal({
                kind: 'input',
                element: textInput,
                start: Number.isInteger(textInput.selectionStart) ? textInput.selectionStart : textInput.value.length,
                end: Number.isInteger(textInput.selectionEnd) ? textInput.selectionEnd : textInput.value.length
            });
        });

        // Recherche, filtre par date, tri et étiquettes.
        const homeSearchInput = document.getElementById('homeSearchInput');
        const homeDateFilter = document.getElementById('homeDateFilter');
        const homeSortSelect = document.getElementById('homeSortSelect');
        const homeTagFilters = document.getElementById('homeTagFilters');
        let homeSearchTimer = null;

        function syncHomeFilterControls() {
            if (homeSearchInput && homeSearchInput.value !== homeState.filters.query) {
                homeSearchInput.value = homeState.filters.query;
            }
            if (homeDateFilter) {
                homeDateFilter.value = homeState.filters.date;
                homeDateFilter.closest('.home-select')?.classList.toggle('is-active', homeState.filters.date !== 'all');
            }
            if (homeSortSelect) {
                homeSortSelect.value = homeState.filters.sort;
            }
        }

        homeSearchInput?.addEventListener('input', function() {
            clearTimeout(homeSearchTimer);
            homeSearchTimer = setTimeout(() => {
                homeState.filters.query = homeSearchInput.value;
                renderOwnedQuizzes();
            }, 120);
        });
        homeSearchInput?.addEventListener('keydown', function(event) {
            if (event.key === 'Escape' && homeSearchInput.value) {
                event.preventDefault();
                homeSearchInput.value = '';
                homeState.filters.query = '';
                renderOwnedQuizzes();
            }
        });
        homeDateFilter?.addEventListener('change', function() {
            homeState.filters.date = homeDateFilter.value || 'all';
            syncHomeFilterControls();
            renderOwnedQuizzes();
        });
        homeSortSelect?.addEventListener('change', function() {
            homeState.filters.sort = homeSortSelect.value || 'recent';
            renderOwnedQuizzes();
        });
        homeTagFilters?.addEventListener('click', function(event) {
            const chip = event.target.closest('.home-tag-filter');
            if (!chip) {
                return;
            }
            const key = chip.dataset.tag || '';
            homeState.filters.tag = homeState.filters.tag === key ? '' : key;
            renderOwnedQuizzes();
        });

        // Renommage d'un dossier (dans la vue du dossier).
        savedQuizCards?.addEventListener('keydown', function(event) {
            if (event.target.classList?.contains('folder-name-input') && event.key === 'Enter') {
                event.preventDefault();
                event.target.blur();
            }
        });
        savedQuizCards?.addEventListener('change', function(event) {
            const input = event.target;
            if (!input.classList?.contains('folder-name-input')) {
                return;
            }
            const id = Number(input.dataset.folderId);
            const folder = getHomeFolder(id);
            const name = input.value.trim() || 'Nouveau dossier';
            if (!folder || folder.name === name) {
                input.value = folder ? folder.name : name;
                return;
            }
            folder.name = name;
            runHomeAction(async () => {
                await organizeQuizzes({ action: 'update_folder', id, name });
                renderHomeHeader();
            }, 'Renommage impossible.');
        });

        // Glisser-déposer : carte sur carte = nouveau dossier, carte sur dossier = rangement,
        // carte sur « Mes questionnaires » (dans un dossier) = sortie du dossier.
        let draggedQuizCode = '';

        function clearQuizDropTargets() {
            savedQuizCards?.querySelectorAll('.is-drop-target').forEach(el => el.classList.remove('is-drop-target'));
        }

        function getQuizDropTarget(event) {
            if (!draggedQuizCode) {
                return null;
            }
            const folderEl = event.target.closest('.saved-quiz-folder, .saved-quiz-new-folder, .folder-back-btn');
            if (folderEl) {
                return folderEl;
            }
            const cardEl = event.target.closest('.saved-quiz-card');
            if (cardEl && cardEl.dataset.code !== draggedQuizCode && homeState.openFolderId === null) {
                return cardEl;
            }
            return null;
        }

        savedQuizCards?.addEventListener('dragstart', function(event) {
            const card = event.target.closest?.('.saved-quiz-card[draggable="true"]');
            if (!card) {
                return;
            }
            closeQuizMenu();
            draggedQuizCode = card.dataset.code || '';
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData(QUIZ_DRAG_TYPE, draggedQuizCode);
            event.dataTransfer.setData('text/plain', draggedQuizCode);
            requestAnimationFrame(() => {
                card.classList.add('is-dragging');
                savedQuizCards.classList.add('is-drag-active');
            });
        });

        savedQuizCards?.addEventListener('dragover', function(event) {
            const target = getQuizDropTarget(event);
            if (!target) {
                return;
            }
            event.preventDefault();
            event.dataTransfer.dropEffect = 'move';
            if (!target.classList.contains('is-drop-target')) {
                clearQuizDropTargets();
                target.classList.add('is-drop-target');
            }
        });

        savedQuizCards?.addEventListener('dragleave', function(event) {
            const target = event.target.closest?.('.is-drop-target');
            if (target && !target.contains(event.relatedTarget)) {
                target.classList.remove('is-drop-target');
            }
        });

        savedQuizCards?.addEventListener('drop', function(event) {
            const target = getQuizDropTarget(event);
            const code = draggedQuizCode;
            clearQuizDropTargets();
            if (!target || !code) {
                return;
            }
            event.preventDefault();
            if (target.classList.contains('saved-quiz-folder')) {
                const folderId = Number(target.dataset.folderId);
                if (getHomeItem(code)?.folderId === folderId) {
                    return;
                }
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'move', code, folderId });
                    await loadOwnedQuizzes();
                }, 'Déplacement impossible.');
            } else if (target.classList.contains('folder-back-btn')) {
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'move', code, folderId: null });
                    await loadOwnedQuizzes();
                }, 'Déplacement impossible.');
            } else if (target.classList.contains('saved-quiz-new-folder')) {
                runHomeAction(() => createFolderWith([code]), 'Création du dossier impossible.');
            } else if (target.classList.contains('saved-quiz-card')) {
                const otherCode = target.dataset.code || '';
                const otherFolderId = getHomeItem(otherCode)?.folderId ?? null;
                if (otherFolderId !== null) {
                    runHomeAction(async () => {
                        await organizeQuizzes({ action: 'move', code, folderId: otherFolderId });
                        await loadOwnedQuizzes();
                    }, 'Déplacement impossible.');
                } else {
                    runHomeAction(() => createFolderWith([otherCode, code]), 'Création du dossier impossible.');
                }
            }
        });

        savedQuizCards?.addEventListener('dragend', function() {
            draggedQuizCode = '';
            clearQuizDropTargets();
            savedQuizCards.classList.remove('is-drag-active');
            savedQuizCards.querySelectorAll('.is-dragging').forEach(el => el.classList.remove('is-dragging'));
        });

        savedQuizCards?.addEventListener('click', async function(event) {
            const actionBtn = event.target.closest('button[data-action]');
            if (!actionBtn) {
                return;
            }

            const action = actionBtn.dataset.action || '';
            if (action === 'new-quiz') {
                startNewQuizBtn?.click();
                return;
            }
            if (action === 'filter-tag') {
                const key = actionBtn.dataset.tag || '';
                homeState.filters.tag = homeState.filters.tag === key ? '' : key;
                renderOwnedQuizzes();
                return;
            }
            if (action === 'clear-filters') {
                homeState.filters.query = '';
                homeState.filters.date = 'all';
                homeState.filters.tag = '';
                syncHomeFilterControls();
                renderOwnedQuizzes();
                return;
            }
            if (action === 'open-folder') {
                homeState.openFolderId = Number(actionBtn.dataset.folderId);
                renderOwnedQuizzes();
                savedQuizCards.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
                return;
            }
            if (action === 'close-folder') {
                homeState.openFolderId = null;
                renderOwnedQuizzes();
                return;
            }
            if (action === 'new-folder') {
                runHomeAction(() => createFolderWith([]), 'Création du dossier impossible.');
                return;
            }
            if (action === 'card-menu') {
                if (quizMenuAnchor === actionBtn) {
                    closeQuizMenu();
                } else {
                    openQuizMenu(actionBtn, actionBtn.dataset.code);
                }
                return;
            }
            if (action === 'folder-color') {
                const id = Number(actionBtn.dataset.folderId);
                const color = actionBtn.dataset.color || 'indigo';
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'update_folder', id, color });
                    await loadOwnedQuizzes();
                }, 'Changement de couleur impossible.');
                return;
            }
            if (action === 'delete-folder') {
                const folder = getHomeFolder(actionBtn.dataset.folderId);
                if (!folder) {
                    return;
                }
                const confirmed = await window.AudienceDialog.confirm({
                    title: `Supprimer le dossier « ${folder.name || 'Sans nom'} » ?`,
                    message: "Les questionnaires qu'il contient ne sont pas supprimés : ils reviennent sur l'accueil.",
                    confirmLabel: 'Supprimer le dossier',
                    tone: 'danger',
                    icon: 'fa-folder-minus'
                });
                if (!confirmed) {
                    return;
                }
                runHomeAction(async () => {
                    await organizeQuizzes({ action: 'delete_folder', id: folder.id });
                    homeState.openFolderId = null;
                    await loadOwnedQuizzes();
                }, 'Suppression du dossier impossible.');
                return;
            }
            if (action === 'toggle-favorite') {
                const code = String(actionBtn.dataset.code || '').trim();
                const currentlyFavorite = actionBtn.getAttribute('aria-pressed') === 'true';
                try {
                    await setQuizFavorite(code, !currentlyFavorite);
                    await loadOwnedQuizzes();
                } catch (error) {
                    alert(error.message || 'Mise à jour des favoris impossible.');
                }
                return;
            }

            if (action === 'open-edit') {
                const code = String(actionBtn.dataset.code || '').trim();
                try {
                    await loadQuizByCode(code);
                    showBuilderView();
                    updateSessionCorner(state.code);
                } catch (error) {
                    alert(error.message || 'Impossible de charger ce questionnaire.');
                }
                return;
            }

            if (action === 'open-live') {
                const code = String(actionBtn.dataset.code || '').trim();
                try {
                    await loadQuizByCode(code);
                    showLiveView();
                    updateSessionCorner(state.code);
                } catch (error) {
                    alert(error.message || 'Impossible de lancer cette présentation.');
                }
                return;
            }

            const code = actionBtn.dataset.code || '';
            const card = actionBtn.closest('.saved-quiz-card');
            const title = card?.querySelector('h3')?.textContent?.trim() || code;
            if (!code) {
                return;
            }

            if (action === 'export') {
                try {
                    await exportQuizMarkdownByCode(code);
                } catch (error) {
                    alert(error.message || 'Export impossible.');
                }
                return;
            }

            if (action !== 'delete') {
                return;
            }

            const confirmed = await window.AudienceDialog.confirm({
                title: `Supprimer « ${title} » ?`,
                message: `Le questionnaire ${code} sera placé dans la corbeille. Vous pourrez le restaurer depuis le bas de l'accueil.`,
                confirmLabel: 'Mettre à la corbeille',
                tone: 'danger'
            });
            if (!confirmed) {
                return;
            }

            try {
                await deleteOwnedQuiz(code);

                if (state.code === code) {
                    state.code = null;
                    state.runId = null;
                    state.quizTitle = '';
                    state.participantReportEnabled = false;
                    state.requireParticipantName = true;
                    state.batch = [];
                    state.currentIndex = 0;
                    state.liveActive = false;
                    state.latestQuestionSignature = '';
                    localStorage.removeItem(SESSION_CODE_KEY);
                    localStorage.removeItem(BATCH_STATE_KEY);
                    renderBatchEditor();
                    if (quizTitleInput) {
                        quizTitleInput.value = '';
                    }
                    if (participantReportEnabledInput) {
                        participantReportEnabledInput.checked = false;
                    }
                    if (requireParticipantNameInput) {
                        requireParticipantNameInput.checked = true;
                    }
                    showHomeView();
                    updateSessionCorner(null);
                }

                await loadOwnedQuizzes();
                await loadTrashQuizzes();
            } catch (error) {
                alert(error.message || 'Suppression impossible.');
            }
        });

        restoreTrashQuizBtn?.addEventListener('click', async function() {
            const code = trashQuizSelect?.value || '';
            if (!code) {
                return;
            }
            try {
                const resp = await fetchApi('restore_batch.php', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ code })
                });
                const data = await resp.json();
                if (!data.success) {
                    throw new Error(data.error || 'Restauration impossible.');
                }
                await loadOwnedQuizzes();
                await loadTrashQuizzes();
            } catch (error) {
                alert(error.message || 'Restauration impossible.');
            }
        });

        purgeTrashQuizBtn?.addEventListener('click', async function() {
            const code = trashQuizSelect?.value || '';
            if (!code) {
                return;
            }
            const confirmed = await window.AudienceDialog.confirm({
                title: 'Supprimer définitivement ?',
                message: `Le questionnaire ${code} et toutes ses réponses seront effacés. Cette action est irréversible.`,
                confirmLabel: 'Supprimer définitivement',
                tone: 'danger',
                icon: 'fa-triangle-exclamation'
            });
            if (!confirmed) {
                return;
            }
            try {
                const resp = await fetchApi('purge_batch.php', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ code })
                });
                const data = await resp.json();
                if (!data.success) {
                    throw new Error(data.error || 'Suppression définitive impossible.');
                }
                await loadOwnedQuizzes();
                await loadTrashQuizzes();
            } catch (error) {
                alert(error.message || 'Suppression définitive impossible.');
            }
        });

        addQuestionBtn.addEventListener('click', function() {
            batchQuestions.appendChild(createQuestionBlock());
            updateQuestionBlockTitles();
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        batchQuestions.addEventListener('click', function(e) {
            const mathBtn = e.target.closest('.open-math-editor-btn');
            if (mathBtn) {
                const questionEditor = mathBtn.closest('.batch-question-editor-wrap')?.querySelector('.batch-question-input');
                const textInput = mathBtn.closest('.math-enabled-input-wrap')?.querySelector('input[type="text"], textarea');
                if (questionEditor) {
                    openMathInsertModal({
                        kind: 'editor',
                        element: questionEditor,
                        range: captureEditorRange(questionEditor)
                    });
                    return;
                }
                if (textInput) {
                    openMathInsertModal({
                        kind: 'input',
                        element: textInput,
                        start: Number.isInteger(textInput.selectionStart) ? textInput.selectionStart : textInput.value.length,
                        end: Number.isInteger(textInput.selectionEnd) ? textInput.selectionEnd : textInput.value.length
                    });
                    return;
                }
            }

            const moveUpBtn = e.target.closest('.move-up-btn');
            if (moveUpBtn) {
                const block = moveUpBtn.closest('.batch-question-block');
                if (block && block.previousElementSibling) {
                    batchQuestions.insertBefore(block, block.previousElementSibling);
                    updateQuestionBlockTitles();
                    scheduleEditorDraftSave();
                    scheduleServerDraftSave();
                }
                return;
            }

            const moveDownBtn = e.target.closest('.move-down-btn');
            if (moveDownBtn) {
                const block = moveDownBtn.closest('.batch-question-block');
                if (block && block.nextElementSibling) {
                    batchQuestions.insertBefore(block.nextElementSibling, block);
                    updateQuestionBlockTitles();
                    scheduleEditorDraftSave();
                    scheduleServerDraftSave();
                }
                return;
            }

            const removeBtn = e.target.closest('.remove-question-btn');
            if (removeBtn) {
                const blocks = batchQuestions.querySelectorAll('.batch-question-block');
                if (blocks.length <= 1) {
                    return;
                }
                removeBtn.closest('.batch-question-block').remove();
                updateQuestionBlockTitles();
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
                return;
            }

            const clearImageBtn = e.target.closest('.clear-question-image-btn');
            const clearLabelImageBtn = e.target.closest('.clear-labelimage-btn');
            if (clearImageBtn || clearLabelImageBtn) {
                const trigger = clearImageBtn || clearLabelImageBtn;
                const block = trigger.closest('.batch-question-block');
                if (!block) {
                    return;
                }
                const imageDataInput = block.querySelector('.batch-question-image-data');
                const imageFileInputs = block.querySelectorAll('.batch-question-image-input');
                if (imageDataInput) {
                    imageDataInput.value = '';
                }
                imageFileInputs.forEach(input => { input.value = ''; });
                updateQuestionImagePreview(block);
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
                return;
            }

            const toggleImageFieldsBtn = e.target.closest('.toggle-question-image-fields-btn');
            if (!toggleImageFieldsBtn) {
                return;
            }
            const block = toggleImageFieldsBtn.closest('.batch-question-block');
            const imageFields = block?.querySelector('.question-image-fields');
            if (!block || !imageFields) {
                return;
            }
            imageFields.classList.toggle('hidden');
        });

        batchQuestions.addEventListener('change', async function(e) {
            if (e.target.classList.contains('batch-question-image-input')) {
                const block = e.target.closest('.batch-question-block');
                const fileInput = e.target;
                if (!block || !fileInput) {
                    return;
                }
                const selectedType = normalizeQuestionType(block.querySelector('.batch-question-type')?.value);
                if (!supportsQuestionImage(selectedType)) {
                    fileInput.value = '';
                    return;
                }

                const file = fileInput.files && fileInput.files[0] ? fileInput.files[0] : null;
                const imageDataInput = block.querySelector('.batch-question-image-data');
                if (!file || !imageDataInput) {
                    return;
                }
                if (!ALLOWED_QUESTION_IMAGE_TYPES.has(file.type)) {
                    alert('Format non pris en charge. Utilisez PNG, JPG, WebP ou GIF.');
                    fileInput.value = '';
                    return;
                }
                if (file.size > MAX_QUESTION_IMAGE_SOURCE_BYTES) {
                    alert('Image source trop volumineuse (8 Mo maximum).');
                    fileInput.value = '';
                    return;
                }

                try {
                    const dataUrl = await optimizeQuestionImageFile(file);
                    if (!isValidQuestionImage(dataUrl)) {
                        throw new Error('Format image non valide.');
                    }
                    const uploadedUrl = await uploadQuestionImageAsset(dataUrl, file.name || 'image.webp');
                    imageDataInput.value = uploadedUrl;
                    updateQuestionImagePreview(block);
                    scheduleEditorDraftSave();
                } catch (error) {
                    imageDataInput.value = '';
                    fileInput.value = '';
                    updateQuestionImagePreview(block);
                    alert(error.message || "Impossible d'ajouter l'image.");
                }
                return;
            }

            if (e.target.classList.contains('batch-participant-responses-toggle')) {
                updateLiveParticipantResponsesButton();
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
                return;
            }

            if (e.target.classList.contains('batch-poll-mode-toggle')) {
                const block = e.target.closest('.batch-question-block');
                if (block) {
                    const selectedType = normalizeQuestionType(block.querySelector('.batch-question-type')?.value);
                    updateChoiceEditorMode(block, selectedType);
                }
                scheduleEditorDraftSave();
                scheduleServerDraftSave();
                return;
            }

            if (!e.target.classList.contains('batch-question-type')) {
                return;
            }

            const block = e.target.closest('.batch-question-block');
            if (!block) {
                return;
            }

            const selectedType = normalizeQuestionType(e.target.value);
            const isChoice = isChoiceQuestionType(selectedType);
            const isCloze = selectedType === 'cloze';
            const isRanking = selectedType === 'ranking';
            const isVideo = selectedType === 'video';
            const isLabelImage = selectedType === 'labelimage';
            block.dataset.type = selectedType;

            const multipleFields = block.querySelector('.question-multiple-fields');
            const openFields = block.querySelector('.question-open-fields');
            const clozeFields = block.querySelector('.question-cloze-fields');
            const rankingFields = block.querySelector('.question-ranking-fields');
            const videoFields = block.querySelector('.question-video-fields');
            const labelImageFields = block.querySelector('.question-labelimage-fields');
            const labelImageUploadFields = block.querySelector('.question-labelimage-image-fields');
            const openResponseRow = block.querySelector('.question-open-response-row');
            const participantResponsesRow = block.querySelector('.question-participant-responses-row');
            const timerRow = block.querySelector('.question-timer-row');
            const timerSelect = block.querySelector('.batch-time-limit-select');
            const imageToggleRow = block.querySelector('.question-image-toggle-row');
            const imageFields = block.querySelector('.question-image-fields');
            const clozeInput = block.querySelector('.batch-cloze-text');
            const videoInput = block.querySelector('.batch-video-url');

            if (multipleFields) {
                multipleFields.classList.toggle('hidden', !isChoice);
            }
            if (openFields) {
                openFields.classList.toggle('hidden', isChoice);
                const helper = openFields.querySelector('.open-question-help');
                if (helper) {
                    const helperText = getOpenQuestionHelpText(selectedType);
                    helper.textContent = helperText;
                    helper.classList.toggle('hidden', !helperText);
                }
            }
            if (openResponseRow) {
                openResponseRow.classList.toggle('hidden', selectedType !== 'open');
            }
            if (participantResponsesRow) {
                participantResponsesRow.classList.toggle('hidden', isVideo);
            }
            if (clozeFields) {
                clozeFields.classList.toggle('hidden', !isCloze);
            }
            if (rankingFields) {
                rankingFields.classList.toggle('hidden', !isRanking);
            }
            if (videoFields) {
                videoFields.classList.toggle('hidden', !isVideo);
            }
            if (timerRow) {
                timerRow.classList.toggle('hidden', isVideo);
            }
            if (timerSelect) {
                timerSelect.disabled = isVideo;
                if (isVideo) {
                    timerSelect.value = String(DEFAULT_QUESTION_TIME_LIMIT_SEC);
                }
            }
            if (labelImageFields) {
                labelImageFields.classList.toggle('hidden', !isLabelImage);
            }
            if (labelImageUploadFields) {
                labelImageUploadFields.classList.toggle('hidden', !isLabelImage);
            }
            if (imageToggleRow) {
                imageToggleRow.classList.toggle('hidden', !supportsQuestionImage(selectedType) || isLabelImage);
            }
            if (imageFields) {
                const hasImage = getQuestionImageFromBlock(block) !== '';
                if (isLabelImage) {
                    imageFields.classList.add('hidden');
                } else {
                    imageFields.classList.toggle('hidden', !supportsQuestionImage(selectedType) || !hasImage);
                }
            }
            if (clozeInput) {
                clozeInput.required = isCloze;
            }
            if (videoInput) {
                videoInput.required = isVideo;
            }
            updateChoiceEditorMode(block, selectedType);
            updateQuestionImagePreview(block);
            updateLiveParticipantResponsesButton();
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        batchQuestions.addEventListener('mousedown', function(e) {
            if (e.target.closest('.open-math-editor-btn')) {
                e.preventDefault();
            }
        });

        batchQuestions.addEventListener('dragstart', function(e) {
            const handle = e.target.closest('.drag-question-handle');
            if (!handle) {
                return;
            }
            const block = handle.closest('.batch-question-block');
            if (!block) {
                return;
            }

            draggedQuestionBlock = block;
            block.classList.add('is-dragging');
            batchQuestions.classList.add('drag-active');
            if (e.dataTransfer) {
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', block.dataset.uid || '');
            }
        });

        batchQuestions.addEventListener('dragover', function(e) {
            if (!draggedQuestionBlock) {
                return;
            }
            e.preventDefault();
            const afterBlock = getDropAfterQuestionBlock(e.clientY);
            if (!afterBlock) {
                batchQuestions.appendChild(draggedQuestionBlock);
            } else if (afterBlock !== draggedQuestionBlock) {
                batchQuestions.insertBefore(draggedQuestionBlock, afterBlock);
            }
        });

        batchQuestions.addEventListener('drop', function(e) {
            if (!draggedQuestionBlock) {
                return;
            }
            e.preventDefault();
            updateQuestionBlockTitles();
            clearQuestionDragState();
        });

        batchQuestions.addEventListener('dragend', function() {
            if (!draggedQuestionBlock) {
                return;
            }
            updateQuestionBlockTitles();
            clearQuestionDragState();
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });

        quizTitleInput?.addEventListener('input', scheduleEditorDraftSave);
        quizTitleInput?.addEventListener('input', scheduleServerDraftSave);
        participantReportEnabledInput?.addEventListener('change', function() {
            state.participantReportEnabled = normalizeParticipantReportEnabled(this.checked);
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });
        requireParticipantNameInput?.addEventListener('change', function() {
            state.requireParticipantName = normalizeRequireParticipantName(this.checked);
            scheduleEditorDraftSave();
            scheduleServerDraftSave();
        });
        batchQuestions.addEventListener('input', scheduleEditorDraftSave);
        batchQuestions.addEventListener('input', scheduleServerDraftSave);
        batchQuestions.addEventListener('change', scheduleEditorDraftSave);
        batchQuestions.addEventListener('change', scheduleServerDraftSave);

        questionForm.addEventListener('submit', async function(e) {
            e.preventDefault();
            if (isSubmittingBatch) {
                return;
            }

            const collected = collectBatchFromEditor();
            if (collected.error) {
                alert(collected.error);
                return;
            }

            state.code = state.code || getOrCreateSessionCode(true);
            state.quizTitle = (quizTitleInput?.value || '').trim();
            state.participantReportEnabled = normalizeParticipantReportEnabled(participantReportEnabledInput?.checked);
            state.requireParticipantName = normalizeRequireParticipantName(requireParticipantNameInput?.checked);
            if (!state.quizTitle) {
                alert('Merci de renseigner un nom pour le questionnaire.');
                return;
            }
            state.runId = generateRunId();
            state.batch = normalizeBatchQuestionTiming(collected.batch);
            state.currentIndex = 0;
            state.liveActive = false;

            if (draftSaveTimer) {
                clearTimeout(draftSaveTimer);
                draftSaveTimer = null;
            }
            if (serverDraftSaveTimer) {
                clearTimeout(serverDraftSaveTimer);
                serverDraftSaveTimer = null;
            }

            const submitBtn = questionForm.querySelector('button[type="submit"]');
            const originalSubmitHtml = submitBtn ? submitBtn.innerHTML : '';
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>Démarrage...';
            }
            isSubmittingBatch = true;

            try {
                let lastPublishError = null;
                const maxAttempts = 5;
                for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
                    try {
                        await publishCurrentQuestion({ resetAllResponses: true });
                        lastPublishError = null;
                        break;
                    } catch (error) {
                        lastPublishError = error;
                        state.code = getOrCreateSessionCode(true);
                    }
                }
                if (lastPublishError) {
                    throw lastPublishError;
                }
                saveBatchState();
                clearEditorDraft();
                renderLiveQuestion();
                showLiveView();
                loadOwnedQuizzes();
                loadTrashQuizzes();
            } catch (error) {
                alert(error.message || 'Erreur lors de la publication du lot.');
            } finally {
                isSubmittingBatch = false;
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = originalSubmitHtml;
                }
            }
        });

        document.getElementById('nextQuestionBtn').addEventListener('click', async function() {
            await advanceToNextQuestion();
        });
        document.getElementById('prevQuestionBtn').addEventListener('click', async function() {
            const moved = await advanceToPreviousQuestion();
            if (!moved && state.currentIndex <= 0) {
                alert('Vous êtes déjà sur la première question du lot.');
            }
        });

        document.getElementById('createNewBtn').addEventListener('click', function() {
            renderBatchEditor(state.batch);
            showBuilderView();
        });

        document.getElementById('newSessionBtn')?.addEventListener('click', async function() {
            if (!Array.isArray(state.batch) || state.batch.length === 0) {
                alert('Aucun questionnaire à relancer.');
                return;
            }

            const btn = this;
            const original = btn.innerHTML;
            btn.disabled = true;
            btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>Relance...';

            try {
                state.currentIndex = 0;
                state.liveActive = false;
                state.revealCorrectAnswer = false;
                state.showParticipantResponses = true;
                state.participantResponsesVisibilityOverrides = {};
                state.currentResultsQuestionKey = null;
                state.latestResultsSnapshot = null;
                state.latestQuestionSignature = '';
                state.lastStatsSignature = null;
                state.resultsTotalQuestions = Math.max(1, state.batch.length);
                state.showingFinalReport = false;
                state.latestFinalReport = null;
                state.runId = generateRunId();

                let lastError = null;
                const maxAttempts = 5;
                for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
                    try {
                        state.code = state.code || getOrCreateSessionCode(false);
                        await publishCurrentQuestion({ resetAllResponses: true });
                        lastError = null;
                        break;
                    } catch (error) {
                        lastError = error;
                    }
                }
                if (lastError) {
                    throw lastError;
                }

                saveBatchState();
                renderLiveQuestion();
                showLiveView();
                updateSessionCorner(state.code);
                loadOwnedQuizzes();
                loadTrashQuizzes();
            } catch (error) {
                alert(error.message || 'Impossible de relancer une nouvelle session.');
            } finally {
                btn.disabled = false;
                btn.innerHTML = original;
            }
        });

        document.getElementById('toggleAllParticipantResponsesBtn')?.addEventListener('click', async function() {
            const shouldShow = !areParticipantResponsesVisibleForAllQuestions(state.batch);
            const btn = this;
            const original = btn.innerHTML;
            btn.disabled = true;
            btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>Mise à jour...';

            try {
                await applyParticipantResponsesVisibilityToEntireBatch(shouldShow);
            } catch (error) {
                showSiteNotice(error.message || 'Impossible de mettre à jour l’affichage des réponses.', 'error');
            } finally {
                btn.disabled = false;
                btn.innerHTML = original;
                updateLiveParticipantResponsesButton();
            }
        });

        document.getElementById('viewResultsBtn').addEventListener('click', async function() {
            try {
                await ensureSessionLive();
            } catch (error) {
                alert(error.message || "Impossible d'activer la session.");
                return;
            }

            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById('resultsTab').classList.add('active');
            document.getElementById('resultsBtn')?.classList.add('active');

            document.getElementById('resultsCode').value = state.code;
            document.getElementById('resultsForm').classList.add('hidden');
            document.getElementById('resultsForm').dispatchEvent(new Event('submit'));
            startResultsPolling();
            updateSessionCorner(state.code);
        });

        window.addEventListener('beforeunload', function() {
            saveEditorDraft();
        });
    }

    function setupResultsHandlers() {
        document.getElementById('resultsForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            const code = document.getElementById('resultsCode').value.trim();
            if (!code) {
                return;
            }

            try {
                await refreshResultsForCode(code);
                startResultsPolling();
            } catch (error) {
                alert(error.message || 'Erreur de récupération des résultats.');
            }
        });

        document.getElementById('toggleWordcloudSizeBtn').addEventListener('click', function() {
            state.wordcloudScaleMode = state.wordcloudScaleMode === 'large' ? 'compact' : 'large';
            updateResultsNavigationControls();

            if (state.showingFinalReport && state.latestFinalReport) {
                renderFinalReport(state.latestFinalReport);
                return;
            }

            if (state.latestResultsSnapshot) {
                displayResults(
                    state.latestResultsSnapshot.questionData,
                    state.latestResultsSnapshot.responseData,
                    state.latestResultsSnapshot.meta
                );
            }
        });

        document.getElementById('toggleParticipantResponsesBtn').addEventListener('click', function() {
            if (!state.latestResultsSnapshot || state.showingFinalReport) {
                return;
            }

            state.showParticipantResponses = !state.showParticipantResponses;
            if (state.currentResultsQuestionKey) {
                state.participantResponsesVisibilityOverrides[state.currentResultsQuestionKey] = state.showParticipantResponses;
            }
            updateResultsNavigationControls();

            displayResults(
                state.latestResultsSnapshot.questionData,
                state.latestResultsSnapshot.responseData,
                state.latestResultsSnapshot.meta
            );
        });

        document.getElementById('revealCorrectBtn').addEventListener('click', function() {
            if (!state.latestResultsSnapshot) {
                return;
            }

            state.revealCorrectAnswer = true;
            this.disabled = true;
            setRevealButtonLabel(this, true);

            displayResults(
                state.latestResultsSnapshot.questionData,
                state.latestResultsSnapshot.responseData,
                state.latestResultsSnapshot.meta
            );
        });

        document.getElementById('prevFromResultsBtn').addEventListener('click', async function() {
            const moved = await advanceToPreviousQuestion();
            if (!moved && state.currentIndex <= 0) {
                alert('Vous êtes déjà sur la première question du lot.');
            }
            if (moved) {
                state.showingFinalReport = false;
                state.latestFinalReport = null;
                document.getElementById('resultsContent').classList.remove('report-mode');
                document.getElementById('finalReport').classList.add('hidden');
                updateResultsNavigationControls();
                startResultsPolling();
            }
        });

        document.getElementById('nextFromResultsBtn').addEventListener('click', async function() {
            const moved = await advanceToNextQuestion();
            if (!moved && state.batch.length && state.currentIndex >= state.batch.length - 1) {
                alert('Vous êtes déjà sur la dernière question du lot.');
            }
            if (moved) {
                state.showingFinalReport = false;
                state.latestFinalReport = null;
                document.getElementById('resultsContent').classList.remove('report-mode');
                document.getElementById('finalReport').classList.add('hidden');
                updateResultsNavigationControls();
                startResultsPolling();
            }
        });

        document.getElementById('showFinalReportBtn').addEventListener('click', async function() {
            const code = document.getElementById('resultsCode').value.trim();
            if (!code) {
                return;
            }

            try {
                const resp = await fetchApi(`get_batch_results.php?code=${encodeURIComponent(code)}`);
                const data = await resp.json();
                if (!data.success) {
                    throw new Error(data.error || 'Impossible de charger le bilan final.');
                }
                renderFinalReport(data);
            } catch (error) {
                alert(error.message || 'Erreur lors du chargement du bilan final.');
            }
        });

        document.getElementById('exportCsvBtn').addEventListener('click', function() {
            if (!state.latestFinalReport) {
                alert('Affichez d\'abord le bilan final.');
                return;
            }
            downloadCsv(state.latestFinalReport);
        });

        document.getElementById('backToQuestionBtn').addEventListener('click', function() {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById('createTab').classList.add('active');
            document.getElementById('resultsBtn')?.classList.remove('active');
            tabsNav.classList.add('hidden');
            stopResultsPolling();
            updateSessionCorner(state.code);
        });

        document.getElementById('goHomeFromResultsBtn').addEventListener('click', function() {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById('createTab').classList.add('active');
            document.getElementById('resultsBtn')?.classList.remove('active');
            stopResultsPolling();
            showHomeView();
            updateSessionCorner(null);
        });
    }

    function setupAnswerTabHandlers() {
        const codeForm = document.getElementById('codeForm');
        const accessCodeInput = document.getElementById('accessCode');

        if (!codeForm || !accessCodeInput) {
            return;
        }

        codeForm.addEventListener('submit', function(e) {
            e.preventDefault();

            const code = accessCodeInput.value.trim();
            if (!code) {
                return;
            }
            const nextUrl = new URL('r.html', window.location.href);
            nextUrl.searchParams.set('c', code);
            window.location.href = nextUrl.toString();
        });
    }

    function restoreState() {
        renderBatchEditor();

        const savedRaw = localStorage.getItem(BATCH_STATE_KEY);
        if (!savedRaw) {
            return;
        }

        try {
            const saved = JSON.parse(savedRaw);
            if (!saved || !saved.code || !Array.isArray(saved.batch) || saved.batch.length === 0) {
                return;
            }

            state.code = saved.code;
            state.runId = saved.batch[0] && typeof saved.batch[0] === 'object'
                ? String(saved.batch[0].runId || '').trim() || null
                : null;
            state.quizTitle = String(saved.quizTitle || '');
            state.participantReportEnabled = normalizeParticipantReportEnabled(saved.participantReportEnabled);
            state.requireParticipantName = normalizeRequireParticipantName(saved.requireParticipantName);
            state.batch = normalizeBatchQuestionTiming(saved.batch);
            state.currentIndex = Math.max(0, Math.min(saved.currentIndex || 0, state.batch.length - 1));
            state.liveActive = !!saved.liveActive;
            if (quizTitleInput) {
                quizTitleInput.value = state.quizTitle;
            }
            if (participantReportEnabledInput) {
                participantReportEnabledInput.checked = state.participantReportEnabled;
            }
            if (requireParticipantNameInput) {
                requireParticipantNameInput.checked = state.requireParticipantName !== false;
            }

            safeSetLocalStorage(SESSION_CODE_KEY, state.code);
            renderLiveQuestion();
            showLiveView();
            updateSessionCorner(state.code);
        } catch (_) {
            // Etat ignore si invalide
        }
    }

    async function initApp() {
        const scheduleCompaction = () => {
            if (typeof window.requestIdleCallback === 'function') {
                window.requestIdleCallback(() => compactLocalStoragePayloads(), { timeout: 1200 });
                return;
            }
            window.setTimeout(() => compactLocalStoragePayloads(), 0);
        };
        scheduleCompaction();
        const ok = await ensureAuthenticated();
        if (!ok) {
            return;
        }
        updateAccountBar();
        setupTabs();
        setupPresenterHandlers();
        setupResultsHandlers();
        setupAnswerTabHandlers();
        updateResultsNavigationControls();
        showHomeView();
        await loadOwnedQuizzes();
        await loadTrashQuizzes();
        updateSessionCorner(null);
    }

    initApp();
});
