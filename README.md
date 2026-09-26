# Adaptive Retirement — Target Date Fund 2.0

> Same retirement date. Different financial lives.

## The problem

Target-date funds are the default investment in most 401(k) plans. They shift from stocks to bonds as retirement approaches, but they only look at one thing: your age. Two 30-year-olds get the same plan, even if one has no debt and a healthy savings cushion while the other carries high-interest debt and has almost no emergency savings.

T. Rowe Price, whose target-date lineup is its largest product line, has publicly said that personalization is the next step for target-date solutions ([research](https://www.troweprice.com/institutional/us/en/insights/articles/2024/q3/make-it-personal-the-next-chapter-for-target-date-solutions-na.html)). This project is a working prototype of that idea.

## What it does

Adaptive Retirement keeps the target-date strategy as the investment foundation and personalizes what sits around it: how much to contribute, and where the next available dollar should go. It looks at a person's real cash flow, debts, interest rates, and savings (from synthetic profiles, or Plaid Sandbox as a stretch goal) and answers three questions:

1. What retirement contribution fits this person's current cash flow?
2. Should the next dollar go to the employer match, emergency savings, or high-interest debt?
3. What happens to debt, cash, and retirement assets over time?

## How it works

- **Financial State Agent** interprets computed indicators such as liquidity, debt burden, savings capacity, and time horizon.
- **Recommendation Agent** proposes a bounded priority order for contributions, debt repayment, and savings.
- **Python validation and cash allocator** checks that proposal and computes every dollar amount. The AI never does the math.
- **Deterministic simulation** projects debt, cash, and retirement balances month by month.
- **Explanation Agent** explains, in plain language, why the plan looks the way it does and why it changed.

The **backend** is a Python 3.12 + FastAPI service ([BACKEND.md](BACKEND.md)). The **frontend** is a native SwiftUI iPhone app that displays results and never recalculates them ([FRONTEND.md](FRONTEND.md)).

## Demo profiles

The demo uses fictional profiles: **Morgan** (competing priorities), **Jordan** (financially established), and **Casey** (approaching retirement). Morgan and Jordan are both 35 and plan to retire at 67, but they get different plans.

*Educational prototype using synthetic or Sandbox data. Not affiliated with or endorsed by T. Rowe Price.*
