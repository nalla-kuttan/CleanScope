# CleanScope Brandkit

## Identity

CleanScope helps people understand what occupies their Mac before they decide what to remove. The **Sprout Lens** combines a magnifying lens for clarity with a two-leaf sprout for useful room reclaimed. The product promise is: **Make room for what’s next.**

Use the mark alone for the app icon and compact controls. Use the mark with `CleanScope` in navigation and product chrome. Reserve the full lockup for documentation, About surfaces, and release artwork.

## Assets

- `Assets/Brand/CleanScopeMark.svg`: primary vector mark.
- `Assets/Brand/CleanScopeWordmark.svg`: wordmark.
- `Assets/Brand/CleanScopeLockup.svg`: mark, wordmark, and tagline.
- `Assets/Brand/AppIcon-1024.png`: master raster app icon.
- `Assets/Brand/CleanScope.icns`: production macOS app icon.
- `Assets/Brand/CleanScope.iconset/`: standard macOS icon sizes.

Regenerate raster assets with:

```bash
swift script/generate_brand_assets.swift
```

## Clear Space And Size

Keep clear space around the mark equal to the height of one leaf. Do not place text, borders, or other symbols inside this area. The mark may be used down to 16 px. At small sizes, use the mark without a field, wordmark, or tagline.

## Color

The product UI uses the **Greenhouse** palette; the full token table and contrast contract live in `DESIGN.md`.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| Accent | `#526D56` | `#4D814D` | Primary actions and active state |
| Safe | `#3D6B4A` | `#5DA96A` | Safe state and positive progress |
| Review | `#816025` | `#E0B05A` | Review recommended |
| Destructive | `#A54C3F` | `#E8836F` | Destructive confirmation and failures |
| Info | `#4B698A` | `#7DA4CC` | Information and permissions |
| Text | `#2C2420` | `#F2EDE8` | Primary text |
| Surface | `#FAF7F2` | `#1A1816` | Main surface |

The Sprout Lens mark keeps its own colors in every context so it matches the app icon:

| Mark | Light | Dark |
| --- | --- | --- |
| Lens | `#176F5D` | `#63C6A7` |
| Leaf | `#50B77A` | `#71D198` |
| Field | `#DFF2E8` | `#173C33` |

Color never replaces a safety icon and text label.

## Typography

Use the system SF Pro family. Product headlines use SF Pro Display Bold. Body, table, permission, and safety copy use standard SF Pro Text. Data values may use the rounded system design with tabular digits. Letter spacing is always zero.

## Voice

Be calm, useful, and specific. Prefer “Your Mac has room to grow,” “Moved safely to Trash,” and “Three items deserve a closer look.” Avoid urgency, shame, or claims that unknown files are junk.

## Motion

Use 200 ms ease-out transitions. Growth may progress through three finite stages while scanning. Cleanup completion may settle once. Respect Reduce Motion with immediate changes or crossfades. Never use confetti, bounce, points, streaks, or ambient looping animation.

## Safety Usage

The identity may support optimistic cleanup language, but it must never imply that removal is automatic or risk-free. Destructive actions always name Trash, show selected totals, and preserve category, confidence, and risk explanations.

## Misuse

Do not rotate, stretch, outline, recolor, add gradients, add facial features, or separate the sprout from the lens. Do not place the mark on a low-contrast field. Do not use the full lockup below 180 px wide.
