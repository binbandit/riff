"""Generate Riff's original, royalty-free starter sounds. Standard library only."""
import math
import pathlib
import struct
import wave
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOUNDS = {
    'level-up': [(523, .12), (659, .12), (784, .12), (1047, .40)],
    'plot-twist': [(392, .28), (370, .28), (262, .65)],
    'nope': [(220, .18), (165, .35)],
    'countdown': [(880, .15), (0, .55), (880, .15), (0, .55), (1320, .4)],
    'coin-drop': [(988, .07), (1319, .32)],
    'red-alert': [(740, .18), (523, .18)] * 4,
}
for name, notes in SOUNDS.items():
    samples = []
    for frequency, duration in notes:
        count = int(duration * 44100)
        for index in range(count):
            t = index / 44100
            envelope = min(1, index / 220) * min(1, (count - index) / 1800)
            sound = (math.sin(2 * math.pi * frequency * t) + .2 * math.sin(4 * math.pi * frequency * t)) if frequency else 0
            samples.append(int(15000 * envelope * sound))
    for folder in ['Shared/Sounds', 'Riff/Resources/Sounds']:
        with wave.open(str(ROOT / folder / (name + '.wav')), 'wb') as output:
            output.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
