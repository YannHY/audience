# Icône Audience

`AppIcon.icon` est l’icône commune aux apps Mac et iPad. C’est un document Icon Composer (Liquid Glass) que Xcode compile avec `actool` dans `Assets.car`. Pour macOS, `actool` produit aussi un `AppIcon.icns` de repli. Les deux cibles l’utilisent par le réglage `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (voir `scripts/generate-project.py`). Elle remplace l’ancien `AppIcon.icns` (Mac) et l’ancien `AppIcon.appiconset` (iPad).

## Composition

Un orateur se tient derrière un pupitre muni d’un micro court, sur une estrade ronde éclairée par un faisceau de projecteur, face à deux rangs de spectateurs vus de dos. Le premier rang passe légèrement devant l’estrade. Le fond est un dégradé indigo.

Les quatre groupes, de l’avant vers l’arrière :

1. le public (`rang2`, `rang1`), opaque ;
2. le micro, le pupitre et l’orateur ;
3. l’ombre de contact, la flaque de lumière, le dessus et la face de l’estrade ;
4. le faisceau du projecteur, sans effet de verre.

`actool` refuse plus de quatre groupes. En apparence sombre, le fond devient anthracite, l’orateur et la lumière prennent une teinte ambrée. Les apparences teintée et transparente sont calculées par le système.

## Modifier l’icône

Chaque couche est un masque PNG blanc de 1024 × 1024 pixels, colorié par `icon.json`. Deux façons de la modifier :

- dans Icon Composer, pour les couleurs, l’opacité, les reflets et les ombres ;
- dans `scripts/generate-icon.py`, pour la géométrie ; le script régénère tout le dossier (`python3 scripts/generate-icon.py`, Pillow requis).

Aperçu sans Xcode :

```sh
ictool Resources/AppIcon.icon --export-image --output-file apercu.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Les rendus `Dark`, `TintedDark` et `ClearLight` s’obtiennent en changeant `--rendition`.
