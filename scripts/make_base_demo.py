#!/usr/bin/env python3
"""Writes the fictional, deterministic journals of the demo base (notes/journal-2025.md, -2026.md)."""

from datetime import date, timedelta
from pathlib import Path
import random

random.seed(7)
ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "base-demo" / "notes"

ACTIVITIES = [
    "J'ai avancé sur le cours de systèmes distribués",
    "J'ai relu mes notes d'algorithmique",
    "La séance d'escalade était régulière",
    "J'ai cuisiné une soupe de légumes",
    "J'ai lu quelques chapitres dans le train",
    "J'ai corrigé un détail sur Revisio",
    "J'ai testé une nouvelle pellicule photo",
]
FOLLOW_UPS = [
    "Le résultat était simple mais satisfaisant.",
    "Nora Vidal m'a donné un avis utile.",
    "J'en ai discuté avec Inès Carrel après les cours.",
    "La pluie a rendu la journée assez calme.",
    "Le ciel clair m'a donné envie de marcher.",
    "Je reprendrai ce point demain matin.",
]
DETAILS = [
    "J'ai noté deux idées pour la suite.",
    "Une courte pause a suffi pour retrouver de l'énergie.",
    "Le dîner était composé de pâtes fraîches.",
    "La bibliothèque était presque vide.",
]


def spread_days(start: date, end: date, count: int) -> list[date]:
    length = (end - start).days
    return [start + timedelta(days=(i * length) // (count - 1)) for i in range(count)]


def entry_for(day: date) -> str:
    sentences = [random.choice(ACTIVITIES) + ".", random.choice(FOLLOW_UPS)]
    if random.random() < 0.48:
        sentences.append(random.choice(DETAILS))
    if day.year == 2026 and day.month == 7 and random.random() < 0.65:
        sentences[-1] = random.choice([
            "Au Portugal, j'ai marché longtemps près de l'océan.",
            "Le carnet du Portugal se remplit de petits détails.",
            "La lumière du Portugal était idéale pour les photos.",
        ])
    return " ".join(sentences)


def write(year: int, end: date, count: int = 190) -> None:
    lines = [f"# Journal {year}", ""]
    for day in spread_days(date(year, 1, 1), end, count):
        lines.extend([f"## {day.isoformat()}", entry_for(day), ""])
    (ROOT / f"journal-{year}.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    write(2025, date(2025, 12, 31))
    write(2026, date(2026, 10, 15))


if __name__ == "__main__":
    main()
