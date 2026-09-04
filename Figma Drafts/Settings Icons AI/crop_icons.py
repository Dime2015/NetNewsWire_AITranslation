from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "Source"
CROPPED = ROOT / "Cropped"
PREVIEW = ROOT / "Preview24"
CONTACT_SHEET = ROOT / "settings-icons-24pt-contact-sheet.png"

ACCEPTED = (
    "accounts-sync",
    "subscriptions",
    "article-list",
    "reader",
    "appearance",
    "notifications",
    "support-diagnostics",
)

CANVAS_SIZE = 256
VISUAL_BOX = 204
ALPHA_THRESHOLD = 3


def alpha_bbox(image: Image.Image):
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    return mask.getbbox()


def normalize_icon(name: str) -> None:
    source_path = SOURCE / f"{name}.png"
    image = Image.open(source_path).convert("RGBA")
    bbox = alpha_bbox(image)
    if bbox is None:
        raise RuntimeError(f"{name}: no non-transparent pixels")

    icon = image.crop(bbox)
    scale = min(VISUAL_BOX / icon.width, VISUAL_BOX / icon.height)
    size = (
        max(1, round(icon.width * scale)),
        max(1, round(icon.height * scale)),
    )
    icon = icon.resize(size, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    origin = ((CANVAS_SIZE - size[0]) // 2, (CANVAS_SIZE - size[1]) // 2)
    canvas.alpha_composite(icon, origin)

    output = CROPPED / f"{name}-256.png"
    preview = PREVIEW / f"{name}-24.png"
    canvas.save(output, optimize=True)
    canvas.resize((24, 24), Image.Resampling.LANCZOS).save(preview, optimize=True)

    print(
        f"{name}: source={image.size} bbox={bbox} "
        f"normalized={size} center=({CANVAS_SIZE / 2:.0f},{CANVAS_SIZE / 2:.0f})"
    )


def main() -> None:
    CROPPED.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    for name in ACCEPTED:
        normalize_icon(name)

    # Show the icons at their real 24 pt size, while enlarging the finished
    # sheet for inspection without changing the icon rasterization itself.
    cell_size = 56
    sheet = Image.new("RGB", (cell_size * len(ACCEPTED), cell_size), "#F7F4F1")
    for index, name in enumerate(ACCEPTED):
        icon = Image.open(PREVIEW / f"{name}-24.png").convert("RGBA")
        sheet.paste(icon, (index * cell_size + 16, 16), icon)
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST).save(
        CONTACT_SHEET,
        optimize=True,
    )


if __name__ == "__main__":
    main()
