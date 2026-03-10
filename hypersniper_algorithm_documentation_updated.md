# HyperSniper Trading Algorithm — Technical Documentation

## 1. Overview

HyperSniper is a multi-factor algorithmic trading decision engine
designed to detect high‑probability trading opportunities in
cryptocurrency derivatives markets.

The system combines:

- Technical indicators
- Multi‑timeframe analysis
- Market structure signals
- Volatility filters
- Microstructure signals

Final decisions returned by the algorithm:

- **LONG**
- **SHORT**
- **NO TRADE**

Primary timeframe: **1H candles**

Confirmation timeframes: **4H**, **1D**

---

## 2. Algorithm Pipeline

Processing stages:

1. Market data ingestion
2. Indicator calculation
3. Signal scoring
4. Market regime detection
5. Risk filtering
6. Decision engine
7. Trade signal output

---

## 3. Algorithm Flowchart

> 📎 **Interactive flowchart:** see `hypersniper_flowchart.html`

The decision engine processes market data through the following stages:

```
Market Data Input
       │
       ▼
Calculate Indicators
  ┌────┬────┬────┬────┬────┬────┬────┐
  EMA  MACD RSI STOCH  BB  OBV  ADX  FVG
  └────┴────┴────┴────┴────┴────┴────┘
       │
       ▼
Signal Scoring Engine  (weighted composite score)
       │
       ▼
Multi-Timeframe Confirmation  [1H · 4H · 1D]
       │
       ▼
Market Regime Detection
       │
   ADX > 30?
   ┌───┴───┐
  YES      NO
   │        │
TREND    RANGE
MODE      MODE
(std thr) (strict thr)
   └───┬───┘
       │
       ▼
Risk Filters
  [Volume · Funding · HTF · Volatility · Session · BTC Veto]
       │
  Passed?
  ┌────┴────┐
 YES       NO
  │         │
Score    NO TRADE
≥ LONG?
  ├─YES──▶ OPEN LONG
  │
  └─NO──▶ Score ≤ SHORT?
            ├─YES──▶ OPEN SHORT
            └─NO───▶ NO TRADE
                │
                ▼
         Trade Execution
     [NO_OPEN=0 · LONG=1 · SHORT=2]
```

---

## 4. Technical Indicators

### EMA Stack

| EMA | Period |
|-----|--------|
| EMA Fast | 9 |
| EMA Medium | 21 |
| EMA Slow | 50 |
| EMA Macro | 200 |

**Bullish stack:** `EMA9 > EMA21 > EMA50`  
**Bearish stack:** `EMA9 < EMA21 < EMA50`  
**Macro trend:** `EMA50 > EMA200` → bullish · `EMA50 < EMA200` → bearish

---

### MACD

```
MACD   = EMA12 − EMA26
Signal = EMA9(MACD)
```

Signals detected:

- Momentum expansion
- Momentum weakening
- Bullish divergence
- Bearish divergence

---

### RSI

```
RSI = 100 − (100 / (1 + RS))
```

| Zone | Value |
|------|-------|
| Overbought | RSI > 75 |
| Oversold | RSI < 25 |

---

### Stochastic Oscillator

Used for:

- Momentum shifts
- Reversal detection
- Overbought / oversold signals
- Crossover signals

---

### Bollinger Bands

```
Upper = SMA + k·σ
Lower = SMA − k·σ
```

Where `σ` = standard deviation, `k` = 2 (default)

Signals:

- Bollinger squeeze
- Volatility breakout
- Mean reversion

---

### OBV (On Balance Volume)

```
OBV(t) = OBV(t−1) + Volume   if Close↑
OBV(t) = OBV(t−1) − Volume   if Close↓
```

Used for: accumulation · distribution · divergence analysis

---

### ADX — Trend Strength

| Threshold | Meaning |
|-----------|---------|
| ADX > 25 | Strong trend |
| ADX > 30 | Algorithm TREND MODE trigger |

---

### Supertrend

Trend‑following indicator based on ATR.

States: **BULL** · **BEAR** · **NEUTRAL**

---

### CHOP Index

| Value | Regime |
|-------|--------|
| CHOP < 38 | Trending market |
| CHOP > 61 | Ranging market |

---

### Fair Value Gap (FVG)

Detects liquidity imbalance zones.

- **Bullish FVG** → upward imbalance
- **Bearish FVG** → downward imbalance

Used for: liquidity zones · entry optimization · smart money imbalance detection

---

## 5. Score Engine

Each indicator contributes a weighted score to the final decision value:

```
Score = (EMA × 2) + (MACD × 2) + RSI + Stochastic + Bollinger
      + OBV + FVG + ADX + CHOP + Microstructure
```

---

## 6. Market Regime Detection

### TREND MODE

Activated when: `ADX > 30`

- LONG if `Score ≥ threshold`
- SHORT if `Score ≤ −threshold`

### RANGE MODE

Activated when: `ADX ≤ 30`

- Stricter thresholds applied
- Stronger confirmation required

---

## 7. Microstructure Signals

| Signal | Meaning |
|--------|---------|
| OrderBookImbalance (OBI) | Buy vs. sell pressure |
| VD Ratio | Aggressive trading activity |
| Open Interest | Position buildup |
| Funding Rate | Market crowding |

**Thresholds:**

- `OBI > 1.3` → strong buy pressure
- `OBI < 0.7` → strong sell pressure

---

## 8. Risk Filters

Trades are blocked when any of the following conditions are met:

| Filter | Condition |
|--------|-----------|
| Volume | Market volume too low |
| Funding Rate | Extreme funding rate |
| HTF Conflict | Higher timeframe directional conflict |
| Volatility | Abnormal volatility spike |
| Session | Trading session filter fails |
| BTC Correlation | BTC correlation veto triggered |

---

## 9. Decision Engine

**Possible outputs:**

| Signal | Value |
|--------|-------|
| NO_OPEN | 0 |
| LONG_POS | 1 |
| SHORT_POS | 2 |

**Decision sequence:**

1. Calculate indicators
2. Compute total score
3. Detect market regime
4. Apply thresholds
5. Run risk filters
6. Return trading signal
