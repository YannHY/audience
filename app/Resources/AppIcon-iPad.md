# Icône Audience pour iPad

Les fichiers livrés sont `iPad.xcassets/AppIcon.appiconset/AppIcon.png` et `iPad.xcassets/AppIcon.appiconset/AppIcon-Dark.png`, en 1024 × 1024 pixels. Le cadre arrondi et son ombre intégrés dans l’ancienne illustration sont supprimés ; iPadOS applique sa propre découpe. La variante sombre est déclarée avec l’apparence `luminosity: dark` du catalogue Apple. L’apparence des icônes reste pilotée par le réglage de l’écran d’accueil (Automatique ou Sombre).

Images éditées avec l’outil intégré imagegen, puis redimensionnées avec sips. Le dessin de l’orateur, du microphone et du pupitre est conservé. La version Mac conserve son icône existante.

## Prompt de l’icône claire

Edit target: the supplied Audience iPad app icon. This is a precise packaging correction, NOT a logo redesign. Preserve the existing indigo line illustration of the person in profile speaking into a microphone at a lectern, with the same drawing style and recognizable features.
Remove the inset rounded-square tile completely: remove its outline, raised edges, bevel, drop shadow and surrounding white margins. The icon must be ONE full-bleed square image with a uniform near-white very pale lavender background all the way to its four edges. NO rounded corners baked into the image; the operating system will supply the only corner mask. Reframe the existing illustration to use the available square naturally, keeping the head and microphone fully visible and letting the lectern drawing continue to the bottom edge. Keep the illustration indigo purple, clean and sharp. Do not add any text, symbol, border, frame, tile, gloss or decoration. Do not replace the person with another logo. Output one square 1024x1024 production asset only.

## Prompt de l’icône sombre

Edit target: the supplied frameless Audience app icon. Make its DARK APPEARANCE variant. Preserve exactly the composition, silhouette, linework, person, microphone, lectern, scale and positions. Change ONLY the palette: replace the entire pale background (including all spaces inside the line drawing) with uniform deep charcoal #17171E; recolor all indigo strokes and filled areas to luminous soft lavender #A99AFF for clear contrast at small sizes. Keep line edges clean. Absolutely no border, no inset tile, no rounded corners, no shadow, no bevel, no gradient, no texture, no text, no extra symbols. One full-bleed square production image only. This is the same logo with a dark palette, not a redesign.

Référence : [catalogue d’icônes Apple](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

