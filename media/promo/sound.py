#!/usr/bin/env python3
"""Original, quiet synthesized ambient score. No samples or third-party music."""
import math
import struct
import sys
import wave

RATE = 48000
DURATION = 30
CHORDS = [
    (0.0, 9.0, (130.8128, 195.9977, 261.6256, 293.6648)),
    (7.0, 10.0, (146.8324, 220.0000, 293.6648, 329.6276)),
    (15.0, 10.0, (174.6141, 261.6256, 349.2282, 391.9954)),
    (23.0, 8.0, (130.8128, 195.9977, 261.6256, 329.6276)),
]

def smooth(v):
    v = max(0.0, min(1.0, v))
    return v * v * (3.0 - 2.0 * v)

with wave.open(sys.argv[1], 'wb') as output:
    output.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
    block = bytearray()
    for index in range(RATE * DURATION):
        t = index / RATE
        channels = [0.0, 0.0]
        for start, length, frequencies in CHORDS:
            local = t - start
            if 0 <= local <= length:
                envelope = smooth(local / 2.7) * smooth((length - local) / 3.0)
                for note, freq in enumerate(frequencies):
                    pan = 0.35 + 0.3 * (note / 3)
                    tone = math.sin(2 * math.pi * freq * local + 0.15 * math.sin(local * .4))
                    tone += .18 * math.sin(2 * math.pi * freq * 2 * local)
                    tone *= .014 * envelope
                    channels[0] += tone * (1.1 - pan)
                    channels[1] += tone * pan
        for event, freq in [(3.5, 659.25), (7.83, 987.77), (10.6, 783.99), (16.0, 659.25), (22.9, 880), (26.8, 523.25)]:
            elapsed = t - event
            if 0 <= elapsed <= .8:
                note = .018 * math.sin(2 * math.pi * freq * elapsed) * math.exp(-elapsed * 7) * smooth(elapsed / .015)
                channels[0] += note * .65
                channels[1] += note * .65
        fade = smooth(t / 1.5) * smooth((DURATION - t) / 2.0)
        block += struct.pack('<hh', *[int(max(-1, min(1, value * fade)) * 32767) for value in channels])
        if len(block) >= 65536:
            output.writeframesraw(block)
            block.clear()
    output.writeframesraw(block)
