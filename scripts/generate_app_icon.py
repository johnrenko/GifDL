#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
MASTER_SIZE = 1024

OUTPUTS = {
    "ipad-notification-20@1x.png": 20,
    "ipad-notification-20@2x.png": 40,
    "ipad-settings-29@1x.png": 29,
    "ipad-settings-29@2x.png": 58,
    "ipad-spotlight-40@1x.png": 40,
    "ipad-spotlight-40@2x.png": 80,
    "ipad-app-76@1x.png": 76,
    "ipad-app-76@2x.png": 152,
    "ipad-pro-app-83.5@2x.png": 167,
    "iphone-notification-20@2x.png": 40,
    "iphone-notification-20@3x.png": 60,
    "iphone-settings-29@2x.png": 58,
    "iphone-settings-29@3x.png": 87,
    "iphone-spotlight-40@2x.png": 80,
    "iphone-spotlight-40@3x.png": 120,
    "iphone-app-60@2x.png": 120,
    "iphone-app-60@3x.png": 180,
    "ios-marketing-1024.png": 1024,
}


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def gradient_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    top_left = (255, 149, 103)
    bottom_right = (255, 84, 70)
    accent = (255, 210, 125)

    for y in range(size):
        for x in range(size):
            tx = x / (size - 1)
            ty = y / (size - 1)
            diag = (tx + ty) / 2
            warm_bias = max(0.0, 1.0 - ((tx - 0.2) ** 2 + (ty - 0.18) ** 2) * 3.2)
            r = lerp(top_left[0], bottom_right[0], diag)
            g = lerp(top_left[1], bottom_right[1], diag)
            b = lerp(top_left[2], bottom_right[2], diag)
            r = lerp(r, accent[0], warm_bias * 0.35)
            g = lerp(g, accent[1], warm_bias * 0.35)
            b = lerp(b, accent[2], warm_bias * 0.35)
            pixels[x, y] = (r, g, b, 255)

    return image


def add_glow(base: Image.Image, box: tuple[int, int, int, int], radius: int, color: tuple[int, int, int, int], blur: int) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer)


def draw_icon() -> Image.Image:
    base = gradient_background(MASTER_SIZE)
    draw = ImageDraw.Draw(base)

    add_glow(base, (180, 148, 890, 908), 190, (72, 23, 22, 96), 48)
    add_glow(base, (64, 48, 528, 500), 180, (255, 245, 214, 84), 82)

    rear_card = Image.new("RGBA", base.size, (0, 0, 0, 0))
    rear_draw = ImageDraw.Draw(rear_card)
    rear_draw.rounded_rectangle((226, 188, 726, 688), radius=126, fill=(255, 247, 229, 105))
    rear_card = rear_card.rotate(-8, resample=Image.Resampling.BICUBIC, center=(476, 438))
    rear_card = rear_card.filter(ImageFilter.GaussianBlur(1))
    base.alpha_composite(rear_card)

    panel_box = (190, 170, 834, 814)
    panel_radius = 176
    panel = Image.new("RGBA", base.size, (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle(panel_box, radius=panel_radius, fill=(33, 40, 67, 255))

    panel_highlight = Image.new("RGBA", base.size, (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(panel_highlight)
    highlight_draw.rounded_rectangle((190, 170, 834, 520), radius=176, fill=(255, 255, 255, 28))
    highlight_draw.ellipse((248, 184, 600, 450), fill=(255, 255, 255, 24))
    panel.alpha_composite(panel_highlight)
    base.alpha_composite(panel)

    # Media play marker.
    draw.rounded_rectangle((270, 280, 430, 440), radius=42, fill=(255, 236, 198, 230))
    draw.polygon([(328, 315), (328, 405), (402, 360)], fill=(255, 117, 78, 255))

    # Download tray.
    tray_color = (255, 236, 198, 255)
    tray_outline = (255, 187, 117, 255)
    draw.rounded_rectangle((408, 594, 676, 662), radius=34, fill=tray_color)
    draw.rounded_rectangle((426, 556, 658, 618), radius=28, fill=(33, 40, 67, 255))
    draw.rounded_rectangle((434, 604, 650, 644), radius=20, fill=tray_outline)

    # Download arrow.
    arrow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    arrow_draw = ImageDraw.Draw(arrow)
    arrow_draw.rounded_rectangle((500, 298, 588, 564), radius=40, fill=tray_color)
    arrow_draw.polygon([(444, 500), (644, 500), (544, 640)], fill=tray_color)
    arrow = arrow.filter(ImageFilter.GaussianBlur(0.3))
    base.alpha_composite(arrow)

    # Subtle badge spark for energy.
    spark = Image.new("RGBA", base.size, (0, 0, 0, 0))
    spark_draw = ImageDraw.Draw(spark)
    spark_draw.polygon([(710, 266), (736, 324), (794, 350), (736, 376), (710, 434), (684, 376), (626, 350), (684, 324)], fill=(255, 214, 115, 235))
    spark = spark.filter(ImageFilter.GaussianBlur(1))
    base.alpha_composite(spark)

    return base


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = draw_icon()
    for filename, size in OUTPUTS.items():
        image = master if size == MASTER_SIZE else master.resize((size, size), Image.Resampling.LANCZOS)
        image.save(ICONSET / filename)


if __name__ == "__main__":
    main()
