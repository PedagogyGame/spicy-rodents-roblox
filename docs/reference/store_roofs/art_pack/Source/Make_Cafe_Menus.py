"""Regenerate the exact blank-price café menus. Python 3 + Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random

ROOT = Path(__file__).resolve().parents[1] / 'Textures' / 'Shop'
ROOT.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
HEADER = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'
W, H = 768, 1024

def menu(filename, title, items, seed):
    rng = random.Random(seed)
    im = Image.new('RGB', (W, H), (27, 35, 34))
    d = ImageDraw.Draw(im)
    # Sparse chalk dust and an imperfect, scuffed double-line border.
    for _ in range(9000):
        x, y = rng.randrange(W), rng.randrange(H)
        v = rng.randrange(25, 44)
        d.point((x, y), fill=(v, v+5, v+3))
    for inset in (22, 32):
        for x in range(inset, W-inset, 9):
            d.line((x, inset+rng.randrange(-1, 2), x+7, inset), fill=(182, 187, 168), width=2)
            d.line((x, H-inset, x+7, H-inset+rng.randrange(-1, 2)), fill=(182, 187, 168), width=2)
        for y in range(inset, H-inset, 10):
            d.line((inset, y, inset+rng.randrange(-1, 2), y+8), fill=(182, 187, 168), width=2)
            d.line((W-inset, y, W-inset+rng.randrange(-1, 2), y+8), fill=(182, 187, 168), width=2)
    chalk = (240, 235, 213)
    heading = ImageFont.truetype(HEADER, 73)
    d.text((W/2, 100), title, font=heading, fill=chalk, anchor='mm')
    d.line([(87, 158), (240, 161), (387, 157), (528, 161), (681, 158)], fill=chalk, width=3)
    for i, text in enumerate(items):
        size = 41
        font = ImageFont.truetype(FONT, size)
        while d.textlength(text, font=font) > 542:
            size -= 1
            font = ImageFont.truetype(FONT, size)
        y = 265 + i*132
        d.text((66, y), text, font=font, fill=chalk, anchor='lm')
        # Intentionally blank prices; small chalk dash without a number/currency.
        d.line((665, y+3, 696, y+2), fill=(203, 210, 188), width=3)
    # Restrained decorative sprigs, safely away from the menu entries.
    for side in (-1, 1):
        cx = W/2 + side*50
        d.line((cx, 921, cx+side*130, 900), fill=(152, 179, 146), width=3)
        for j in range(5):
            x = cx + side*(18+j*23)
            y = 918-j*4
            d.ellipse((x-7, y-17, x+7, y-2), outline=(152, 179, 146), width=2)
    im.save(ROOT/filename, optimize=True)

menu('menu_drinks.png', 'DRINKS', ['Kombucha', 'Green tea', 'Bubble tea', 'Coffee', 'Soft drink'], 18)
menu('menu_food.png', 'KITCHEN', ['Grilled cheese', 'Ham sandwich', 'Chicken noodle soup', 'Tofu dish', 'Hamburger & french fries'], 19)
print(ROOT/'menu_drinks.png')
print(ROOT/'menu_food.png')
