<?php
declare(strict_types=1);

final class AudienceSimplePdf
{
    private float $pageWidth;
    private float $pageHeight;
    /** @var array<int, string> */
    private array $pages = [];
    private int $currentPageIndex = -1;
    /** @var array<string, array{data: string, width: int, height: int}> */
    private array $images = [];

    public function __construct(float $pageWidth = 595.28, float $pageHeight = 841.89)
    {
        $this->pageWidth = $pageWidth;
        $this->pageHeight = $pageHeight;
    }

    public function getPageWidth(): float
    {
        return $this->pageWidth;
    }

    public function getPageHeight(): float
    {
        return $this->pageHeight;
    }

    public function addPage(): void
    {
        $this->pages[] = '';
        $this->currentPageIndex = count($this->pages) - 1;
    }

    public function pageCount(): int
    {
        return count($this->pages);
    }

    public function setLineWidth(float $width): void
    {
        $this->write($this->formatNumber(max(0.1, $width)) . " w\n");
    }

    public function setStrokeColor(int $red, int $green, int $blue): void
    {
        $this->write($this->formatColor($red, $green, $blue) . " RG\n");
    }

    public function setFillColor(int $red, int $green, int $blue): void
    {
        $this->write($this->formatColor($red, $green, $blue) . " rg\n");
    }

    public function setTextColor(int $red, int $green, int $blue): void
    {
        $this->setFillColor($red, $green, $blue);
    }

    public function roundedRect(float $x, float $y, float $width, float $height, float $radius, string $style = 'B'): void
    {
        if ($width <= 0 || $height <= 0) {
            return;
        }

        $radius = max(0.0, min($radius, min($width, $height) / 2));
        $k = 0.5522847498;
        $bottomY = $this->pageHeight - $y - $height;

        $x0 = $x;
        $x1 = $x + $width;
        $y0 = $bottomY;
        $y1 = $bottomY + $height;
        $c = $radius * $k;

        $op = 'B';
        if ($style === 'F') {
            $op = 'f';
        } elseif ($style === 'S') {
            $op = 'S';
        }

        $path = [];
        $path[] = $this->formatPoint($x0 + $radius, $y0) . ' m';
        $path[] = $this->formatPoint($x1 - $radius, $y0) . ' l';
        $path[] = $this->formatCurve($x1 - $radius + $c, $y0, $x1, $y0 + $radius - $c, $x1, $y0 + $radius);
        $path[] = $this->formatPoint($x1, $y1 - $radius) . ' l';
        $path[] = $this->formatCurve($x1, $y1 - $radius + $c, $x1 - $radius + $c, $y1, $x1 - $radius, $y1);
        $path[] = $this->formatPoint($x0 + $radius, $y1) . ' l';
        $path[] = $this->formatCurve($x0 + $radius - $c, $y1, $x0, $y1 - $radius + $c, $x0, $y1 - $radius);
        $path[] = $this->formatPoint($x0, $y0 + $radius) . ' l';
        $path[] = $this->formatCurve($x0, $y0 + $radius - $c, $x0 + $radius - $c, $y0, $x0 + $radius, $y0);
        $path[] = $op;

        $this->write(implode("\n", $path) . "\n");
    }

    public function textLine(float $x, float $y, string $text, float $fontSize = 12.0, string $font = 'F1'): void
    {
        $trimmed = str_replace(["\r", "\n"], ' ', $text);
        if ($trimmed === '') {
            return;
        }

        $encoded = $this->escapePdfText($trimmed);
        if ($encoded === '') {
            return;
        }

        $pdfY = $this->pageHeight - $y - $fontSize;
        $this->write(sprintf(
            "BT /%s %s Tf 1 0 0 1 %s %s Tm (%s) Tj ET\n",
            $font,
            $this->formatNumber($fontSize),
            $this->formatNumber($x),
            $this->formatNumber($pdfY),
            $encoded
        ));
    }

    /**
     * @return string[]
     */
    public function wrapText(string $text, float $maxWidth, float $fontSize): array
    {
        $clean = str_replace(["\r\n", "\r"], "\n", $text);
        $paragraphs = explode("\n", $clean);
        $lines = [];

        foreach ($paragraphs as $paragraph) {
            $paragraph = trim(preg_replace('/\s+/u', ' ', $paragraph) ?? '');
            if ($paragraph === '') {
                if ($lines !== [] && end($lines) !== '') {
                    $lines[] = '';
                }
                continue;
            }

            $words = preg_split('/\s+/u', $paragraph) ?: [];
            $currentLine = '';
            foreach ($words as $word) {
                $candidate = $currentLine === '' ? $word : ($currentLine . ' ' . $word);
                if ($currentLine !== '' && $this->measureText($candidate, $fontSize) > $maxWidth) {
                    $lines[] = $currentLine;
                    $currentLine = $this->breakWord($word, $maxWidth, $fontSize, $lines);
                    continue;
                }
                if ($currentLine === '' && $this->measureText($word, $fontSize) > $maxWidth) {
                    $currentLine = $this->breakWord($word, $maxWidth, $fontSize, $lines);
                    continue;
                }
                $currentLine = $candidate;
            }
            if ($currentLine !== '') {
                $lines[] = $currentLine;
            }
        }

        while ($lines !== [] && end($lines) === '') {
            array_pop($lines);
        }

        return $lines === [] ? [''] : $lines;
    }

    public function measureText(string $text, float $fontSize): float
    {
        $width = 0.0;
        $chars = preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY) ?: [];
        foreach ($chars as $char) {
            $width += $this->characterWidthFactor($char);
        }
        return $width * $fontSize;
    }

    public function registerLogoFromPng(string $path, string $name = 'Im1'): ?string
    {
        if (!extension_loaded('gd') || !is_file($path)) {
            return null;
        }

        $image = @imagecreatefrompng($path);
        if ($image === false) {
            return null;
        }

        $croppedImage = $this->cropImageToOpaqueBounds($image, 12);
        if ($croppedImage !== null) {
            $image = $croppedImage;
        }

        return $this->storeImageFromGd($image, $name);
    }

    public function registerImageFromDataUrl(string $dataUrl, string $name = 'Im2'): ?string
    {
        if (!extension_loaded('gd')) {
            return null;
        }

        $dataUrl = trim($dataUrl);
        if ($dataUrl === '' || !preg_match('#^data:image/(png|jpeg|jpg|webp);base64,(.+)$#i', $dataUrl, $matches)) {
            return null;
        }

        $binary = base64_decode($matches[2], true);
        if ($binary === false || $binary === '') {
            return null;
        }

        $image = @imagecreatefromstring($binary);
        if ($image === false) {
            return null;
        }

        return $this->storeImageFromGd($image, $name);
    }

    /**
     * @return array{data: string, width: int, height: int}|null
     */
    public function getImageInfo(string $name): ?array
    {
        return $this->images[$name] ?? null;
    }

    public function drawImage(string $name, float $x, float $y, float $width, float $height): void
    {
        if (!isset($this->images[$name])) {
            return;
        }

        $pdfY = $this->pageHeight - $y - $height;
        $this->write(sprintf(
            "q %s 0 0 %s %s %s cm /%s Do Q\n",
            $this->formatNumber($width),
            $this->formatNumber($height),
            $this->formatNumber($x),
            $this->formatNumber($pdfY),
            $name
        ));
    }

    public function output(): string
    {
        if ($this->pages === []) {
            $this->addPage();
        }

        $fontObjectIds = [
            'F1' => 3,
            'F2' => 4
        ];

        $nextObjectId = 5;
        $imageObjectIds = [];
        foreach ($this->images as $name => $_image) {
            $imageObjectIds[$name] = $nextObjectId;
            $nextObjectId += 1;
        }

        $pageContentObjectIds = [];
        $pageObjectIds = [];
        foreach ($this->pages as $_pageContent) {
            $pageContentObjectIds[] = $nextObjectId;
            $nextObjectId += 1;
            $pageObjectIds[] = $nextObjectId;
            $nextObjectId += 1;
        }

        $objects = [];
        $objects[1] = "<< /Type /Catalog /Pages 2 0 R >>";
        $objects[2] = "<< /Type /Pages /Kids [" . implode(' ', array_map(static fn(int $id): string => $id . " 0 R", $pageObjectIds)) . "] /Count " . count($pageObjectIds) . " >>";
        $objects[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>";
        $objects[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>";

        foreach ($this->images as $name => $image) {
            $data = $image['data'];
            $objectId = $imageObjectIds[$name];
            $objects[$objectId] = "<< /Type /XObject /Subtype /Image /Width {$image['width']} /Height {$image['height']} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " . strlen($data) . " >>\nstream\n" . $data . "\nendstream";
        }

        foreach ($this->pages as $index => $content) {
            $contentObjectId = $pageContentObjectIds[$index];
            $pageObjectId = $pageObjectIds[$index];
            $objects[$contentObjectId] = "<< /Length " . strlen($content) . " >>\nstream\n" . $content . "endstream";

            $resources = "<< /Font << /F1 {$fontObjectIds['F1']} 0 R /F2 {$fontObjectIds['F2']} 0 R >>";
            if ($imageObjectIds !== []) {
                $xObjects = [];
                foreach ($imageObjectIds as $name => $objectId) {
                    $xObjects[] = '/' . $name . ' ' . $objectId . ' 0 R';
                }
                $resources .= " /XObject << " . implode(' ', $xObjects) . " >>";
            }
            $resources .= " >>";

            $objects[$pageObjectId] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " . $this->formatNumber($this->pageWidth) . ' ' . $this->formatNumber($this->pageHeight) . "] /Resources " . $resources . " /Contents {$contentObjectId} 0 R >>";
        }

        ksort($objects);
        $buffer = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
        $offsets = [0];

        foreach ($objects as $objectId => $objectBody) {
            $offsets[$objectId] = strlen($buffer);
            $buffer .= $objectId . " 0 obj\n" . $objectBody . "\nendobj\n";
        }

        $xrefOffset = strlen($buffer);
        $buffer .= "xref\n0 " . (count($objects) + 1) . "\n";
        $buffer .= "0000000000 65535 f \n";
        for ($index = 1; $index <= count($objects); $index += 1) {
            $buffer .= sprintf("%010d 00000 n \n", $offsets[$index] ?? 0);
        }

        $buffer .= "trailer\n<< /Size " . (count($objects) + 1) . " /Root 1 0 R >>\nstartxref\n" . $xrefOffset . "\n%%EOF";

        return $buffer;
    }

    private function write(string $value): void
    {
        if ($this->currentPageIndex < 0) {
            $this->addPage();
        }
        $this->pages[$this->currentPageIndex] .= $value;
    }

    private function formatNumber(float $value): string
    {
        $formatted = number_format($value, 3, '.', '');
        return rtrim(rtrim($formatted, '0'), '.');
    }

    private function formatPoint(float $x, float $y): string
    {
        return $this->formatNumber($x) . ' ' . $this->formatNumber($y);
    }

    private function formatCurve(float $x1, float $y1, float $x2, float $y2, float $x3, float $y3): string
    {
        return implode(' ', [
            $this->formatNumber($x1),
            $this->formatNumber($y1),
            $this->formatNumber($x2),
            $this->formatNumber($y2),
            $this->formatNumber($x3),
            $this->formatNumber($y3),
            'c'
        ]);
    }

    private function formatColor(int $red, int $green, int $blue): string
    {
        return implode(' ', [
            $this->formatNumber(max(0, min(255, $red)) / 255),
            $this->formatNumber(max(0, min(255, $green)) / 255),
            $this->formatNumber(max(0, min(255, $blue)) / 255)
        ]);
    }

    private function escapePdfText(string $text): string
    {
        $converted = @iconv('UTF-8', 'Windows-1252//TRANSLIT//IGNORE', $text);
        if ($converted === false) {
            $converted = preg_replace('/[^\x20-\x7E]/', '', $text) ?? '';
        }
        return strtr($converted, [
            '\\' => '\\\\',
            '(' => '\(',
            ')' => '\)'
        ]);
    }

    private function breakWord(string $word, float $maxWidth, float $fontSize, array &$lines): string
    {
        $letters = preg_split('//u', $word, -1, PREG_SPLIT_NO_EMPTY) ?: [];
        $chunk = '';
        foreach ($letters as $letter) {
            $candidate = $chunk . $letter;
            if ($chunk !== '' && $this->measureText($candidate, $fontSize) > $maxWidth) {
                $lines[] = $chunk;
                $chunk = $letter;
            } else {
                $chunk = $candidate;
            }
        }
        return $chunk;
    }

    private function characterWidthFactor(string $char): float
    {
        if ($char === ' ') {
            return 0.28;
        }
        if (preg_match('/[.,;:!|]/u', $char) === 1) {
            return 0.26;
        }
        if (preg_match('/[\'"`’]/u', $char) === 1) {
            return 0.22;
        }
        if (preg_match('/[ilIjtf]/u', $char) === 1) {
            return 0.30;
        }
        if (preg_match('/[mwMW@%]/u', $char) === 1) {
            return 0.84;
        }
        if (preg_match('/[A-ZÀ-ÖØ-Þ]/u', $char) === 1) {
            return 0.66;
        }
        if (preg_match('/[0-9]/u', $char) === 1) {
            return 0.56;
        }
        if (preg_match('/[a-zà-öø-ÿ]/u', $char) === 1) {
            return 0.53;
        }
        return 0.55;
    }

    private function storeImageFromGd($image, string $name): ?string
    {
        $width = imagesx($image);
        $height = imagesy($image);
        if ($width < 1 || $height < 1) {
            return null;
        }

        $canvas = imagecreatetruecolor($width, $height);
        if ($canvas === false) {
            return null;
        }

        $white = imagecolorallocate($canvas, 255, 255, 255);
        imagefill($canvas, 0, 0, $white);
        imagealphablending($canvas, true);
        imagecopy($canvas, $image, 0, 0, 0, 0, $width, $height);

        ob_start();
        imagejpeg($canvas, null, 92);
        $jpegData = (string)ob_get_clean();

        if ($jpegData === '') {
            return null;
        }

        $this->images[$name] = [
            'data' => $jpegData,
            'width' => $width,
            'height' => $height
        ];
        return $name;
    }

    private function cropImageToOpaqueBounds($image, int $margin = 0)
    {
        $width = imagesx($image);
        $height = imagesy($image);
        $minX = $width;
        $minY = $height;
        $maxX = -1;
        $maxY = -1;

        for ($y = 0; $y < $height; $y += 1) {
            for ($x = 0; $x < $width; $x += 1) {
                $rgba = imagecolorat($image, $x, $y);
                $alpha = ($rgba >> 24) & 0x7F;
                if ($alpha < 120) {
                    if ($x < $minX) {
                        $minX = $x;
                    }
                    if ($y < $minY) {
                        $minY = $y;
                    }
                    if ($x > $maxX) {
                        $maxX = $x;
                    }
                    if ($y > $maxY) {
                        $maxY = $y;
                    }
                }
            }
        }

        if ($maxX < $minX || $maxY < $minY) {
            return null;
        }

        $cropX = max(0, $minX - $margin);
        $cropY = max(0, $minY - $margin);
        $cropWidth = min($width - $cropX, ($maxX - $minX + 1) + ($margin * 2));
        $cropHeight = min($height - $cropY, ($maxY - $minY + 1) + ($margin * 2));

        if ($cropWidth <= 0 || $cropHeight <= 0) {
            return null;
        }

        $cropped = imagecrop($image, [
            'x' => $cropX,
            'y' => $cropY,
            'width' => $cropWidth,
            'height' => $cropHeight
        ]);

        return $cropped !== false ? $cropped : null;
    }
}

function participant_report_pdf_normalize_text($value, int $maxLength = 4000): string
{
    $text = trim((string)$value);
    for ($index = 0; $index < 5; $index += 1) {
        $decoded = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
        if ($decoded === $text) {
            break;
        }
        $text = $decoded;
    }
    $text = preg_replace('/\R/u', "\n", $text) ?? '';
    $text = preg_replace('/[ \t]+/u', ' ', $text) ?? '';
    $text = preg_replace('/\n{3,}/u', "\n\n", $text) ?? '';
    $text = trim($text);
    if ($text === '') {
        return '';
    }
    return mb_substr($text, 0, $maxLength, 'UTF-8');
}

/**
 * @return array{
 *   quizTitle: string,
 *   participantName: string,
 *   code: string,
 *   summaryLines: array<int, string>,
 *   brandTitleImageDataUrl: string,
 *   sections: array<int, array{key: string, title: string, items: array<int, array{questionNumber: int, status: string, statusLabel: string, questionText: string, participantResponse: string, expectedResponse: string, explanation: string}>}>
 * }
 */
function participant_report_pdf_prepare_report(array $raw): array
{
    $sections = [];
    $rawSections = is_array($raw['sections'] ?? null) ? $raw['sections'] : [];
    foreach ($rawSections as $rawSection) {
        if (!is_array($rawSection)) {
            continue;
        }
        $items = [];
        $rawItems = is_array($rawSection['items'] ?? null) ? $rawSection['items'] : [];
        foreach ($rawItems as $rawItem) {
            if (!is_array($rawItem)) {
                continue;
            }
            $questionText = participant_report_pdf_normalize_text($rawItem['questionText'] ?? '', 8000);
            if ($questionText === '') {
                $questionText = '(question)';
            }
            $items[] = [
                'questionNumber' => max(1, (int)($rawItem['questionNumber'] ?? 1)),
                'status' => trim((string)($rawItem['status'] ?? 'not_graded')) ?: 'not_graded',
                'statusLabel' => participant_report_pdf_normalize_text($rawItem['statusLabel'] ?? 'Réponse enregistrée', 120),
                'questionText' => $questionText,
                'participantResponse' => participant_report_pdf_normalize_text($rawItem['participantResponse'] ?? 'Aucune', 4000) ?: 'Aucune',
                'expectedResponse' => participant_report_pdf_normalize_text($rawItem['expectedResponse'] ?? '', 4000),
                'explanation' => participant_report_pdf_normalize_text($rawItem['explanation'] ?? '', 2000)
            ];
        }

        if ($items === []) {
            continue;
        }

        $sections[] = [
            'key' => trim((string)($rawSection['key'] ?? 'section')) ?: 'section',
            'title' => participant_report_pdf_normalize_text($rawSection['title'] ?? 'Section', 160) ?: 'Section',
            'items' => $items
        ];
    }

    $summaryLines = [];
    $rawSummaryLines = is_array($raw['summaryLines'] ?? null) ? $raw['summaryLines'] : [];
    foreach ($rawSummaryLines as $summaryLine) {
        $normalized = participant_report_pdf_normalize_text($summaryLine, 240);
        if ($normalized !== '') {
            $summaryLines[] = $normalized;
        }
    }

    return [
        'quizTitle' => participant_report_pdf_normalize_text($raw['quizTitle'] ?? 'Questionnaire', 200) ?: 'Questionnaire',
        'participantName' => participant_report_pdf_normalize_text($raw['participantName'] ?? '', 120),
        'code' => participant_report_pdf_normalize_text($raw['code'] ?? '-', 80) ?: '-',
        'summaryLines' => $summaryLines,
        'brandTitleImageDataUrl' => trim((string)($raw['brandTitleImageDataUrl'] ?? '')),
        'sections' => $sections
    ];
}

function participant_report_pdf_slug(string $value): string
{
    $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $value);
    if ($ascii === false) {
        $ascii = $value;
    }
    $ascii = strtolower($ascii);
    $ascii = preg_replace('/[^a-z0-9]+/', '-', $ascii) ?? '';
    $ascii = trim($ascii, '-');
    return $ascii !== '' ? $ascii : 'rapport';
}

function participant_report_pdf_filename(array $report): string
{
    $quiz = participant_report_pdf_slug((string)($report['quizTitle'] ?? 'questionnaire'));
    $participant = participant_report_pdf_slug((string)($report['participantName'] ?? 'participant'));
    return sprintf('rapport-%s-%s.pdf', $quiz, $participant);
}

/**
 * @param array{key: string, title: string, items: array<int, array{questionNumber: int, status: string, statusLabel: string, questionText: string, participantResponse: string, expectedResponse: string, explanation: string}>} $section
 */
function participant_report_pdf_estimate_item_height(AudienceSimplePdf $pdf, array $item, float $contentWidth): float
{
    $innerWidth = $contentWidth - 28.0;
    $questionLines = $pdf->wrapText($item['questionText'], $innerWidth - 20.0, 11.2);
    $questionHeight = 12.0 + (count($questionLines) * 13.6) + 10.0;

    $metaBlocks = [
        'Votre réponse : ' . $item['participantResponse']
    ];
    if ($item['expectedResponse'] !== '') {
        $metaBlocks[] = 'Réponse attendue : ' . $item['expectedResponse'];
    }
    if ($item['explanation'] !== '') {
        $metaBlocks[] = $item['explanation'];
    }

    $metaHeight = 0.0;
    foreach ($metaBlocks as $block) {
        $blockLines = $pdf->wrapText($block, $innerWidth - 18.0, 10.4);
        $metaHeight += 10.0 + (count($blockLines) * 12.4) + 8.0;
    }
    if ($metaHeight > 0) {
        $metaHeight += (count($metaBlocks) - 1) * 6.0;
    }

    return 14.0 + 18.0 + 8.0 + $questionHeight + 8.0 + $metaHeight + 14.0;
}

/**
 * @param array{status: string, statusLabel: string, questionNumber: int, questionText: string, participantResponse: string, expectedResponse: string, explanation: string} $item
 */
function participant_report_pdf_draw_item(AudienceSimplePdf $pdf, array $item, float $x, float $y, float $width): float
{
    $status = $item['status'];
    $fill = [238, 245, 255];
    $border = [158, 197, 255];
    $badgeFill = [219, 234, 254];
    $badgeText = [29, 78, 216];

    if ($status === 'correct') {
        $fill = [236, 253, 243];
        $border = [125, 211, 167];
        $badgeFill = [220, 252, 231];
        $badgeText = [22, 101, 52];
    } elseif ($status === 'incorrect' || $status === 'unanswered') {
        $fill = [255, 242, 244];
        $border = [244, 169, 184];
        $badgeFill = [255, 228, 230];
        $badgeText = [159, 18, 57];
    }

    $height = participant_report_pdf_estimate_item_height($pdf, $item, $width);

    $pdf->setLineWidth(1.0);
    $pdf->setStrokeColor($border[0], $border[1], $border[2]);
    $pdf->setFillColor($fill[0], $fill[1], $fill[2]);
    $pdf->roundedRect($x, $y, $width, $height, 16.0, 'B');

    $cursorY = $y + 14.0;
    $pdf->setTextColor(15, 23, 42);
    $pdf->textLine($x + 14.0, $cursorY, 'Question ' . $item['questionNumber'], 11.2, 'F2');

    $badgeLabel = $item['statusLabel'] !== '' ? $item['statusLabel'] : 'Réponse enregistrée';
    $badgeWidth = min(160.0, $pdf->measureText($badgeLabel, 9.0) + 18.0);
    $badgeX = $x + $width - 14.0 - $badgeWidth;
    $pdf->setStrokeColor($badgeFill[0], $badgeFill[1], $badgeFill[2]);
    $pdf->setFillColor($badgeFill[0], $badgeFill[1], $badgeFill[2]);
    $pdf->roundedRect($badgeX, $cursorY - 2.0, $badgeWidth, 18.0, 9.0, 'B');
    $pdf->setTextColor($badgeText[0], $badgeText[1], $badgeText[2]);
    $pdf->textLine($badgeX + 9.0, $cursorY + 1.5, $badgeLabel, 9.0, 'F2');

    $cursorY += 26.0;

    $innerX = $x + 14.0;
    $innerWidth = $width - 28.0;

    $questionLines = $pdf->wrapText($item['questionText'], $innerWidth - 20.0, 11.2);
    $questionHeight = 12.0 + (count($questionLines) * 13.6) + 10.0;
    $pdf->setStrokeColor(226, 232, 240);
    $pdf->setFillColor(255, 255, 255);
    $pdf->roundedRect($innerX, $cursorY, $innerWidth, $questionHeight, 12.0, 'B');
    $lineY = $cursorY + 11.0;
    $pdf->setTextColor(31, 41, 55);
    foreach ($questionLines as $line) {
        if ($line === '') {
            $lineY += 13.6;
            continue;
        }
        $pdf->textLine($innerX + 10.0, $lineY, $line, 11.2, 'F1');
        $lineY += 13.6;
    }

    $cursorY += $questionHeight + 8.0;

    $metaBlocks = [
        'Votre réponse : ' . $item['participantResponse']
    ];
    if ($item['expectedResponse'] !== '') {
        $metaBlocks[] = 'Réponse attendue : ' . $item['expectedResponse'];
    }
    if ($item['explanation'] !== '') {
        $metaBlocks[] = $item['explanation'];
    }

    foreach ($metaBlocks as $block) {
        $blockLines = $pdf->wrapText($block, $innerWidth - 18.0, 10.4);
        $blockHeight = 10.0 + (count($blockLines) * 12.4) + 8.0;
        $pdf->setStrokeColor(226, 232, 240);
        $pdf->setFillColor(255, 255, 255);
        $pdf->roundedRect($innerX, $cursorY, $innerWidth, $blockHeight, 10.0, 'B');
        $blockY = $cursorY + 9.0;
        $pdf->setTextColor(71, 85, 105);
        foreach ($blockLines as $line) {
            if ($line === '') {
                $blockY += 12.4;
                continue;
            }
            $pdf->textLine($innerX + 9.0, $blockY, $line, 10.4, 'F1');
            $blockY += 12.4;
        }
        $cursorY += $blockHeight + 6.0;
    }

    return $height;
}

function participant_report_pdf_build(array $rawReport, string $logoPath): string
{
    $report = participant_report_pdf_prepare_report($rawReport);
    if ($report['sections'] === []) {
        throw new RuntimeException('Le rapport personnel ne contient aucune réponse à exporter.');
    }

    $pdf = new AudienceSimplePdf();
    $logoName = $pdf->registerLogoFromPng($logoPath);

    $pageWidth = $pdf->getPageWidth();
    $pageHeight = $pdf->getPageHeight();
    $marginX = 30.0;
    $topMargin = 26.0;
    $bottomMargin = 28.0;
    $contentWidth = $pageWidth - ($marginX * 2.0);
    $cursorY = $topMargin;

    $pdf->addPage();

    $brandTitleName = $report['brandTitleImageDataUrl'] !== ''
        ? $pdf->registerImageFromDataUrl($report['brandTitleImageDataUrl'], 'Im2')
        : null;
    $brandTitleInfo = $brandTitleName !== null ? $pdf->getImageInfo($brandTitleName) : null;
    $logoInfo = $logoName !== null ? $pdf->getImageInfo($logoName) : null;
    $summaryLines = $report['summaryLines'];
    $headerPaddingX = 24.0;
    $headerPaddingY = 18.0;
    $logoMaxWidth = 132.0;
    $logoMaxHeight = 108.0;
    $logoWidth = 108.0;
    $logoHeight = 108.0;
    if ($logoInfo !== null) {
        $rawLogoWidth = max(1, (float)$logoInfo['width']);
        $rawLogoHeight = max(1, (float)$logoInfo['height']);
        $logoScale = min($logoMaxWidth / $rawLogoWidth, $logoMaxHeight / $rawLogoHeight);
        $logoWidth = $rawLogoWidth * $logoScale;
        $logoHeight = $rawLogoHeight * $logoScale;
    }
    $leftColumnWidth = max(148.0, $logoWidth + 12.0);
    $columnGap = 28.0;
    $brandHeight = $brandTitleInfo !== null ? 34.0 : 20.0;
    $brandGap = -4.0;
    $leftBlockHeight = $logoHeight + $brandGap + $brandHeight;

    $metaParts = [];
    if ($report['participantName'] !== '') {
        $metaParts[] = $report['participantName'];
    }
    if ($report['code'] !== '') {
        $metaParts[] = 'Code ' . $report['code'];
    }

    $rightColumnWidth = $contentWidth - ($headerPaddingX * 2.0) - $leftColumnWidth - $columnGap;
    $titleLines = $pdf->wrapText($report['quizTitle'], $rightColumnWidth, 28.0);
    $titleBlockHeight = count($titleLines) * 31.0;
    $metaBlockHeight = $metaParts !== [] ? 20.0 : 0.0;
    $rightBlockHeight = $titleBlockHeight + ($metaBlockHeight > 0 ? 18.0 + $metaBlockHeight : 0.0);
    $headerHeight = max(156.0, max($leftBlockHeight, $rightBlockHeight) + ($headerPaddingY * 2.0));

    $pdf->setLineWidth(1.0);
    $pdf->setStrokeColor(217, 228, 242);
    $pdf->setFillColor(255, 255, 255);
    $pdf->roundedRect($marginX, $cursorY, $contentWidth, $headerHeight, 18.0, 'B');

    $leftColumnX = $marginX + $headerPaddingX;
    $leftBlockY = $cursorY + 12.0;
    $logoWrapX = $leftColumnX + (($leftColumnWidth - $logoWidth) / 2.0);
    $logoWrapY = $leftBlockY;
    if ($logoName !== null) {
        $pdf->drawImage($logoName, $logoWrapX, $logoWrapY, $logoWidth, $logoHeight);
    }

    $brandY = $logoWrapY + $logoHeight + $brandGap;
    if ($brandTitleInfo !== null && $brandTitleName !== null) {
        $brandWidth = min($leftColumnWidth, max(96.0, ($brandTitleInfo['width'] / max(1, $brandTitleInfo['height'])) * $brandHeight));
        $brandX = $leftColumnX + max(($leftColumnWidth - $brandWidth) / 2.0, 0.0);
        $pdf->drawImage($brandTitleName, $brandX, $brandY, $brandWidth, $brandHeight);
    } else {
        $pdf->setTextColor(99, 102, 241);
        $fallbackBrand = 'Audience';
        $brandTextWidth = $pdf->measureText($fallbackBrand, 20.0);
        $brandTextX = $leftColumnX + max(($leftColumnWidth - $brandTextWidth) / 2.0, 0.0);
        $pdf->textLine($brandTextX, $brandY + 2.0, $fallbackBrand, 20.0, 'F2');
    }

    $rightColumnX = $leftColumnX + $leftColumnWidth + $columnGap;
    $headerY = $cursorY + max(($headerHeight - $rightBlockHeight) / 2.0, $headerPaddingY);
    $pdf->setTextColor(15, 23, 42);
    foreach ($titleLines as $line) {
        $pdf->textLine($rightColumnX, $headerY, $line, 28.0, 'F2');
        $headerY += 31.0;
    }
    if ($metaParts !== []) {
        $pdf->setTextColor(71, 85, 105);
        $pdf->textLine($rightColumnX, $headerY + 6.0, implode('  •  ', $metaParts), 12.2, 'F1');
    }

    $cursorY += $headerHeight + 14.0;

    if ($summaryLines !== []) {
        $summaryHeight = 16.0 + (count($summaryLines) * 13.0) + 8.0;
        $pdf->setStrokeColor(217, 228, 242);
        $pdf->setFillColor(255, 255, 255);
        $pdf->roundedRect($marginX, $cursorY, $contentWidth, $summaryHeight, 18.0, 'B');
        $pdf->setTextColor(71, 85, 105);
        $summaryY = $cursorY + 14.0;
        foreach ($summaryLines as $line) {
            $pdf->textLine($marginX + 16.0, $summaryY, $line, 10.8, 'F1');
            $summaryY += 13.0;
        }
        $cursorY += $summaryHeight + 16.0;
    }

    foreach ($report['sections'] as $section) {
        $sectionColor = [79, 70, 229];
        if ($section['key'] === 'correct') {
            $sectionColor = [22, 101, 52];
        } elseif ($section['key'] === 'incorrect') {
            $sectionColor = [159, 18, 57];
        } elseif ($section['key'] === 'neutral') {
            $sectionColor = [29, 78, 216];
        }

        $minSectionHeight = 26.0;
        if ($cursorY + $minSectionHeight > $pageHeight - $bottomMargin) {
            $pdf->addPage();
            $cursorY = $topMargin;
        }

        $pdf->setTextColor($sectionColor[0], $sectionColor[1], $sectionColor[2]);
        $pdf->textLine($marginX, $cursorY, $section['title'], 12.8, 'F2');
        $cursorY += 30.0;

        foreach ($section['items'] as $item) {
            $itemHeight = participant_report_pdf_estimate_item_height($pdf, $item, $contentWidth);
            if ($cursorY + $itemHeight > $pageHeight - $bottomMargin) {
                $pdf->addPage();
                $cursorY = $topMargin;
            }
            $drawnHeight = participant_report_pdf_draw_item($pdf, $item, $marginX, $cursorY, $contentWidth);
            $cursorY += $drawnHeight + 10.0;
        }

        $cursorY += 6.0;
    }

    return $pdf->output();
}
