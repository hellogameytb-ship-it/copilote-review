#!/usr/bin/env python3
"""Synthetic speaker playback for the hardware recipe; never records input audio."""
import importlib.util
import pathlib
import sys
import tempfile
import wave

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('fixture', pathlib.Path(__file__).with_name('make_test_wav.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
output = pathlib.Path('build/retours-7/speech')
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as directory:
    for i, (name, voice, text) in enumerate([
        ('fr', 'Thomas', 'Comment fonctionne une recherche dans un arbre binaire équilibré ?'),
        ('en', 'Samantha', 'What is a hash table, and how do you handle collisions?'),
        ('resume', 'Thomas', 'Comment fonctionne une fonction récursive ?'),
    ]):
        audio = fixture.silence(0.3) + fixture.speak(text, directory, i, voice) + fixture.silence(0.5)
        with wave.open(str(output / (name + '.wav')), 'wb') as wav:
            wav.setparams((1, 2, fixture.RATE, 0, 'NONE', 'not compressed'))
            wav.writeframes(audio)
        print(name, round(len(audio) / 2 / fixture.RATE, 2), 'seconds')
