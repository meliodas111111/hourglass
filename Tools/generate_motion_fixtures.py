#!/usr/bin/env python3
"""
Generates the CoreMotion gravity.y traces used by FlipDetectorTests.

The traces mimic data recorded with CMDeviceMotion at 60 Hz (sensor noise, hand tremor, a ~0.5 s rotation).
Real recordings can be dropped into the same folder in the same "t,gy" CSV format — the tests pick up every
file and read the expected number of flips from the file name suffix `__<n>flips.csv`.

    python3 Tools/generate_motion_fixtures.py
"""
import math
import pathlib
import random

OUT = pathlib.Path(__file__).resolve().parent.parent / "Packages/HourglassCore/Tests/HourglassCoreTests/Fixtures"
HZ = 60.0


def noise(rnd, amp=0.02):
    return rnd.gauss(0, amp)


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / name, "w", newline="\n") as f:
        f.write("t,gy\n")
        for t, gy in samples:
            f.write(f"{t:.4f},{max(-1.0, min(1.0, gy)):.4f}\n")


def hold(rnd, t0, seconds, value, tremor=0.03):
    out, n = [], int(seconds * HZ)
    for i in range(n):
        t = t0 + i / HZ
        out.append((t, value + tremor * math.sin(t * 7.3) + noise(rnd)))
    return out, t0 + n / HZ


def rotate(rnd, t0, seconds, a, b):
    out, n = [], int(seconds * HZ)
    for i in range(n):
        u = i / max(n - 1, 1)
        s = 0.5 - 0.5 * math.cos(math.pi * u)  # ease-in-out
        out.append((t0 + i / HZ, a + (b - a) * s + noise(rnd)))
    return out, t0 + n / HZ


def seq(rnd, parts):
    t, out = 0.0, []
    for kind, *args in parts:
        chunk, t = (hold if kind == "hold" else rotate)(rnd, t, *args)
        out += chunk
    return out


def main():
    rnd = random.Random(42)
    write("clean_flip__1flips.csv", seq(rnd, [("hold", 1.5, -0.97), ("rotate", 0.5, -0.97, 0.96), ("hold", 2.0, 0.96)]))
    write("double_flip__2flips.csv", seq(rnd, [("hold", 1.0, -0.95), ("rotate", 0.45, -0.95, 0.95), ("hold", 1.5, 0.95),
                                               ("rotate", 0.5, 0.95, -0.95), ("hold", 1.5, -0.95)]))
    # Brief spike past +0.8 (bump / fast wiggle): shorter than 300 ms → no flip.
    write("short_spike__0flips.csv", seq(rnd, [("hold", 1.0, -0.95), ("rotate", 0.08, -0.95, 0.88), ("hold", 0.15, 0.88),
                                               ("rotate", 0.08, 0.88, -0.95), ("hold", 1.0, -0.95)]))
    # Tilted to ~0.72 upside down: inside the hysteresis band, never beyond 0.8 → no flip.
    write("partial_tilt__0flips.csv", seq(rnd, [("hold", 1.0, -0.95), ("rotate", 0.6, -0.95, 0.72), ("hold", 2.0, 0.72)]))
    # Lying flat on a table, gy ≈ 0.
    write("flat_on_table__0flips.csv", seq(rnd, [("hold", 3.0, 0.0, 0.01)]))
    # Starts upside down (app launched while inverted) — first orientation adopted silently.
    write("launch_inverted__0flips.csv", seq(rnd, [("hold", 2.0, 0.93)]))
    # Flip, wobble around 0.78–0.9 (hand shake) while holding: still one flip thanks to hysteresis.
    wob, t = [], 0.0
    part, t = hold(rnd, t, 1.0, -0.95); wob += part
    part, t = rotate(rnd, t, 0.5, -0.95, 0.84); wob += part
    for i in range(int(1.5 * HZ)):
        tt = t + i / HZ
        wob.append((tt, 0.84 + 0.07 * math.sin(tt * 25) + noise(rnd, 0.01)))
    write("wobbly_hold__1flips.csv", wob)


if __name__ == "__main__":
    main()
