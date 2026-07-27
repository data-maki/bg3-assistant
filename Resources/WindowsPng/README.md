# Windows WPF image derivatives

WPF's Windows Imaging Component path in the Windows 11 ARM64 QA image could
not decode the source WebP build/item artwork. These PNGs are lossless
derivatives of the sibling authoritative sources:

- `../BuildOptionIcons/*.webp` -> `BuildOptionIcons/*.png`
- `../ItemIcons/*.webp` -> `ItemIcons/*.png`

The source files remain unchanged. Windows packaging links these files back to
the runtime paths `Resources/BuildOptionIcons` and `Resources/ItemIcons`.

Inventory:

- 695 non-empty build-option sources -> 695 PNGs
- 51 item sources -> 51 PNGs
- `../BuildOptionIcons/friends.webp` is zero bytes, so it has no derivative and
  is treated as optional missing artwork

The signed ARM64 package is validated to contain these 746 PNGs and no WebP
payloads.
