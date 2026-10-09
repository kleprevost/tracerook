from __future__ import annotations

from dataclasses import dataclass

from .config import Settings


@dataclass(frozen=True)
class Plan:
    id: str
    name: str
    description: str
    price_label: str
    monthly_quota: int
    features: tuple[str, ...]
    public: bool = True


def build_plans(settings: Settings) -> dict[str, Plan]:
    individual = Plan(
        id="individual",
        name="Individual",
        description="Contextual analysis of risky agent actions for one developer.",
        price_label="$5 / month",
        monthly_quota=settings.individual_quota,
        features=(
            f"{settings.individual_quota:,} analyzed actions per month",
            "Task-relevance and prompt-injection analysis by Anthropic Claude",
            f"Up to {settings.max_devices_per_account} enrolled Macs",
            "Redacted context only; analyzed content is never stored",
        ),
    )
    return {individual.id: individual}
