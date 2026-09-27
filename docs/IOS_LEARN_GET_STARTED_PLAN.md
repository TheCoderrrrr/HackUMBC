# iOS Learn and Getting started plan

## Web behavior to carry over

- Learn contains six short lessons: employer match, compound growth, expensive debt, emergency savings, inflation, and target-date funds. Each lesson shows a fact from the selected profile and offers a relevant action.
- Getting started has five pages: welcome, ARM's monthly priority order, three key ideas, plan-style choice, and a tour. It opens on first visit per profile and can be reopened later. Completing it opens the plan.
- The three styles are Balanced, Cash security first, and Debt payoff first. The selected style is stored per profile and affects live evaluations through `planning_preference`.

## Implementation

1. Add a Learn tab with the six lessons, profile/evaluation-backed figures, and native actions into Explore, Plan, Funds, or Getting started. Pass scenario actions through AppStore so Explore receives a specific draft even when its view is recreated.
2. Add a five-step Getting started sheet, accessible from Learn and Plan. Use `/v1/plan-styles` for the selected style's priority order and personal milestones when live calculation is available. Persist guide completion and style choice per profile. Keep dismissal and Learn-first exits available.
3. Apply the selected style to live evaluation requests. Keep the saved artifact labeled as Balanced when offline, and explain when a selected style needs a live calculation. Do not change calculations locally.
4. Verify a simulator build and review first visit, reopen, profile switching, offline style labeling, and lesson navigation. Avoid adding new backend contracts.

## Acceptance checks

- Every web lesson appears with current-profile facts and a working destination.
- Getting started has all five pages, Back/Skip/Finish, style selection, first-visit behavior, and a reopen path.
- Live requests use the selected profile's style; saved results never imply that another style was calculated.
- Changing profiles refreshes facts, style, and first-visit state.
