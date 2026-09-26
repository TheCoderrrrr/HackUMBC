<div id="top">

<div align="center">

<!-- LOGO PLACEHOLDER: add the square logo as assets/logo.svg, then uncomment the line below. -->
<!-- <img src="assets/logo.svg" width="160" alt="Adaptive Retirement logo"/> -->

# ADAPTIVE RETIREMENT

<em>Target Date Fund 2.0: same retirement date, different financial lives.</em>

<!-- BADGES -->
<img src="https://img.shields.io/github/last-commit/TheCoderrrrr/HackUMBC?style=flat-square&logo=git&logoColor=white&color=13A89E" alt="last-commit">
<img src="https://img.shields.io/github/languages/top/TheCoderrrrr/HackUMBC?style=flat-square&color=13A89E" alt="repo-top-language">
<img src="https://img.shields.io/badge/status-hackathon%20prototype-F2A541?style=flat-square" alt="status">

<em>Built with the tools and technologies:</em>

<img src="https://img.shields.io/badge/Python%203.12-3776AB.svg?style=flat-square&logo=Python&logoColor=white" alt="Python">
<img src="https://img.shields.io/badge/FastAPI-009688.svg?style=flat-square&logo=FastAPI&logoColor=white" alt="FastAPI">
<img src="https://img.shields.io/badge/Pydantic-E92063.svg?style=flat-square&logo=Pydantic&logoColor=white" alt="Pydantic">
<img src="https://img.shields.io/badge/pytest-0A9EDC.svg?style=flat-square&logo=Pytest&logoColor=white" alt="pytest">
<br>
<img src="https://img.shields.io/badge/Swift-F05138.svg?style=flat-square&logo=Swift&logoColor=white" alt="Swift">
<img src="https://img.shields.io/badge/SwiftUI-0D96F6.svg?style=flat-square&logo=Swift&logoColor=white" alt="SwiftUI">
<img src="https://img.shields.io/badge/iOS%2017+-000000.svg?style=flat-square&logo=Apple&logoColor=white" alt="iOS">
<img src="https://img.shields.io/badge/Plaid%20Sandbox-111111.svg?style=flat-square" alt="Plaid Sandbox">

</div>
<br>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [How It Works](#how-it-works)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
    - [Usage](#usage)
    - [Testing](#testing)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Overview

Target-date funds are the default investment in most 401(k) plans. They shift from stocks to bonds as retirement approaches, but they only look at one thing: your age. Two 30-year-olds get the same plan, even if one has no debt and a healthy savings cushion while the other carries high-interest debt and has almost no emergency savings.

T. Rowe Price, whose target-date lineup is its largest product line, has publicly said that personalization is the next step for target-date solutions ([research](https://www.troweprice.com/institutional/us/en/insights/articles/2024/q3/make-it-personal-the-next-chapter-for-target-date-solutions-na.html)). **Adaptive Retirement** is a working prototype of that idea.

It keeps the target-date strategy as the investment foundation and personalizes what sits around it: how much to contribute, and where the next available dollar should go.

---

## Features

|      | Feature | Summary |
| :--- | :---: | :--- |
| 💵 | **Affordable contributions** | Recommends a retirement contribution that fits current take-home pay, living costs and required debt payments. |
| 🎯 | **Next-dollar priorities** | Orders employer match, emergency savings and high-interest debt, with every dollar funded from one shared budget. |
| 🤖 | **Bounded AI reasoning** | AI agents choose among permitted priority orders; Python validates the choice and computes every amount. |
| 💬 | **Explainable plans** | Every section has a "Why?" with the decision, tradeoffs and supporting inputs, plus a template fallback. |
| 📈 | **Projections** | Deterministic month-by-month projections of debt, cash and retirement assets: current vs. adaptive vs. custom. |
| 📴 | **Works offline** | Nine engine-generated demo scenarios are bundled into the iPhone app, so the demo survives a network outage. |
| 🏦 | **Plaid Sandbox (stretch)** | Optional import of debts and balances from Plaid Sandbox, confirmed by the user before evaluation. |

---

## How It Works

```text
Demo profiles or Plaid Sandbox + confirmed inputs
  -> Financial State Agent     interprets Python-computed liquidity, debt burden, savings capacity, horizon
  -> Recommendation Agent      proposes a bounded priority order
  -> Python validation         checks the proposal and allocates every dollar
  -> Deterministic simulation  projects debt, cash and retirement assets monthly
  -> Explanation Agent         explains why the plan looks the way it does
  -> SwiftUI iPhone app        displays results (never recalculates them)
```

Demo profiles are fictional. **Morgan** (competing priorities) and **Jordan** (financially established) are both 35 and plan to retire at 67, but get different plans. **Casey** is approaching retirement.

---

## Project Structure

Planned layout (see [BACKEND.md](BACKEND.md) and [FRONTEND.md](FRONTEND.md)):

```sh
└── HackUMBC/
    ├── README.md
    ├── BACKEND.md              # backend and financial engine spec
    ├── BACKEND_TEAM_SPLIT.md   # backend ownership
    ├── FRONTEND.md             # SwiftUI app spec
    ├── assets/                 # logo (to be added)
    ├── backend/                # Python 3.12 + FastAPI service
    │   ├── app/
    │   │   ├── main.py
    │   │   ├── api.py
    │   │   ├── schemas.py
    │   │   ├── engine/         # state, policy, simulation, assumptions
    │   │   └── integrations/   # optional Plaid Sandbox
    │   ├── fixtures/
    │   ├── scripts/export_demo.py
    │   └── tests/
    ├── contracts/              # OpenAPI + example payloads
    └── ios/                    # SwiftUI app
        └── AdaptiveRetirement/
```

---

## Getting Started

### Prerequisites

- **Backend:** Python 3.12
- **iOS app:** a Mac with Xcode, and an iPhone running iOS 17+
- **Demo hosting:** [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) for a temporary HTTPS tunnel

### Installation

1. **Clone the repository:**

    ```sh
    git clone https://github.com/TheCoderrrrr/HackUMBC.git
    cd HackUMBC/backend
    ```

2. **Create a virtual environment and install dependencies:**

    ```sh
    python -m venv .venv
    source .venv/bin/activate        # Windows: .venv\Scripts\activate
    pip install -r requirements.txt
    ```

3. **Configure the environment:** copy `.env.example` to `.env` and fill in the AI provider settings. Without AI credentials, the backend uses its rules fallback.

### Usage

Start the API:

```sh
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Expose it to the phone (in a separate terminal), then enter the printed HTTPS URL in the app's Connection Settings:

```sh
cloudflared tunnel --url http://localhost:8000
```

Open `ios/AdaptiveRetirement.xcodeproj` in Xcode and run on a physical iPhone.

### Testing

```sh
cd backend
pytest
```

---

## Roadmap

- [ ] **`Vertical slice`**: Morgan's live evaluation reaches the phone and loads from the bundle.
- [ ] **`MVP`**: all profiles, plan, explanations, projections, offline presets, AI ordering with rules fallback.
- [ ] **`Stretch`**: Plaid Sandbox import and Monte Carlo projections.
- [ ] **`Demo final`**: rehearsed live and offline demo on the physical iPhone.

---

## Contributing

- Work on short-lived task branches and open pull requests into `main`.
- Keep `main` buildable; squash-merge reviewed PRs every one to two hours.
- API contract changes require updated examples in `contracts/` and a successful Swift decode.
- Python computes all money. AI output never sets amounts, allocations or assumptions.

---

## License

No license has been chosen yet.

---

## Acknowledgments

- Built for [HackUMBC](https://hackumbc.org/).
- Inspired by T. Rowe Price's research on [target-date personalization](https://www.troweprice.com/institutional/us/en/insights/articles/2024/q3/make-it-personal-the-next-chapter-for-target-date-solutions-na.html).
- README structure generated with [readme-ai](https://github.com/eli64s/readme-ai).

*Educational prototype using synthetic or Sandbox data. Not affiliated with or endorsed by T. Rowe Price.*

<div align="right">

[![][back-to-top]](#top)

</div>

[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square

