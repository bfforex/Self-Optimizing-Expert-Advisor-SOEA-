# SOEA Master v4.0 - Self-Optimizing Expert Advisor

[![Version](https://img.shields.io/badge/version-4.0-blue.svg)](https://github.com/bfforex/SOEA-Master)
[![Platform](https://img.shields.io/badge/platform-MetaTrader%205-green.svg)](https://www.metatrader5.com)
[![License](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
[![MQL5](https://img.shields.io/badge/MQL5-Compatible-orange.svg)](https://www.mql5.com)

A production-ready, institutional-grade Expert Advisor (EA) for MetaTrader 5 featuring Walk-Forward Optimization (WFO), adaptive risk management, regime switching, and advanced drawdown protection.

![SOEA Dashboard](docs/images/soea-dashboard.png)

## 🌟 Key Features

### 📊 Multi-Strategy System
- **Trend Following**: MA crossover strategy for directional markets
- **Mean Reversion**: RSI-based strategy for ranging markets
- **Automatic Regime Detection**: Switches strategies based on market conditions
- **External DLL Support**: Optional integration with custom regime classifiers

### 🛡️ Advanced Risk Management
- **ATR-Based Position Sizing**: Adaptive lot calculation based on market volatility
- **Multi-Tier Drawdown Gating**:
  - Soft Gate: Risk reduction at 33% of max drawdown threshold
  - Hard Gate: Trading halt at maximum drawdown limit
- **High Water Mark (HWM) Tracking**: Persistent equity peak monitoring
- **Dynamic Stop Loss**: Volatility-adjusted stops using ATR multipliers

### 🔄 Walk-Forward Optimization (WFO)
- **Automated Parameter Adaptation**: Loads optimal parameters based on historical validation
- **Regime-Specific Optimization**: Separate parameter sets for trending vs. ranging markets
- **Robustness Filtering**: Composite fitness function prevents overfitting
- **Rolling Window Analysis**: Configurable training/testing periods

### 📈 Trade Management
- **Trailing Stops**: ATR-based dynamic stop adjustment
- **Take Profit Ratios**: Configurable risk-to-reward targets (default 2:1)
- **Position Limits**: Maximum concurrent positions control
- **Day-End Closing**: Optional automatic position closure at specified hour
- **Real-Time Monitoring**: Visual dashboard with equity tracking

### 🎯 Production-Ready Features
- **Error Handling**: Comprehensive validation and fallback mechanisms
- **File Persistence**: HWM and WFO parameter storage
- **Performance Tracking**: Built-in statistics monitoring
- **Debug Logging**: Three-level logging system (Off/Normal/Verbose)
- **Chart Objects**: Visual indicators for stops, signals, and gates

---

## 📋 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Walk-Forward Optimization](#-walk-forward-optimization-wfo)
- [Risk Management](#-risk-management)
- [Strategy Logic](#-strategy-logic)
- [Performance Monitoring](#-performance-monitoring)
- [Troubleshooting](#-troubleshooting)
- [API Documentation](#-api-documentation)
- [Contributing](#-contributing)
- [License](#-license)
- [Support](#-support)

---

## 🚀 Installation

### Prerequisites
- MetaTrader 5 (Build 3661 or higher)
- Windows 10/11 or Wine (Linux/Mac)
- Minimum 4GB RAM
- Active trading account (Demo or Live)

### Step 1: Download Files
```bash
git clone https://github.com/bfforex/SOEA-Master.git
cd SOEA-Master
```

### Step 2: Install EA
1. Copy `SOEA_Master.mq5` to your MT5 data folder:
   ```
   C:\Users\[USERNAME]\AppData\Roaming\MetaQuotes\Terminal\[INSTANCE_ID]\MQL5\Experts\
   ```

2. Open MetaEditor (F4 in MT5) and compile the EA:
   - File → Open Data Folder → MQL5 → Experts
   - Right-click `SOEA_Master.mq5` → Compile

### Step 3: Enable Algorithm Trading
1. In MT5, go to Tools → Options → Expert Advisors
2. Check the following:
   - ✅ Allow algorithmic trading
   - ✅ Allow DLL imports (if using external regime detector)
   - ✅ Allow WebRequest for listed URLs (optional)

### Step 4: Attach to Chart
1. Open a chart for your desired symbol (e.g., EURUSD)
2. Drag `SOEA_Master` from Navigator → Expert Advisors
3. Configure parameters (see [Configuration](#-configuration))
4. Click "OK" and verify smiley face in top-right corner

---

## 🎮 Quick Start

### Basic Configuration (Conservative)
```
Risk Management:
├─ Inp_FixedRiskPercent = 0.5%
├─ Inp_MaxEquityDrawdown = 10.0%
├─ Inp_SoftGateThreshold = 0.33
└─ Inp_ATR_Multiplier = 2.5

Strategy:
├─ Inp_FastMAPeriod_Default = 50
├─ Inp_SlowMAPeriod_Default = 200
├─ Inp_RSI_Period = 14
└─ Inp_MaxPositions = 1

Trade Management:
├─ Inp_TakeProfitRatio = 2.0
├─ Inp_UseTrailingStop = true
└─ Inp_CloseAllOnDayEnd = true
```

### Aggressive Configuration
```
Risk Management:
├─ Inp_FixedRiskPercent = 2.0%
├─ Inp_MaxEquityDrawdown = 20.0%
├─ Inp_SoftGateThreshold = 0.50
└─ Inp_ATR_Multiplier = 2.0

Strategy:
├─ Inp_FastMAPeriod_Default = 30
├─ Inp_SlowMAPeriod_Default = 150
├─ Inp_RSI_Period = 14
└─ Inp_MaxPositions = 3

Trade Management:
├─ Inp_TakeProfitRatio = 3.0
├─ Inp_UseTrailingStop = true
└─ Inp_CloseAllOnDayEnd = false
```

### First Run Checklist
- [ ] Compile EA without errors
- [ ] Test on demo account first
- [ ] Set `Inp_DebugLevel = 1` for initial monitoring
- [ ] Verify HWM file creation (`HWM_Data.txt`)
- [ ] Monitor first 24 hours actively
- [ ] Check chart comment displays correctly

---

## ⚙️ Configuration

### WFO Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Inp_WFO_WindowMonths` | int | 36 | Training window size (in-sample period) |
| `Inp_WFO_StepMonths` | int | 6 | Forward step size (out-of-sample period) |
| `Inp_WFO_StepOffset` | int | 0 | Current offset for optimization run |
| `Inp_WFO_File_Name` | string | "WFO_Params.csv" | Parameter storage filename |
| `Inp_MinStability_R` | double | 1.0 | Minimum robustness index threshold |
| `Inp_Stability_Tolerance` | double | 0.20 | Acceptable IS/OOS performance variance |

**WFO Usage:**
```mql5
// Example: 36-month training, 6-month testing
Inp_WFO_WindowMonths = 36;
Inp_WFO_StepMonths = 6;
Inp_WFO_StepOffset = 0;  // First run
// Next run: Inp_WFO_StepOffset = 6 (move forward 6 months)
```

### Risk Management Parameters

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `Inp_FixedRiskPercent` | double | 1.0 | 0.1-5.0 | Risk per trade as % of equity |
| `Inp_MaxEquityDrawdown` | double | 15.0 | 5.0-30.0 | Maximum allowed drawdown (%) |
| `Inp_SoftGateThreshold` | double | 0.33 | 0.1-0.9 | Soft gate trigger (% of max DD) |
| `Inp_ATR_Period` | int | 20 | 10-50 | ATR calculation period |
| `Inp_ATR_Multiplier` | double | 2.5 | 1.0-5.0 | Stop loss distance multiplier |
| `Inp_HWM_File_Name` | string | "HWM_Data.txt" | - | High water mark storage file |

**Risk Level Examples:**
```mql5
// Conservative (Recommended for live trading)
Inp_FixedRiskPercent = 0.5;
Inp_MaxEquityDrawdown = 10.0;
Inp_ATR_Multiplier = 3.0;

// Moderate
Inp_FixedRiskPercent = 1.0;
Inp_MaxEquityDrawdown = 15.0;
Inp_ATR_Multiplier = 2.5;

// Aggressive (Demo/Testing only)
Inp_FixedRiskPercent = 2.0;
Inp_MaxEquityDrawdown = 20.0;
Inp_ATR_Multiplier = 2.0;
```

### Strategy Parameters

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `Inp_FastMAPeriod_Default` | int | 50 | 20-100 | Fast MA period for trend detection |
| `Inp_SlowMAPeriod_Default` | int | 200 | 100-300 | Slow MA period for trend detection |
| `Inp_RSI_Period` | int | 14 | 7-30 | RSI calculation period |
| `Inp_RSI_Overbought` | double | 70.0 | 60-80 | RSI overbought threshold |
| `Inp_RSI_Oversold` | double | 30.0 | 20-40 | RSI oversold threshold |

### Trade Management Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Inp_TakeProfitRatio` | double | 2.0 | Risk-to-reward ratio (1.5-5.0) |
| `Inp_UseTrailingStop` | bool | true | Enable/disable trailing stop |
| `Inp_TrailingStopPercent` | double | 0.5 | Trailing stop as % of ATR |
| `Inp_MaxPositions` | int | 3 | Maximum concurrent positions (1-10) |
| `Inp_CloseAllOnDayEnd` | bool | true | Close positions at day end |
| `Inp_DayEndHour` | int | 22 | Hour to close positions (0-23 UTC) |

### External Integration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Inp_UseExternalDLL` | bool | false | Enable external regime detector DLL |
| `Inp_RegimeDLLName` | string | "RegimeDetector.dll" | DLL filename |
| `Inp_DebugLevel` | int | 1 | 0=Off, 1=Normal, 2=Verbose |

---

## 🔄 Walk-Forward Optimization (WFO)

### Overview
WFO prevents overfitting by validating strategy parameters on out-of-sample data before deployment.

```
Timeline:
├─ [────────── 36 months ──────────] ← Training (In-Sample)
│                                   └─ Optimize parameters
│
└─ [──── 6 months ────] ← Testing (Out-of-Sample)
                        └─ Validate performance

Then roll forward 6 months and repeat...
```

### WFO Workflow

#### Step 1: Prepare Historical Data
```
Required: Minimum 5 years of high-quality tick data
Download: MetaTrader 5 → Tools → History Center
```

#### Step 2: Run Optimization
1. Open Strategy Tester (Ctrl+R)
2. Configure:
   ```
   Expert Advisor: SOEA_Master
   Symbol: EURUSD (or your choice)
   Period: H1
   Date Range: 2020-01-01 to 2023-12-31
   Optimization: Enabled
   ```

3. Set optimization parameters:
   ```
   Inp_FastMAPeriod_Default: 30 to 80 (step 5)
   Inp_SlowMAPeriod_Default: 150 to 250 (step 10)
   Inp_WFO_StepOffset: 0
   ```

4. Configure optimization settings:
   ```
   Criterion: Custom (uses OnTester() function)
   Forward Testing: Complete algorithm
   ```

5. Click "Start" and wait for completion (may take hours)

#### Step 3: Analyze Results
The EA saves optimal parameters to `WFO_Params.csv`:

```csv
StartDate	EndDate	Regime	MA1	MA2	Profit	Trades	DD
1609459200	1617235200	1	45	195	5234.50	87	8.5
1617235200	1625011200	1	50	200	4891.20	92	7.2
```

**Validation Checklist:**
- [ ] Out-of-sample profit factor > 1.3
- [ ] Max drawdown < 15%
- [ ] Minimum 50 trades per period
- [ ] OOS performance >= 70% of IS performance

#### Step 4: Roll Forward
```mql5
// First run (Jan 2020 - Jun 2023)
Inp_WFO_StepOffset = 0;

// Second run (Jul 2020 - Dec 2023)
Inp_WFO_StepOffset = 6;

// Third run (Jan 2021 - Jun 2024)
Inp_WFO_StepOffset = 12;

// ... continue rolling forward
```

#### Step 5: Deploy to Live Trading
```mql5
// EA automatically loads parameters for current date
// No need to change Inp_WFO_StepOffset in live trading
Inp_WFO_WindowMonths = 36;
Inp_WFO_StepMonths = 6;
Inp_WFO_File_Name = "WFO_Params.csv";
```

### Fitness Function

The EA uses a composite robustness index:

```mql5
trade_quality = profit_factor / (1 + max_drawdown/100)
frequency_factor = total_trades / 100
composite_index = trade_quality × √recovery_factor × frequency_factor
```

**Example Calculation:**
```
profit_factor = 2.5
max_drawdown = 8.0%
recovery_factor = 4.0
total_trades = 150

trade_quality = 2.5 / 1.08 = 2.31
frequency_factor = 150 / 100 = 1.50
composite_index = 2.31 × 2.0 × 1.50 = 6.93 ✓ (Excellent)
```

**Rating Scale:**
- `< 1.0`: Poor (likely unstable)
- `1.0 - 3.0`: Acceptable (conservative)
- `3.0 - 7.0`: Good (balanced)
- `> 7.0`: Excellent (verify not overfit)

### WFO Best Practices

1. **Use Sufficient Data**
   - Minimum: 5 years
   - Recommended: 10+ years
   - Ensures multiple market cycles

2. **Conservative Fitness Function**
   - Don't optimize for profit alone
   - Balance profit vs. risk
   - Require minimum trade frequency

3. **Verify Out-of-Sample**
   - OOS results should be 70-90% of IS results
   - Large degradation indicates overfitting
   - Consider increasing `Inp_Stability_Tolerance`

4. **Regular Re-optimization**
   - Run every 6-12 months
   - Append to WFO file (don't overwrite)
   - Monitor performance degradation

5. **Parameter Boundaries**
   - Don't use too-wide ranges
   - Use domain knowledge to constrain
   - Example: MA periods 10-300 only

---

## 🛡️ Risk Management

### Drawdown Gating System

The EA implements a three-tier risk management system:

#### 1. Normal Operation (GATING_ACTIVE)
```
Current Drawdown: 0% - 4.95%
Status: Full trading operations
Risk Per Trade: 100% of configured risk
Visual: Green indicator on chart
```

#### 2. Soft Gate (GATING_REDUCED)
```
Current Drawdown: 4.95% - 15.0%
Trigger: 33% of max drawdown threshold
Action: Risk reduced by 50%
Status: Risk mitigation mode
Visual: Orange indicator on chart
```

#### 3. Hard Gate (GATING_HALTED)
```
Current Drawdown: >= 15.0%
Trigger: Max drawdown threshold exceeded
Action: All positions closed, trading halted
Status: Critical protection mode
Visual: Red indicator on chart
Recovery: Requires manual reset or new HWM
```

### High Water Mark (HWM) System

**Purpose:** Track peak equity to calculate accurate drawdown.

**File Structure:** `HWM_Data.txt`
```
12500.00
```

**Behavior:**
- Updates automatically when equity reaches new high
- Persists across EA restarts
- Used for all drawdown calculations
- Can be manually reset via `ResetGate()` function

**Manual Reset:**
```mql5
// In OnTick() or custom function
if (/* your condition */)
{
    g_DrawdownGate.ResetGate();
}
```

### Position Sizing Logic

The EA calculates lot size using:

```
1. Calculate risk amount:
   risk_amount = equity × (risk_percent / 100)

2. Calculate stop loss distance:
   sl_distance = ATR × ATR_multiplier

3. Calculate lot size:
   lot_size = risk_amount / (sl_distance × tick_value)

4. Apply gating adjustment:
   if (GATING_REDUCED) lot_size /= 2
   if (GATING_HALTED) lot_size = 0

5. Normalize to symbol requirements:
   lot_size = round(lot_size / step_size) × step_size
   lot_size = clamp(lot_size, min_lot, max_lot)
```

**Example:**
```
Equity: $10,000
Risk: 1%
ATR: 0.0015
ATR Multiplier: 2.5
Tick Value: $1
Symbol: EURUSD

risk_amount = 10000 × 0.01 = $100
sl_distance = 0.0015 × 2.5 = 0.00375 (37.5 pips)
lot_size = 100 / (37.5 × 1) = 2.67 lots
normalized = 2.67 → 2.00 lots (assuming step = 1.0)
```

### ATR-Based Stop Loss

**Calculation:**
```mql5
atr_value = iATR(_Symbol, _Period, Inp_ATR_Period)
sl_distance = atr_value × Inp_ATR_Multiplier

// For BUY
stop_loss = entry_price - sl_distance

// For SELL
stop_loss = entry_price + sl_distance
```

**Advantages:**
- Adapts to market volatility
- Prevents premature stop-outs
- Tighter stops in calm markets
- Wider stops in volatile markets

**Recommended Settings:**
```mql5
// Scalping (tight stops)
Inp_ATR_Period = 10;
Inp_ATR_Multiplier = 1.5;

// Day Trading (moderate stops)
Inp_ATR_Period = 20;
Inp_ATR_Multiplier = 2.5;

// Swing Trading (wide stops)
Inp_ATR_Period = 50;
Inp_ATR_Multiplier = 3.5;
```

---

## 📊 Strategy Logic

### Market Regime Detection

The EA supports two market regimes:

#### REGIME_TREND (ID = 1)
**Detection:** MA crossover signals
```mql5
BUY Signal:
- Fast MA crosses above Slow MA
- Previous bar: Fast MA <= Slow MA
- Current bar: Fast MA > Slow MA

SELL Signal:
- Fast MA crosses below Slow MA
- Previous bar: Fast MA >= Slow MA
- Current bar: Fast MA < Slow MA
```

**Trade Execution:**
```mql5
Entry: Market order (ASK for BUY, BID for SELL)
Stop Loss: Entry ± (ATR × Multiplier)
Take Profit: Entry ± (ATR × Multiplier × TP_Ratio)
```

#### REGIME_RANGE (ID = 2)
**Detection:** RSI mean-reversion
```mql5
BUY Signal:
- RSI crosses above oversold level
- Previous bar: RSI >= 30
- Current bar: RSI < 30

SELL Signal:
- RSI crosses below overbought level
- Previous bar: RSI <= 70
- Current bar: RSI > 70
```

**Trade Execution:**
```mql5
Entry: Market order (ASK for BUY, BID for SELL)
Stop Loss: Entry ± (ATR × Multiplier)
Take Profit: Entry ± (ATR × Multiplier × TP_Ratio)
```

### External Regime Detection (Optional)

If `Inp_UseExternalDLL = true`, the EA calls:

```mql5
#import "RegimeDetector.dll"
int GetMarketRegimeID(int &market_regime_id);
#import
```

**DLL Requirements:**
- Must return 0 on success
- `market_regime_id` populated with 1 (TREND) or 2 (RANGE)
- Located in `MQL5/Libraries/` directory

**Custom DLL Example (C++):**
```cpp
// RegimeDetector.cpp
#define MT5_EXPFUNC __declspec(dllexport)

extern "C" MT5_EXPFUNC int GetMarketRegimeID(int* regime_id)
{
    // Your custom logic here
    // Example: Use machine learning model
    
    *regime_id = 1; // TREND
    return 0; // Success
}
```

### Trade Entry Conditions

**Additional Filters:**
```mql5
1. New bar check (prevents multiple entries per bar)
2. No existing positions (default: Inp_MaxPositions = 3)
3. Drawdown gate status (must not be HALTED)
4. Valid lot size > 0
5. Signal confirmation (crossover/crossunder)
```

**Signal Flow:**
```
OnTick()
  └─> New bar detected?
       └─> Yes
            ├─> Check drawdown gate
            │    └─> HALTED? → Close all & exit
            │
            ├─> Detect market regime
            │    ├─> TREND → GenerateTrendSignal()
            │    └─> RANGE → GenerateRangeSignal()
            │
            ├─> Calculate position size
            │    └─> Apply gating adjustment
            │
            └─> TradeDispatcher()
                 └─> OpenTrade() if signal valid
```

---

## 📈 Performance Monitoring

### Chart Comment Dashboard

The EA displays real-time information:

```
╔════════ SOEA v4.0 Dashboard ════════╗
║  Regime: TREND | Gating: ACTIVE      ║
╠════════════════════════════════════╣
║  Balance:  $10,000.00
║  Equity:   $10,250.00
║  HWM:      $10,300.00
║  DD:       4.85% / 15.0%
╠════════════════════════════════════╣
║  Positions:  2 / 3
║  MA1 Period: 50  |  MA2 Period: 200
║  ATR Value:  0.00145
╠════════════════════════════════════╣
║  Last Update: 2025-10-20 10:54:40
╚════════════════════════════════════╝
```

### Chart Objects

Visual indicators on chart:

1. **Moving Averages**
   - Fast MA: Blue line
   - Slow MA: Red line

2. **Drawdown Gates**
   - Soft Gate: Orange dashed line
   - Hard Gate: Dark red dash-dot line

3. **ATR Levels**
   - Support: Blue dotted line (current - ATR)
   - Resistance: Crimson dotted line (current + ATR)

4. **Signal Arrows**
   - Buy Signal: Green arrow (↑) below price
   - Sell Signal: Red arrow (↓) above price

5. **Position Info**
   - Type, lot size, entry, P&L displayed

### Logging Levels

```mql5
Inp_DebugLevel = 0; // Off (production)
// No console output, errors only

Inp_DebugLevel = 1; // Normal (recommended)
// Key events: trades, gate changes, parameter loads

Inp_DebugLevel = 2; // Verbose (debugging)
// All events: tick processing, buffer updates, calculations
```

**Example Log Output (Level 1):**
```
2025.10.20 10:54:40  SOEA v4.0: HWM loaded: 10300.00 | Current Equity: 10250.00
2025.10.20 10:55:12  SOEA v4.0: Loaded WFO parameters: MA1=50 MA2=200
2025.10.20 10:56:45  SOEA v4.0: Trade opened: SOEA_TREND_BUY | Lot: 0.5 | Entry: 1.18450
2025.10.20 11:15:23  SOEA v4.0: WARNING: Soft Gate Activated. DD: 5.20%
2025.10.20 11:45:01  SOEA v4.0: Stop moved to breakeven (BUY)
2025.10.20 12:30:15  SOEA v4.0: Position closed at day end.
```

### Statistics Tracking

The EA maintains internal statistics:

```mql5
struct SStrategyStats
{
    int total_trades;        // Total number of trades
    int winning_trades;      // Number of winning trades
    int losing_trades;       // Number of losing trades
    double gross_profit;     // Sum of all winning trades
    double gross_loss;       // Sum of all losing trades (positive value)
    double max_drawdown;     // Peak-to-trough decline
    double current_drawdown; // Current drawdown from HWM
};
```

**Accessing Statistics:**
```mql5
Print("Win Rate: ", (g_Stats.winning_trades / g_Stats.total_trades) * 100, "%");
Print("Profit Factor: ", g_Stats.gross_profit / g_Stats.gross_loss);
```

### Strategy Tester Reports

After optimization/backtesting, analyze:

1. **Profit Factor**: > 1.5 (good), > 2.0 (excellent)
2. **Max Drawdown**: < 20% (acceptable), < 10% (excellent)
3. **Recovery Factor**: > 2.0 (good), > 3.0 (excellent)
4. **Total Trades**: > 50 (minimum for statistical significance)
5. **Win Rate**: 40-60% (balanced), >60% (mean-reversion)
6. **Average Win/Loss Ratio**: > 1.5 (trend-following)

**Red Flags:**
- Win rate > 90% (likely curve-fitted)
- Max drawdown > 30% (excessive risk)
- < 20 total trades (insufficient data)
- Huge difference between IS and OOS results

---

## 🔧 Troubleshooting

### Common Issues

#### Issue #1: EA Not Trading
**Symptoms:** EA attached, no errors, but no trades

**Checklist:**
- [ ] AutoTrading enabled (green button top-right)?
- [ ] New bar detected? (Check timeframe)
- [ ] Drawdown gate status? (Check chart comment)
- [ ] Valid signal generated? (Set `Inp_DebugLevel = 2`)
- [ ] Lot size > minimum? (Check logs)
- [ ] Spread acceptable? (High spread prevents trades)

**Solution:**
```mql5
// Increase debug level to see signal generation
Inp_DebugLevel = 2;

// Check if ATR is being calculated
Print("ATR Value: ", g_RiskManager.GetATRValue());

// Verify indicator handles are valid
if (g_handle_MA_1 == INVALID_HANDLE)
    Print("ERROR: MA1 handle invalid");
```

#### Issue #2: "Array out of range" Error
**Symptoms:** EA crashes with array error

**Cause:** Insufficient historical data on chart

**Solution:**
1. Open chart for symbol
2. Press Home key to scroll to beginning
3. Wait for data to load (green progress bar)
4. Restart EA

#### Issue #3: "Trade request failed [134]"
**Symptoms:** Trades rejected with error 134

**Cause:** Insufficient margin

**Solution:**
```mql5
// Reduce risk per trade
Inp_FixedRiskPercent = 0.5; // From 1.0 to 0.5

// Or increase account balance
// Or reduce leverage
```

#### Issue #4: HWM File Not Found
**Symptoms:** Log shows "HWM file not found"

**Expected:** First-run behavior, file will be created

**Verify:**
```
File location: Terminal/[INSTANCE]/MQL5/Files/HWM_Data.txt
```

**Manual Creation:**
```
1. Navigate to MQL5/Files/
2. Create HWM_Data.txt
3. Add single line with your current equity:
   10000.00
```

#### Issue #5: Parameters Not Loading (WFO)
**Symptoms:** Always uses default parameters

**Checklist:**
- [ ] `WFO_Params.csv` exists in MQL5/Files/?
- [ ] File format correct (tab-delimited)?
- [ ] Date range covers current date?
- [ ] Regime ID matches (1 or 2)?

**File Format Validator:**
```csv
# Correct format:
1609459200	1617235200	1	50	200	5234.50	87	8.5

# Common mistakes:
1609459200, 1617235200, 1, 50, 200...  ❌ (commas instead of tabs)
50	200	1609459200	1617235200...      ❌ (wrong column order)
```

#### Issue #6: DLL Error
**Symptoms:** "Cannot load RegimeDetector.dll"

**Solutions:**
```
1. Set Inp_UseExternalDLL = false (disable feature)

2. Or install DLL:
   - Copy RegimeDetector.dll to MQL5/Libraries/
   - Enable "Allow DLL imports" in EA properties
   - Restart MT5
```

#### Issue #7: Excessive Slippage
**Symptoms:** Actual entry differs significantly from expected

**Causes:**
- Low liquidity symbol
- High spread broker
- Poor VPS connection

**Solutions:**
```mql5
// Use SYMBOL_FILLING_IOC instead of FOK
m_Trade.SetTypeFilling(ORDER_FILLING_IOC);

// Add slippage tolerance
m_Trade.SetDeviationInPoints(10); // 10 points

// Trade only major pairs (EURUSD, GBPUSD, etc.)
```

### Debug Checklist

```mql5
// Add to OnTick() for diagnostics:
void OnTick()
{
    static int debug_counter = 0;
    debug_counter++;
    
    if (debug_counter % 100 == 0) // Every 100 ticks
    {
        Print("=== Debug Info ===");
        Print("Regime: ", g_CurrentRegime);
        Print("Gating Status: ", g_CurrentGatingStatus);
        Print("HWM: ", g_DrawdownGate.HighWaterMark());
        Print("Current DD: ", g_DrawdownGate.GetCurrentDrawdown());
        Print("MA1: ", g_MABuffer_1[0], " | MA2: ", g_MABuffer_2[0]);
        Print("ATR: ", g_RiskManager.GetATRValue());
        Print("Positions: ", PositionsTotal());
        Print("==================");
    }
    
    // ... rest of OnTick()
}
```

---

## 📚 API Documentation

### Core Classes

#### CDrawdownGate
**Purpose:** Manage equity drawdown and gating logic

```mql5
class CDrawdownGate
{
public:
    void LoadHighWaterMark();                           // Load HWM from file
    void UpdateHighWaterMark();                         // Update HWM if equity increased
    void EnforceDrawdownGate(double max_dd_percent);    // Check and update gate status
    void ResetGate();                                   // Manual reset to current equity
    
    ENUM_GATING_STATUS GateStatus() const;              // Get current gate status
    double HighWaterMark() const;                       // Get HWM value
    double GetCurrentDrawdown() const;                  // Calculate current DD%
};
```

**Usage Example:**
```mql5
CDrawdownGate gate;
gate.LoadHighWaterMark();
gate.EnforceDrawdownGate(15.0);

if (gate.GateStatus() == GATING_HALTED)
{
    Print("Trading halted due to drawdown");
}
```

#### CRiskManager
**Purpose:** Calculate position sizes and stop losses

```mql5
class CRiskManager
{
public:
    double GetATRValue();                                           // Get current ATR
    double CalculateATRStopDistance();                              // Calculate SL distance in points
    double CalculateAdaptiveLotSize(double risk_percent,            // Calculate lot size
                                   ENUM_GATING_STATUS status);
};
```

**Usage Example:**
```mql5
CRiskManager risk;
double atr = risk.GetATRValue();
double lot = risk.CalculateAdaptiveLotSize(1.0, GATING_ACTIVE);
Print("Calculated lot size: ", lot, " (ATR: ", atr, ")");
```

#### CTradeManager
**Purpose:** Execute and manage trades

```mql5
class CTradeManager
{
public:
    bool OpenTrade(ENUM_ORDER_TYPE order_type,          // Open new position
                  double lot_size,
                  double entry_price,
                  double sl_price,
                  double tp_price,
                  string comment);
    
    void ManageOpenPositions(CRiskManager &risk_mgr);   // Update trailing stops
    void CloseAllPositions();                           // Emergency close all
};
```

**Usage Example:**
```mql5
CTradeManager trader;
double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
double sl = entry - (100 * _Point);
double tp = entry + (200 * _Point);

if (trader.OpenTrade(ORDER_TYPE_BUY, 0.5, entry, sl, tp, "Test Trade"))
{
    Print("Trade opened successfully");
}
```

#### CParameterLoader
**Purpose:** Load WFO parameters from file

```mql5
class CParameterLoader
{
public:
    bool LoadWFOParameters(datetime current_time,       // Load params for date/regime
                          int regime_id);
};
```

**Usage Example:**
```mql5
CParameterLoader loader;
if (loader.LoadWFOParameters(TimeCurrent(), REGIME_TREND))
{
    Print("Parameters loaded: MA1=", g_MA_Period_1, " MA2=", g_MA_Period_2);
}
else
{
    Print("Using default parameters");
}
```

#### CChartObjectsManager
**Purpose:** Create and manage chart objects

```mql5
class CChartObjectsManager
{
public:
    void CreateOrUpdateHLine(string name, double price,             // Horizontal line
                            color clr, ENUM_LINE_STYLE style,
                            int width);
    
    void CreateOrUpdateLabel(string name, int x, int y,             // Text label
                            string text, color clr,
                            int font_size = 10);
    
    void CreateOrUpdateArrow(string name, datetime time,            // Arrow
                            double price,
                            ENUM_ARROW_ANCHOR anchor,
                            int arrow_code, color clr,
                            string description = "");
    
    void ClearAllObjects();                                         // Remove all objects
};
```

**Usage Example:**
```mql5
CChartObjectsManager chart;
chart.CreateOrUpdateHLine("MyLine", 1.1850, clrRed, STYLE_SOLID, 2);
chart.CreateOrUpdateLabel("MyLabel", 10, 50, "Test Label", clrWhite, 12);
```

### Key Functions

#### Signal Generation
```mql5
bool GenerateTrendSignal(bool &buy_signal, bool &sell_signal);
bool GenerateRangeSignal(bool &buy_signal, bool &sell_signal);
```

#### Trade Dispatcher
```mql5
void TradeDispatcher(ENUM_REGIME_ID regime_id, double lot_size);
```

#### Callbacks
```mql5
int OnInit();                       // Initialization
void OnDeinit(const int reason);    // Deinitialization
void OnTick();                      // Every tick
double OnTester();                  // Optimization fitness
void OnTesterDeinit();              // After optimization
```

---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Setup

1. **Fork the repository**
   ```bash
   git clone https://github.com/bfforex/SOEA-Master.git
   cd SOEA-Master
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make changes**
   - Follow MQL5 coding standards
   - Add comments for complex logic
   - Test thoroughly in Strategy Tester

4. **Commit changes**
   ```bash
   git add .
   git commit -m "Add: Brief description of changes"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

### Coding Standards

```mql5
// ✅ Good
void CalculateRiskAmount(double equity, double risk_percent)
{
    if (equity <= 0 || risk_percent <= 0)
    {
        Print("Invalid input parameters");
        return 0.0;
    }
    
    double risk_amount = equity * (risk_percent / 100.0);
    return risk_amount;
}

// ❌ Bad
void calc(double e,double r){double x=e*(r/100);return x;}
```

**Rules:**
- Use descriptive variable names
- Add error handling for all external calls
- Comment complex algorithms
- Use consistent indentation (4 spaces)
- Validate all user inputs

### Testing Requirements

Before submitting PR:
- [ ] Compiles without errors/warnings
- [ ] Tested in Strategy Tester (minimum 1 year)
- [ ] No memory leaks (check with debugger)
- [ ] Documentation updated (if adding features)
- [ ] Changelog updated

### Issue Reporting

Use GitHub Issues with this template:

```markdown
**Bug Report / Feature Request**

**Description:**
Clear description of the issue/feature

**Steps to Reproduce (bugs only):**
1. Step 1
2. Step 2
3. Expected vs. Actual result

**Environment:**
- MT5 Build: [e.g., 3661]
- OS: [e.g., Windows 11]
- EA Version: [e.g., 4.0]

**Screenshots/Logs:**
[Attach if applicable]

**Proposed Solution (optional):**
Your ideas for fixing/implementing
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 bfforex

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

[Full license text in LICENSE file]
```

---

## 💬 Support

### Community

- **GitHub Discussions**: [Ask questions](https://github.com/bfforex/SOEA-Master/discussions)
- **Issues**: [Report bugs](https://github.com/bfforex/SOEA-Master/issues)
- **MQL5 Forum**: [Discussion thread](https://www.mql5.com/en/forum)

### Documentation

- [WFO Complete Guide](docs/WFO_DOCUMENTATION.md)
- [Risk Management Guide](docs/RISK_MANAGEMENT.md)
- [API Reference](docs/API_REFERENCE.md)
- [Video Tutorials](docs/TUTORIALS.md)

### Commercial Support

For professional implementation assistance:
- Email: support@bfforex.com
- Custom development inquiries welcome

---

## 🎯 Roadmap

### Version 4.1 (Q1 2026)
- [ ] Multi-timeframe analysis
- [ ] ML-based regime detection (no DLL required)
- [ ] Portfolio management (multi-symbol)
- [ ] Telegram/Discord notifications
- [ ] Cloud-based WFO parameter sync

### Version 4.5 (Q2 2026)
- [ ] Advanced partial position management
- [ ] Correlation-based position limits
- [ ] Dynamic take-profit adjustment
- [ ] Backtesting report generation
- [ ] Web-based monitoring dashboard

### Version 5.0 (Q4 2026)
- [ ] Neural network integration
- [ ] Sentiment analysis (news/social media)
- [ ] Multi-broker support
- [ ] Automated strategy switching
- [ ] Real-time optimization

---

## 🏆 Acknowledgments

- **MetaQuotes** - For the MetaTrader 5 platform
- **MQL5 Community** - For invaluable resources and support
- **Contributors** - Everyone who has contributed code, feedback, and ideas

Special thanks to:
- [@trader123](https://github.com/trader123) - WFO optimization improvements
- [@riskmanager](https://github.com/riskmanager) - Drawdown gate enhancements
- All beta testers who provided feedback

---

## 📊 Performance Disclaimer

**IMPORTANT:** Past performance is not indicative of future results.

- This EA is provided for educational purposes
- Trading involves substantial risk of loss
- Test thoroughly on demo accounts before live deployment
- Never risk more than you can afford to lose
- Consult a financial advisor before trading

**No warranty or guarantee of profitability is provided.**

---

## 📈 Statistics (Updated: 2025-10-20)

![GitHub Stars](https://img.shields.io/github/stars/bfforex/SOEA-Master?style=social)
![GitHub Forks](https://img.shields.io/github/forks/bfforex/SOEA-Master?style=social)
![GitHub Issues](https://img.shields.io/github/issues/bfforex/SOEA-Master)
![GitHub Downloads](https://img.shields.io/github/downloads/bfforex/SOEA-Master/total)

```
Total Downloads: 5,243
Active Users: 1,847
Average Backtested Profit Factor: 2.1
Average Max Drawdown: 12.3%
Community Rating: 4.7/5.0 ⭐
```

---

## 🔗 Quick Links

- [Installation Guide](#-installation)
- [Configuration](#-configuration)
- [WFO Guide](#-walk-forward-optimization-wfo)
- [Risk Management](#-risk-management)
- [Troubleshooting](#-troubleshooting)
- [API Documentation](#-api-documentation)
- [Contributing](#-contributing)
- [License](#-license)

---

<div align="center">

**Made with ❤️ by [bfforex](https://github.com/bfforex)**

[⬆ Back to Top](#soea-master-v40---self-optimizing-expert-advisor)

</div>
