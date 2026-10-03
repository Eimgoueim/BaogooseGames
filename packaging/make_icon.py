# Generate the app icon (multi-size .ico) for the installer / shortcuts.
from PIL import Image, ImageDraw

S = 256
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# vertical gradient background (game palette: purple -> pink)
for y in range(S):
    t = y / (S - 1)
    r = int(0x8b + (0xff - 0x8b) * t)
    g = int(0x7b + (0x8f - 0x7b) * t)
    b = int(0xff + (0xb1 - 0xff) * t)
    d.line([(0, y), (S, y)], fill=(r, g, b, 255))

# rounded corners
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=58, fill=255)
img.putalpha(mask)

d = ImageDraw.Draw(img)
HAIR = (255, 176, 207, 255)
FACE = (255, 247, 240, 255)
INK = (72, 62, 84, 255)

d.polygon([(66, 104), (86, 38), (122, 88)], fill=HAIR)        # left ear
d.polygon([(190, 104), (170, 38), (134, 88)], fill=HAIR)      # right ear
d.ellipse([54, 62, 202, 210], fill=FACE)                      # head
d.ellipse([90, 118, 112, 148], fill=INK)                      # eyes
d.ellipse([144, 118, 166, 148], fill=INK)
d.ellipse([99, 123, 108, 134], fill=(255, 255, 255, 255))     # highlights
d.ellipse([153, 123, 162, 134], fill=(255, 255, 255, 255))
d.ellipse([70, 146, 96, 158], fill=(255, 179, 179, 170))      # blush
d.ellipse([160, 146, 186, 158], fill=(255, 179, 179, 170))
d.arc([104, 150, 152, 190], start=15, end=165, fill=(164, 108, 118, 255), width=8)  # smile

img.save('PetGame.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('icon written')
