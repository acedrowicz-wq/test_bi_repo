# Active players by free-spin usage: "FS Only" / "Without FS" / "Total"

User story: filter the active-player count by free-spin usage so that Tableau can be reconciled with the
Backoffice, which leaves out players whose whole activity was free spins.

**No change to the data source.** `bi_sandbox.bi_total_eg_v` already has everything that is needed:
the player (`wlId` + `wlUserId`), the free-spin grant of the row (`freeSpins`, NULL = no free spins)
and the number of bets of the row (`mongoId`). The logic lives in Tableau calculations, because it has to
be evaluated for the period and the breakdown on the sheet (a player can be "FS only" on Monday and a
real-money player on Tuesday).

## Definitions (= Backoffice)
| Group | A player is in the group when, in the period and slice shown |
|---|---|
| **Without FS** | they placed at least one bet without free spins (`freeSpins` is NULL and `mongoId` > 0). This is the Backoffice "Players" (GGR without Promo: `isPromo = 0`, bets > 0). |
| **FS Only** | they were active only with free spins: some free-spin activity and no bet without free spins. |
| **Total** | Without FS + FS Only. |

"FS Only" is computed as `Total − Without FS`. It is exact at every level (day, month, casino, game),
because "Without FS" players are a subset of "Total" players.

## AC1: calculations in the data source (Tableau)
Field names as in the view; if the workbook renamed them (e.g. `Wl Id`, `Mongo Id`), use those names.

**Parameter** `[P] Players FS filter`: data type String, *List*, values `Total`, `Without FS`, `FS Only`
(value = display text), current value `Total`.

```
// Player key  (string)
[wlId] + '|' + [wlUserId]
```
A casino's player id is unique only inside the casino, so the casino is part of the key (like the Backoffice).

```
// Is bet without FS  (boolean, row level)
ISNULL([freeSpins]) AND [mongoId] > 0
```

```
// Is FS activity  (boolean, row level)
NOT ISNULL([freeSpins])
```

```
// Players without FS
COUNTD(IF [Is bet without FS] THEN [Player key] END)
```

```
// Players total
COUNTD(IF [Is bet without FS] OR [Is FS activity] THEN [Player key] END)
```

```
// Players FS only
[Players total] - [Players without FS]
```

```
// Active players   <- use this measure on the dashboard
CASE [[P] Players FS filter]
WHEN 'Without FS' THEN [Players without FS]
WHEN 'FS Only'    THEN [Players FS only]
ELSE [Players total]
END
```

Optional, for the money KPIs of the same sheet (bets, GGR) to follow the switch:
```
// FS row filter  (boolean)  -> on the Filters shelf, True
CASE [[P] Players FS filter]
WHEN 'Without FS' THEN ISNULL([freeSpins])
WHEN 'FS Only'    THEN NOT ISNULL([freeSpins])
ELSE TRUE
END
```
Do **not** put this row filter on a sheet that shows `Active players` with "FS Only": it removes the
real-money rows, so `Players FS only` could no longer subtract the players who also played for real
money (it would show every player with any free spin, 243 instead of 100 on 2026-10-07).
"Without FS" + the row filter is safe and equals the Backoffice "GGR (without Promo)" scope.

## AC2: dashboard
1. Right-click the parameter → *Show Parameter*, on the daily report dashboard.
2. Parameter card menu → *Single Value List* (radio buttons): `Total`, `Without FS`, `FS Only`.
3. Replace the current active-player measure (`Players` / `Unique users`) on the daily report sheets with
   `Active players`, and add the selected state to the title, e.g. `Active players (<[P] Players FS filter>)`.

## AC3: validation (ProdCH, 2026-10-10)
Query: `08_validation_fs_players.sql`. The view numbers are exactly what the calculations above return.

| Product | Period | Without FS (Tableau) | FS Only | Total | Backoffice logic, exact (`agg_players_daily`) | Backoffice screen (`agg_daily`, approximate) |
|---|---|---|---|---|---|---|
| Slots | 07.10 | **117,853** | 100 | 117,953 | **117,853** | 117,861 (Games Report, GGR without Promo) |
| Slots | 08.10 | 127,782 | 101 | 127,883 | 127,791 | 127,566 |
| Slots | 07–08.10 | 210,780 | 179 | 210,959 | 210,788 | 210,046 |
| Live | 07.10 | 3,904 | 73 | 3,977 | 3,902 | 3,902 |
| Live | 08.10 | 4,140 | 77 | 4,217 | 4,144 | 4,140 |
| Live | 07–08.10 | 7,004 | 135 | 7,139 | 7,004 | 6,995 |

What "perfectly matches" can mean here:
- The **Backoffice screen counts players approximately** (`uniqCombined64` in `platform.agg_daily`, error of a
  few tenths of a percent, larger over several days). No exact count can reproduce it digit for digit:
  on 07.10 the exact Backoffice logic gives 117,853 and the screen shows 117,861.
- Against the **exact Backoffice logic** the result is identical on 07.10 (slots) and on 07–08.10 (live), and
  within 0–9 players (≤ 0.1%) on the other days. The rest is the day boundary: the Backoffice assigns a bet to
  its settlement day (`updatedAt`), the source to the day the bet was placed (`createdAt`); a player whose only
  bet of the day was placed before midnight and settled after it is in different days.
- Suggested acceptance: "Without FS" = exact Backoffice player count (per-player table) per day, tolerance
  ≤ 0.1%; against the Backoffice screen, the tolerance of its approximate count (≤ 0.5% per day).
