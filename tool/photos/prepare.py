"""Turn photos into Daily Sort reveal pictures.

For each photo this writes, into the output folder:
  <name>.jpg        the photo, cropped to the 2:1 frame, full color
  <name>-sketch.jpg a soft pencil sketch of the same crop
  <name>-areas.png  red = which reveal area (0..4, times 50),
                    green = when that pixel fills in during the reveal (0..255)
and a photos.json listing title, credit and Unsplash page link per photo.

Usage: python3 -I prepare.py photos.json in_dir out_dir
"""
import json, sys, os
import numpy as np
import cv2
from PIL import Image
from skimage.segmentation import slic
from sklearn.cluster import KMeans

W, H, AREAS = 1200, 600, 5


def crop(img, focus_y=0.5):
    h, w = img.shape[:2]
    if w / h > W / H:
        nw = int(h * W / H); x = (w - nw) // 2
        img = img[:, x:x + nw]
    else:
        nh = int(w * H / W); y = int((h - nh) * focus_y)
        img = img[y:y + nh]
    return cv2.resize(img, (W, H), interpolation=cv2.INTER_AREA)


def sketch(img):
    gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    blur = cv2.GaussianBlur(255 - gray, (0, 0), 9)
    dodge = cv2.divide(gray, 255 - blur, scale=256)
    # Soften: lift contrast of the lines a little, then lay on warm paper.
    s = np.clip((dodge.astype(np.float32) / 255) ** 1.8, 0, 1)
    s = 0.25 + 0.75 * s  # never pure black
    paper = np.array([250, 245, 235], np.float32) / 255
    rng = np.random.default_rng(1)
    grain = 1 - 0.035 * cv2.GaussianBlur(rng.random((H, W)).astype(np.float32), (0, 0), 0.8)
    out = s[..., None] * paper[None, None] * grain[..., None]
    return (out * 255).astype(np.uint8)


def areas(img, k=AREAS):
    lab = cv2.cvtColor(img, cv2.COLOR_RGB2LAB).astype(np.float32)
    seg = slic(img, n_segments=500, compactness=12, start_label=0)
    n = seg.max() + 1
    ys, xs = np.mgrid[0:H, 0:W]
    feats = []
    for i in range(n):
        m = seg == i
        c = lab[m].mean(0)
        feats.append([c[0] / 255 * 1.0, (c[1] - 128) / 128 * 1.2, (c[2] - 128) / 128 * 1.2,
                      xs[m].mean() / W * 0.9, ys[m].mean() / H * 0.9])
    lab_ids = KMeans(k, n_init=10, random_state=0).fit_predict(np.array(feats))
    area = lab_ids[seg]
    # Tidy: smooth the borders and fold away tiny islands.
    for _ in range(2):
        votes = np.stack([cv2.blur((area == a).astype(np.float32), (31, 31)) for a in range(k)])
        area = votes.argmax(0)
    area = _drop_islands(area, k, min_px=W * H // 150)
    # Order areas top to bottom-ish so ids are stable and readable.
    cy = [ys[area == a].mean() if (area == a).any() else 9e9 for a in range(k)]
    remap = np.argsort(np.argsort(cy))
    area = remap[area]
    # Growth: each area fills outward from its most "inside" point.
    grow = np.zeros((H, W), np.float32)
    for a in range(k):
        m = (area == a).astype(np.uint8)
        if not m.any():
            continue
        inside = cv2.distanceTransform(m, cv2.DIST_L2, 5)
        sy, sx = np.unravel_index(inside.argmax(), inside.shape)
        d = np.sqrt((xs - sx) ** 2 + (ys - sy) ** 2).astype(np.float32)
        # A little wobble so the edge looks painted, not a perfect circle.
        noise = cv2.GaussianBlur(np.random.default_rng(a).random((H, W)).astype(np.float32), (0, 0), 25)
        noise = (noise - noise.min()) / (np.ptp(noise) + 1e-6)
        d = d * (0.75 + 0.5 * noise)
        dm = d[m > 0]
        grow[m > 0] = (dm - dm.min()) / (np.ptp(dm) + 1e-6)
    return area.astype(np.uint8), grow


def _drop_islands(area, k, min_px):
    out = area.copy()
    for a in range(k):
        n, lbl, stats, _ = cv2.connectedComponentsWithStats((area == a).astype(np.uint8), 8)
        for j in range(1, n):
            if stats[j, cv2.CC_STAT_AREA] < min_px:
                blob = lbl == j
                ring = cv2.dilate(blob.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
                ring &= ~blob
                vals = out[ring]
                vals = vals[vals != a]
                if len(vals):
                    out[blob] = np.bincount(vals, minlength=k).argmax()
    return out


def main(spec_path, in_dir, out_dir):
    spec = json.load(open(spec_path))
    os.makedirs(out_dir, exist_ok=True)
    listing = []
    for p in spec:
        img = np.array(Image.open(os.path.join(in_dir, p['file'])).convert('RGB'))
        img = crop(img, p.get('focus_y', 0.5))
        area, grow = areas(img)
        name = p['name']
        Image.fromarray(img).save(f'{out_dir}/{name}.jpg', quality=86)
        Image.fromarray(sketch(img)).save(f'{out_dir}/{name}-sketch.jpg', quality=86)
        rgb = np.zeros((H, W, 3), np.uint8)
        rgb[..., 0] = area * 50
        rgb[..., 1] = (grow * 255).astype(np.uint8)
        Image.fromarray(rgb).save(f'{out_dir}/{name}-areas.png')
        listing.append({k: p[k] for k in ('name', 'title', 'credit', 'page') if k in p})
        print('done', name)
    json.dump(listing, open(f'{out_dir}/photos.json', 'w'), indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:4])
