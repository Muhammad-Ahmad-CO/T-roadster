#!/usr/bin/env python3
"""Generate T Roadster assets: logo + launcher icons (PIL) and all original
sounds (synthesized WAVs, mono 22050 Hz 16-bit). No copied music or art."""
import math, os, struct, wave
from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/workspace/highway-roadster/t_roadster")
ASSETS = os.path.join(ROOT, "assets")
SOUNDS = os.path.join(ASSETS, "sounds")
RES = os.path.join(ROOT, "android/app/src/main/res")
SR = 22050

# ---------------------------------------------------------------- logo/icons
def sunset_gradient(size):
    img = Image.new("RGB", (size, size))
    top = (43, 16, 85); mid = (184, 50, 128); bot = (255, 126, 61)
    px = img.load()
    for y in range(size):
        t = y / size
        if t < 0.55:
            f = t / 0.55
            c = tuple(int(top[i] + (mid[i] - top[i]) * f) for i in range(3))
        else:
            f = (t - 0.55) / 0.45
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * f) for i in range(3))
        for x in range(size):
            px[x, y] = c
    return img

def draw_pickup(d, s):
    """White angular pickup, rear view, centred. s = image size."""
    w = s * 0.62; h = w * 0.62
    cx, base = s * 0.5, s * 0.78
    body = [(-0.50, 0.50), (-0.48, 0.08), (-0.34, -0.22), (-0.18, -0.38),
            (0.18, -0.38), (0.34, -0.22), (0.48, 0.08), (0.50, 0.50)]
    pts = [(cx + x * w, base + y * h) for x, y in body]
    d.polygon(pts, fill=(245, 245, 245), outline=(255, 255, 255))
    # glass band
    glass = [(-0.36, 0.06), (-0.30, -0.18), (0.30, -0.18), (0.36, 0.06)]
    d.polygon([(cx + x * w, base + y * h) for x, y in glass], fill=(16, 16, 24))
    # rear light bar
    d.rectangle([cx - 0.44 * w, base + 0.20 * h, cx + 0.44 * w, base + 0.27 * h],
                fill=(255, 45, 85))
    # wheels
    d.rectangle([cx - 0.46 * w, base + 0.34 * h, cx - 0.32 * w, base + 0.50 * h],
                fill=(13, 13, 18))
    d.rectangle([cx + 0.32 * w, base + 0.34 * h, cx + 0.46 * w, base + 0.50 * h],
                fill=(13, 13, 18))

def make_logo(size, path):
    img = sunset_gradient(size)
    d = ImageDraw.Draw(img, "RGBA")
    # sun
    d.ellipse([size*0.68, size*0.16, size*0.86, size*0.34], fill=(255, 209, 102))
    # road
    d.polygon([(size*0.30, size), (size*0.70, size), (size*0.56, size*0.52),
               (size*0.44, size*0.52)], fill=(46, 42, 51))
    d.polygon([(size*0.485, size), (size*0.515, size), (size*0.505, size*0.52),
               (size*0.495, size*0.52)], fill=(255, 209, 102))
    draw_pickup(d, size)
    img.save(path, "PNG")
    print("wrote", path, img.size)

make_logo(512, os.path.join(ASSETS, "logo.png"))
make_logo(512, os.path.join(RES, "drawable/ic_launcher_foreground.png"))
# mipmap icons (square + round)
sizes = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
         "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
for folder, sz in sizes.items():
    base = os.path.join(RES, folder)
    img = Image.open(os.path.join(ASSETS, "logo.png")).resize((sz, sz), Image.LANCZOS)
    img.save(os.path.join(base, "ic_launcher.png"))
    # round: circular crop on transparent bg
    mask = Image.new("L", (sz, sz), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, sz, sz], fill=255)
    circ = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    circ.paste(img, (0, 0), mask)
    circ.save(os.path.join(base, "ic_launcher_round.png"))
    print("wrote", folder, sz)

# -------------------------------------------------------------------- WAVs
def write_wav(path, samples):
    samples = [max(-0.89, min(0.89, s)) for s in samples]
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path, f"{len(samples)/SR:.2f}s")

def sine(f, t, phase=0.0):
    return math.sin(2 * math.pi * f * t + phase)

def tone(freqs, dur, decay=6.0, vol=0.5):
    """Sum of sine partials with exponential decay."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        out.append(vol * env * sum(sine(f, t) for f in freqs) / max(1, len(freqs)))
    return out

def sweep(f0, f1, dur, vol=0.5, noise=0.0):
    n = int(SR * dur)
    out = []
    phase = 0.0
    import random
    rnd = random.Random(7)
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (t / dur)
        phase += 2 * math.pi * f / SR
        env = math.sin(math.pi * min(1.0, t / dur))  # smooth in/out
        v = math.sin(phase) * (1 - noise) + (rnd.random() * 2 - 1) * noise
        out.append(vol * env * v)
    return out

def noise_burst(dur, vol=0.6, low=0.0):
    import random
    rnd = random.Random(11)
    n = int(SR * dur)
    out = []
    last = 0.0
    for i in range(n):
        t = i / SR
        env = math.exp(-5 * t)
        white = rnd.random() * 2 - 1
        # simple one-pole lowpass
        last = last + 0.25 * (white - last)
        out.append(vol * env * (last if low else white))
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out

# --- SFX (all original) ---
write_wav(os.path.join(SOUNDS, "click.wav"), tone([1200], 0.06, decay=40, vol=0.4))
write_wav(os.path.join(SOUNDS, "tick.wav"), tone([880], 0.08, decay=30, vol=0.45))
write_wav(os.path.join(SOUNDS, "go.wav"),
          mix(tone([440, 660], 0.5, decay=4, vol=0.4),
              tone([880], 0.5, decay=6, vol=0.15)))
write_wav(os.path.join(SOUNDS, "hop.wav"), sweep(300, 900, 0.25, vol=0.5, noise=0.3))
write_wav(os.path.join(SOUNDS, "coin.wav"),
          mix(tone([1320], 0.18, decay=12, vol=0.35),
              tone([1760], 0.18, decay=14, vol=0.25)))
write_wav(os.path.join(SOUNDS, "whoosh.wav"), sweep(1200, 300, 0.3, vol=0.5, noise=0.6))
write_wav(os.path.join(SOUNDS, "roll.wav"), sweep(400, 1400, 0.4, vol=0.5, noise=0.4))
write_wav(os.path.join(SOUNDS, "flip.wav"), sweep(500, 1600, 0.4, vol=0.5, noise=0.2))
write_wav(os.path.join(SOUNDS, "chime.wav"),
          mix(tone([1046], 0.5, decay=5, vol=0.35),
              tone([1568], 0.5, decay=6, vol=0.3)))
write_wav(os.path.join(SOUNDS, "smash.wav"),
          mix(noise_burst(0.35, vol=0.6, low=1),
              tone([90], 0.3, decay=10, vol=0.5)))
write_wav(os.path.join(SOUNDS, "crash.wav"),
          mix(noise_burst(0.8, vol=0.7, low=1),
              tone([60, 120], 0.8, decay=4, vol=0.5)))
write_wav(os.path.join(SOUNDS, "fanfare.wav"),
          mix(tone([523], 0.3, decay=3, vol=0.3),
              tone([659], 0.3, decay=3, vol=0.3),
              tone([784], 0.9, decay=2, vol=0.4)))
write_wav(os.path.join(SOUNDS, "pickup.wav"),
          mix(tone([660], 0.3, decay=8, vol=0.3),
              tone([880], 0.3, decay=9, vol=0.3),
              tone([1320], 0.3, decay=10, vol=0.25)))

# --- engine loop (2 s, integer cycles so it loops seamlessly) ---
def engine_loop():
    dur = 2.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        # 80 Hz fundamental + harmonics, slight amplitude wobble at 2 Hz
        v = (0.35 * sine(80, t) + 0.2 * sine(160, t) + 0.1 * sine(240, t)
             + 0.06 * sine(320, t))
        v *= 0.9 + 0.1 * sine(2, t)
        out.append(v * 0.5)
    return out
write_wav(os.path.join(SOUNDS, "engine.wav"), engine_loop())

# --- synthwave loops: 4 bars of 4/4 at 112 BPM = 8.571 s, seamless ---
BPM = 112.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
LOOP = 4 * BAR  # 8.571 s

def note_seq(freq, start_beat, beats, vol=0.3, wave_sine=True):
    n = int(SR * LOOP)
    out = [0.0] * n
    start = int(start_beat * BEAT * SR)
    length = int(beats * BEAT * SR)
    for i in range(length):
        t = i / SR
        env = min(1.0, i / (0.01 * SR)) * math.exp(-1.2 * t)
        out[start + i] += vol * env * sine(freq, t)
    return out

def music(redline):
    # Chords: Am - F - C - G, one bar each. Bass roots: A1 F1 C2 G1.
    roots = [55.0, 43.65, 65.41, 49.0]
    chords = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63],
              [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
    tracks = []
    for bar in range(4):
        for beat in range(4):
            tracks.append(note_seq(roots[bar] * 2, bar * 4 + beat, 0.9, vol=0.30))
            tracks.append(note_seq(roots[bar], bar * 4 + beat, 0.9, vol=0.18))
        for f in chords[bar]:
            tracks.append(note_seq(f, bar * 4, 4, vol=0.07))
    if redline:
        # 16th-note arpeggio, one octave up, plus hats.
        arp = [440.0, 523.25, 659.25, 880.0, 659.25, 523.25]
        for bar in range(4):
            for step in range(16):
                f = arp[step % len(arp)]
                tracks.append(note_seq(f, bar * 4 + step * 0.25, 0.22, vol=0.10))
        import random
        rnd = random.Random(3)
        n = int(SR * LOOP)
        hats = [0.0] * n
        for beat in range(16):
            start = int(beat * BEAT * SR)
            for i in range(int(0.03 * SR)):
                hats[start + i] += (rnd.random() * 2 - 1) * 0.08 * math.exp(-120 * i / SR)
        tracks.append(hats)
    return mix(*tracks)

write_wav(os.path.join(SOUNDS, "music_cruise.wav"), music(redline=False))
write_wav(os.path.join(SOUNDS, "music_redline.wav"), music(redline=True))
print("DONE")
