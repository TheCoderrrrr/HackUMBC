"""Canonical, isolated financial profiles for engine tests."""

import json
from copy import deepcopy
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def profiles():
    path = Path(__file__).parents[1] / "fixtures" / "profiles.json"
    return {profile["id"]: profile for profile in json.loads(path.read_text(encoding="utf-8"))}


@pytest.fixture
def morgan(profiles):
    return deepcopy(profiles["morgan"])
