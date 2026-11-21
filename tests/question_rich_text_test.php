<?php
declare(strict_types=1);
require_once __DIR__ . '/../lib/question_rich_text.php';

function expectSame(string $actual, string $expected): void {
    if ($actual !== $expected) {
        throw new RuntimeException('Expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

// Saving an unformatted question repeatedly must never add another &amp; layer.
foreach ([
    "De quel organe s'agit-il ?",
    'De quel organe s&#39;agit-il ?',
    'De quel organe s&#039;agit-il ?',
    'De quel organe s&#x27;agit-il ?',
    'De quel organe s&rsquo;agit-il ?',
    'Été &amp; hiver',
    '2 &lt; 3 &amp; 4 &gt; 1',
    "Une question\nPuis une autre",
    '<p>Du <b>texte</b> &amp; des <i>accents</i>.</p>',
] as $input) {
    $first = normalizeQuestionRichText($input);
    $saved = $first;
    for ($i = 0; $i < 5; $i++) {
        $saved = normalizeQuestionRichText($saved);
        expectSame($saved, $first);
    }
}

expectSame(normalizeQuestionRichText('s&#39;agit-il ?'), 's&#39;agit-il ?');
expectSame(normalizeQuestionRichText('Été & hiver'), 'Été &amp; hiver');
expectSame(normalizeQuestionRichText('2 &lt; 3 &amp; 4 &gt; 1'), '2 &lt; 3 &amp; 4 &gt; 1');
// Existing encoded markup stays inert; HTML sanitation still removes unsafe tags.
expectSame(normalizeQuestionRichText('&lt;script&gt;alert(1)&lt;/script&gt;'), '&lt;script&gt;alert(1)&lt;/script&gt;');
expectSame(normalizeQuestionRichText('<p onclick="alert(1)">Texte<script>alert(1)</script><b> fort</b></p>'), '<p>Texte<strong> fort</strong></p>');
expectSame(extractQuestionPlainText(normalizeQuestionRichText("De quel organe s'agit-il ?")), "De quel organe s'agit-il ?");

echo "Question rich-text checks passed.\n";
