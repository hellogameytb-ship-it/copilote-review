#!/usr/bin/env python3
"""Builds the replay fixtures, spoken by the macOS French voice with pauses (16 kHz mono):
- three-questions: three distinct questions, then a follow-up on the first one;
- follow-up: a question, then a follow-up sharing no keyword with it (needs a model to link them);
- perso: personal questions to Camille, the fictional person of fixtures/base-demo (direct fiches),
  then a technical one (LLM path);
- pression: one behavioural question (the story in a project's Histoires section);
- trois-types: an estimation, an opinion not in avis.md, a behavioural question, with the time
  to answer between them (the drafted answer of each case);
- reunion: a short fictional product meeting in stereo (left "Eux", right "Moi", two voices),
  for `make notes`."""
import os
import subprocess
import sys
import tempfile
import wave

SCENARIOS = {
    "three-questions": [
        "Est-ce que tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?",
        "D'accord. Et sinon, quelle est la complexité d'une recherche dans un arbre binaire équilibré ?",
        "Dernière question : pourquoi est-ce que tu veux faire un stage en finance quantitative ?",
        "Ah, et pour revenir au ramasse-miettes de Java : comment est-ce qu'il gère les cycles de références ?",
    ],
    "follow-up": [
        "Peux-tu me parler de ton dernier projet ?",
        "Et combien de temps ça t'a pris ?",
    ],
    "perso": [
        "Salut Camille ! Alors, t'étais où cet été ?",
        "Génial. Et sinon, c'est quoi ton projet d'app de révision ?",
        "D'accord. Et tu peux m'expliquer comment marche le ramasse-miettes en Java ?",
    ],
    "pression": [
        "Raconte-moi un projet qui t'a mis sous pression.",
    ],
    "trois-types": [
        "Parle-moi des ventes de peluches en 2027.",
        "C'est qui ton président des États-Unis préféré ?",
        "Raconte-moi un projet qui t'a mis sous pression.",
    ],
}
# Silence between questions, where it is not GAP_SILENCE: the user answering.
GAPS = {"trois-types": 9.0}
# Stereo dialogues: (speaker, line); "eux" on the left channel, "moi" on the right.
DIALOGUES = {
    "reunion": [
        ("eux", "Bonjour Camille. On fait le point sur la sortie de Revisio ?"),
        ("moi", "Oui. La version web est prête, il reste l'export des fiches en PDF."),
        ("eux", "D'accord. On garde la sortie au douze novembre ?"),
        ("moi", "Oui, si on repousse l'export à la version suivante."),
        ("eux", "Très bien, on repousse l'export. Qui prépare la démo pour jeudi ?"),
        ("moi", "Je m'en occupe, je l'envoie mercredi soir."),
        ("eux", "Parfait. Il reste à savoir qui gère le support pendant le lancement."),
        ("moi", "Je n'ai pas encore de réponse, je demande à l'équipe."),
        ("eux", "Bon. On refait un point vendredi matin."),
    ],
}
VOICES = {"eux": "Thomas", "moi": "Flo (Français (France))"}
RATE = 16000
LEAD_SILENCE, GAP_SILENCE, TAIL_SILENCE = 0.8, 2.5, 1.5


def speak(text, directory, index, voice="Thomas"):
    aiff = os.path.join(directory, f"{index}.aiff")
    wav = os.path.join(directory, f"{index}.wav")
    subprocess.run(["say", "-v", voice, "-o", aiff, text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", aiff, wav], check=True)
    with wave.open(wav, "rb") as clip:
        return clip.readframes(clip.getnframes())


def silence(seconds):
    return b"\x00\x00" * int(seconds * RATE)


def stereo(scenario):
    """Each speaker on their own channel, silence on the other, like Copilote's two captures."""
    left, right = silence(LEAD_SILENCE), silence(LEAD_SILENCE)
    with tempfile.TemporaryDirectory() as directory:
        for index, (speaker, line) in enumerate(DIALOGUES[scenario]):
            voice = speak(line, directory, index, VOICES[speaker])
            quiet = b"\x00\x00" * (len(voice) // 2)
            left += voice if speaker == "eux" else quiet
            right += voice if speaker == "moi" else quiet
            gap = silence(1.2)
            left += gap
            right += gap
    frames = bytearray()
    for index in range(0, len(left), 2):
        frames += left[index:index + 2] + right[index:index + 2]
    output = f"fixtures/{scenario}.wav"
    with wave.open(output, "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(bytes(frames))
    print(f"{output}: {len(left) / 2 / RATE:.1f} s, stéréo")


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "three-questions"
    if scenario in DIALOGUES:
        return stereo(scenario)
    lines = SCENARIOS[scenario]
    output = f"fixtures/{scenario}.wav"
    with tempfile.TemporaryDirectory() as directory:
        frames = silence(LEAD_SILENCE)
        for index, line in enumerate(lines):
            frames += speak(line, directory, index)
            frames += silence(GAPS.get(scenario, GAP_SILENCE) if index < len(lines) - 1 else TAIL_SILENCE)
    with wave.open(output, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)
    print(f"{output}: {len(frames) / 2 / RATE:.1f} s")


if __name__ == "__main__":
    main()
