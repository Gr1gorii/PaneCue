#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


PROJECT_DIR = Path(__file__).resolve().parent.parent
RESOURCES_DIR = PROJECT_DIR / "Resources"
SOURCE_PATH = RESOURCES_DIR / "AppIcon.png"
DEFAULT_ICON_PATH = RESOURCES_DIR / "AppIcon-Default.png"
DARK_ICON_PATH = RESOURCES_DIR / "AppIcon-Dark.png"
CLEAR_LIGHT_ICON_PATH = RESOURCES_DIR / "AppIcon-Clear-Light.png"
CLEAR_DARK_ICON_PATH = RESOURCES_DIR / "AppIcon-Clear-Dark.png"
TINTED_LIGHT_ICON_PATH = RESOURCES_DIR / "AppIcon-Tinted-Light.png"
TINTED_DARK_ICON_PATH = RESOURCES_DIR / "AppIcon-Tinted-Dark.png"
STYLE_PREVIEW_PATH = RESOURCES_DIR / "PaneCue-Icon-Styles-Preview.png"
TINT_PREVIEW_PATH = RESOURCES_DIR / "PaneCue-Tint-Colors-Preview.png"
MARK_PATH = RESOURCES_DIR / "PaneCue-Mark-Transparent.png"
PREVIEW_PATH = RESOURCES_DIR / "PaneCue-Mark-Transparency-Preview.png"
STATUS_PATH = RESOURCES_DIR / "PaneCueStatusTemplate.png"
ICONSET_DIR = RESOURCES_DIR / "AppIcon.iconset"

TINT_PALETTES = {
    "Red": {
        "dark_background": ((78, 28, 46), (52, 16, 31)),
        "dark_mark": ((255, 91, 116), (185, 45, 73)),
        "dark_edge": (190, 120, 135),
        "light_background": ((255, 223, 229), (244, 168, 184)),
        "light_mark": ((223, 44, 76), (154, 20, 47)),
    },
    "Orange": {
        "dark_background": ((82, 45, 21), (55, 27, 12)),
        "dark_mark": ((255, 158, 72), (198, 86, 31)),
        "dark_edge": (196, 139, 101),
        "light_background": ((255, 232, 210), (247, 186, 127)),
        "light_mark": ((225, 100, 30), (163, 59, 12)),
    },
    "Yellow": {
        "dark_background": ((78, 64, 21), (52, 40, 11)),
        "dark_mark": ((255, 214, 76), (190, 139, 29)),
        "dark_edge": (190, 174, 111),
        "light_background": ((255, 244, 195), (238, 210, 112)),
        "light_mark": ((176, 125, 4), (122, 82, 0)),
    },
    "Green": {
        "dark_background": ((24, 67, 45), (13, 45, 29)),
        "dark_mark": ((88, 216, 132), (36, 153, 80)),
        "dark_edge": (120, 181, 143),
        "light_background": ((215, 246, 227), (151, 220, 177)),
        "light_mark": ((35, 151, 76), (13, 105, 48)),
    },
    "Blue": {
        "dark_background": ((22, 44, 95), (14, 27, 80)),
        "dark_mark": ((74, 151, 245), (42, 91, 163)),
        "dark_edge": (130, 150, 190),
        "light_background": ((219, 239, 255), (154, 207, 255)),
        "light_mark": ((20, 104, 218), (0, 66, 165)),
    },
    "Purple": {
        "dark_background": ((59, 33, 91), (40, 19, 67)),
        "dark_mark": ((174, 105, 244), (108, 57, 180)),
        "dark_edge": (163, 129, 194),
        "light_background": ((237, 220, 255), (195, 161, 238)),
        "light_mark": ((128, 64, 200), (77, 35, 139)),
    },
    "Pink": {
        "dark_background": ((82, 28, 66), (56, 16, 44)),
        "dark_mark": ((255, 94, 190), (190, 45, 130)),
        "dark_edge": (194, 117, 164),
        "light_background": ((255, 219, 242), (243, 159, 210)),
        "light_mark": ((218, 45, 142), (150, 20, 93)),
    },
    "Graphite": {
        "dark_background": ((58, 62, 70), (35, 38, 45)),
        "dark_mark": ((190, 197, 210), (118, 127, 144)),
        "dark_edge": (166, 172, 184),
        "light_background": ((232, 235, 241), (176, 184, 198)),
        "light_mark": ((83, 93, 111), (45, 52, 64)),
    },
}


def foreground_alpha(pixel: tuple[int, int, int, int]) -> int:
    red, green, blue, source_alpha = pixel
    if source_alpha == 0:
        return 0

    white = max(min(red, green, blue) - 205, 0) / 50
    lime = min(
        max((red - 135) / 75, 0),
        max((green - 175) / 70, 0),
        max((125 - blue) / 125, 0),
    )
    strength = min(max(white, lime), 1)
    return round(source_alpha * strength)


def fitted_image(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    size: int,
    padding: int,
) -> Image.Image:
    cropped = image.crop(bounds)
    available = size - padding * 2
    scale = min(available / cropped.width, available / cropped.height)
    resized = cropped.resize(
        (
            round(cropped.width * scale),
            round(cropped.height * scale),
        ),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        (
            (size - resized.width) // 2,
            (size - resized.height) // 2,
        ),
    )
    return canvas


def centered_square(image: Image.Image, size: int) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("No foreground mark was detected")

    cropped = image.crop(bounds)
    padding = round(max(cropped.size) * 0.12)
    side = max(cropped.size) + padding * 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(
        cropped,
        (
            (side - cropped.width) // 2,
            (side - cropped.height) // 2,
        ),
    )
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def dark_icon(image: Image.Image) -> Image.Image:
    result = image.copy()
    pixels = result.load()

    for y in range(result.height):
        vertical = y / max(result.height - 1, 1)
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue

            blue_separation = blue - max(red, green)
            if blue > 105 and blue_separation > 35:
                tone = round(
                    58 * (1 - vertical)
                    + 14 * vertical
                )
                pixels[x, y] = (tone, tone, tone, alpha)

    return add_inner_edge(
        result,
        result.getchannel("A"),
        color=(255, 255, 255),
        top_opacity=0.16,
        bottom_opacity=0.025,
        width=25,
    )


def solid_layer(
    mask: Image.Image,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    opacity: float = 1,
) -> Image.Image:
    result = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    pixels = result.load()
    mask_pixels = mask.load()

    for y in range(result.height):
        progress = y / max(result.height - 1, 1)
        color = tuple(
            round(top[index] * (1 - progress) + bottom[index] * progress)
            for index in range(3)
        )
        for x in range(result.width):
            alpha = round(mask_pixels[x, y] * opacity)
            if alpha:
                pixels[x, y] = (*color, alpha)
    return result


def colored_mark(
    mark: Image.Image,
    color: tuple[int, int, int],
) -> Image.Image:
    result = Image.new("RGBA", mark.size, (*color, 0))
    alpha = mark if mark.mode == "L" else mark.getchannel("A")
    result.putalpha(alpha)
    return result


def add_inner_edge(
    image: Image.Image,
    mask: Image.Image,
    color: tuple[int, int, int],
    top_opacity: float,
    bottom_opacity: float,
    width: int,
) -> Image.Image:
    result = image.copy()
    eroded = mask.filter(ImageFilter.MinFilter(width))
    ring_mask = ImageChops.subtract(mask, eroded)
    ring = colored_mark(ring_mask, color)
    alpha = ring.getchannel("A")
    alpha_pixels = alpha.load()

    for y in range(alpha.height):
        progress = y / max(alpha.height - 1, 1)
        opacity = (
            top_opacity * (1 - progress)
            + bottom_opacity * progress
        )
        for x in range(alpha.width):
            if alpha_pixels[x, y]:
                alpha_pixels[x, y] = round(
                    alpha_pixels[x, y] * opacity
                )

    ring.putalpha(alpha)
    result.alpha_composite(ring)
    return result


def clear_icon(
    enclosure_mask: Image.Image,
    mark: Image.Image,
    dark: bool,
) -> Image.Image:
    canvas = Image.new("RGBA", enclosure_mask.size, (0, 0, 0, 0))

    if dark:
        glass = solid_layer(
            enclosure_mask,
            (46, 55, 90),
            (12, 24, 69),
            opacity=0.75,
        )
        outline_color = (105, 113, 141)
        outline_opacity = 0.14
        stroke_color = (3, 10, 36)
        mark_color = (249, 249, 251)
        mark_opacity = 0.93
    else:
        glass = solid_layer(
            enclosure_mask,
            (239, 243, 250),
            (169, 183, 207),
            opacity=0.7,
        )
        outline_color = (255, 255, 255)
        outline_opacity = 0.24
        stroke_color = (255, 255, 255)
        mark_color = (32, 37, 47)
        mark_opacity = 0.9

    canvas.alpha_composite(glass)

    eroded = enclosure_mask.filter(ImageFilter.MinFilter(21))
    outline_mask = ImageChops.subtract(enclosure_mask, eroded)
    outline = colored_mark(outline_mask, outline_color)
    outline.putalpha(
        outline.getchannel("A").point(
            lambda value: round(value * outline_opacity)
        )
    )
    canvas.alpha_composite(outline)

    mark_alpha = mark.getchannel("A")
    expanded = mark_alpha.filter(ImageFilter.MaxFilter(21))
    stroke_mask = ImageChops.subtract(expanded, mark_alpha)
    stroke = colored_mark(stroke_mask, stroke_color)
    stroke.putalpha(
        stroke.getchannel("A").point(
            lambda value: round(value * (0.34 if dark else 0.24))
        )
    )
    canvas.alpha_composite(stroke)

    shadow_alpha = mark_alpha.filter(ImageFilter.GaussianBlur(18))
    shadow = colored_mark(shadow_alpha, (0, 9, 34))
    shadow.putalpha(
        shadow.getchannel("A").point(
            lambda value: round(value * (0.24 if dark else 0.14))
        )
    )
    offset_shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    offset_shadow.alpha_composite(shadow, (0, 12))
    canvas.alpha_composite(offset_shadow)

    translucent_mark = colored_mark(mark_alpha, mark_color)
    translucent_mark.putalpha(
        mark_alpha.point(
            lambda value: round(value * mark_opacity)
        )
    )
    canvas.alpha_composite(translucent_mark)
    return canvas


def tinted_icon(
    enclosure_mask: Image.Image,
    mark: Image.Image,
    dark: bool,
    palette: dict[str, object],
) -> Image.Image:
    if dark:
        background_top, background_bottom = palette["dark_background"]
        mark_top, mark_bottom = palette["dark_mark"]
        background = solid_layer(
            enclosure_mask,
            background_top,
            background_bottom,
        )
        mark_layer = solid_layer(
            mark.getchannel("A"),
            mark_top,
            mark_bottom,
        )
        edge_color = palette["dark_edge"]
    else:
        background_top, background_bottom = palette["light_background"]
        mark_top, mark_bottom = palette["light_mark"]
        background = solid_layer(
            enclosure_mask,
            background_top,
            background_bottom,
        )
        mark_layer = solid_layer(
            mark.getchannel("A"),
            mark_top,
            mark_bottom,
        )
        edge_color = (255, 255, 255)

    background.alpha_composite(mark_layer)
    return add_inner_edge(
        background,
        enclosure_mask,
        color=edge_color,
        top_opacity=0.07 if dark else 0.18,
        bottom_opacity=0.015 if dark else 0.04,
        width=25,
    )


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    paths = (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    )
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def style_preview(
    variants: list[tuple[str, Image.Image, tuple[int, int, int]]],
) -> Image.Image:
    width = 1380
    height = 940
    preview = Image.new("RGBA", (width, height), (25, 27, 35, 255))
    draw = ImageDraw.Draw(preview)
    title_font = font(44)
    label_font = font(28)
    draw.text((52, 34), "PaneCue · macOS icon appearances", fill="white", font=title_font)

    tile_width = 410
    tile_height = 380
    icon_size = 282
    x_positions = (45, 485, 925)
    y_positions = (115, 515)

    for index, (label, icon, backdrop) in enumerate(variants):
        x = x_positions[index % 3]
        y = y_positions[index // 3]
        draw.rounded_rectangle(
            (x, y, x + tile_width, y + tile_height),
            radius=34,
            fill=(*backdrop, 255),
            outline=(255, 255, 255, 32),
            width=2,
        )
        resized = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        preview.alpha_composite(
            resized,
            (
                x + (tile_width - icon_size) // 2,
                y + 25,
            ),
        )
        text_box = draw.textbbox((0, 0), label, font=label_font)
        text_width = text_box[2] - text_box[0]
        backdrop_brightness = sum(backdrop) / 3
        label_color = (
            (36, 42, 55, 255)
            if backdrop_brightness > 185
            else (238, 240, 247, 255)
        )
        draw.text(
            (x + (tile_width - text_width) // 2, y + 320),
            label,
            fill=label_color,
            font=label_font,
        )
    return preview


def tint_preview(variants: list[tuple[str, Image.Image]]) -> Image.Image:
    width = 1500
    height = 890
    preview = Image.new("RGBA", (width, height), (25, 27, 35, 255))
    draw = ImageDraw.Draw(preview)
    title_font = font(44)
    label_font = font(27)
    draw.text(
        (52, 34),
        "PaneCue · macOS tinted colors",
        fill="white",
        font=title_font,
    )

    tile_width = 330
    tile_height = 350
    icon_size = 252
    x_positions = (48, 408, 768, 1128)
    y_positions = (120, 500)

    for index, (label, icon) in enumerate(variants):
        x = x_positions[index % 4]
        y = y_positions[index // 4]
        draw.rounded_rectangle(
            (x, y, x + tile_width, y + tile_height),
            radius=32,
            fill=(17, 19, 27, 255),
            outline=(255, 255, 255, 31),
            width=2,
        )
        resized = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        preview.alpha_composite(
            resized,
            (
                x + (tile_width - icon_size) // 2,
                y + 20,
            ),
        )
        text_box = draw.textbbox((0, 0), label, font=label_font)
        text_width = text_box[2] - text_box[0]
        draw.text(
            (x + (tile_width - text_width) // 2, y + 292),
            label,
            fill=(238, 240, 247, 255),
            font=label_font,
        )
    return preview


def save_iconset(icon: Image.Image) -> None:
    ICONSET_DIR.mkdir(exist_ok=True)
    specifications = (
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    )
    for name, size in specifications:
        icon.resize((size, size), Image.Resampling.LANCZOS).save(
            ICONSET_DIR / name
        )


def checkerboard(size: int, cell: int = 48) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    colors = ((224, 226, 231, 255), (178, 182, 190, 255))
    for y in range(size):
        for x in range(size):
            pixels[x, y] = colors[((x // cell) + (y // cell)) % 2]
    return image


def main() -> None:
    source = Image.open(SOURCE_PATH).convert("RGBA")
    mark = source.copy()
    alpha = Image.new("L", source.size)
    alpha.putdata([foreground_alpha(pixel) for pixel in source.getdata()])
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=0.45))
    mark.putalpha(alpha)

    source_bounds = source.getchannel("A").getbbox()
    if source_bounds is None:
        raise RuntimeError("The app icon has no visible artwork")

    default_icon = fitted_image(source, source_bounds, 1024, padding=104)
    fitted_mark = fitted_image(mark, source_bounds, 1024, padding=104)
    enclosure_mask = default_icon.getchannel("A")

    default_icon.save(DEFAULT_ICON_PATH)
    dark = dark_icon(default_icon)
    dark.save(DARK_ICON_PATH)
    clear_light = clear_icon(enclosure_mask, fitted_mark, dark=False)
    clear_light.save(CLEAR_LIGHT_ICON_PATH)
    clear_dark = clear_icon(enclosure_mask, fitted_mark, dark=True)
    clear_dark.save(CLEAR_DARK_ICON_PATH)
    tinted_icons: dict[str, tuple[Image.Image, Image.Image]] = {}
    for name, palette in TINT_PALETTES.items():
        light = tinted_icon(
            enclosure_mask,
            fitted_mark,
            dark=False,
            palette=palette,
        )
        dark_tint = tinted_icon(
            enclosure_mask,
            fitted_mark,
            dark=True,
            palette=palette,
        )
        light.save(RESOURCES_DIR / f"AppIcon-Tinted-{name}-Light.png")
        dark_tint.save(RESOURCES_DIR / f"AppIcon-Tinted-{name}-Dark.png")
        tinted_icons[name] = (light, dark_tint)

    tinted_light, tinted_dark = tinted_icons["Blue"]
    tinted_light.save(TINTED_LIGHT_ICON_PATH)
    tinted_dark.save(TINTED_DARK_ICON_PATH)

    style_preview(
        [
            ("Default", default_icon, (47, 51, 65)),
            ("Dark", dark, (18, 20, 28)),
            ("Clear · Light", clear_light, (167, 203, 239)),
            ("Clear · Dark", clear_dark, (24, 37, 60)),
            ("Tinted · Light", tinted_light, (232, 237, 244)),
            ("Tinted · Dark", tinted_dark, (22, 25, 34)),
        ]
    ).save(STYLE_PREVIEW_PATH)
    tint_preview(
        [
            (name, tinted_icons[name][1])
            for name in TINT_PALETTES
        ]
    ).save(TINT_PREVIEW_PATH)
    save_iconset(default_icon)

    production_mark = centered_square(mark, 1024)
    production_mark.save(MARK_PATH)

    preview = checkerboard(1024)
    preview.alpha_composite(production_mark)
    preview.save(PREVIEW_PATH)

    status_mark = production_mark.resize(
        (28, 28),
        Image.Resampling.LANCZOS,
    )
    status = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    black = Image.new("RGBA", status_mark.size, (0, 0, 0, 255))
    black.putalpha(status_mark.getchannel("A"))
    status.alpha_composite(black, (4, 4))
    status.save(STATUS_PATH)

    print(MARK_PATH)
    print(PREVIEW_PATH)
    print(STATUS_PATH)
    print(STYLE_PREVIEW_PATH)
    print(TINT_PREVIEW_PATH)


if __name__ == "__main__":
    main()
