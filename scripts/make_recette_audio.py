#!/usr/bin/env python3
"""Controlled FR/EN speech, never microphone audio. Regenerate with macOS say/afconvert."""
import importlib.util
import pathlib
import tempfile
import wave

spec = importlib.util.spec_from_file_location('fixture', pathlib.Path(__file__).with_name('make_test_wav.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
output = pathlib.Path('build/retours-6/recette-fr-en.wav')
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as directory:
    audio = fixture.silence(1)
    lines = [
        ('Thomas', 'Comment fonctionne une recherche dans un arbre binaire équilibré ?'),
        ('Samantha', 'What is a hash table, and how do you handle collisions?'),
        ('Thomas', 'Comment comparer Python et'),
        ('Thomas', 'Swift pour créer une application ?'),
        ('Samantha', 'Why is a cache useful in a database?'),
    ]
    for i, (voice, text) in enumerate(lines):
        audio += fixture.speak(text, directory, i, voice)
        audio += fixture.silence(0.9 if i == 2 else 3.5)
    with wave.open(str(output), 'wb') as wav:
        wav.setparams((1, 2, fixture.RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(audio)
print(output, 'seconds', round(len(audio) / 2 / fixture.RATE, 1))
