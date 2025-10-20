//+------------------------------------------------------------------+
//| SOEA_Master.mq5         				                         |
//+------------------------------------------------------------------+
#property copyright "Expert Report - Enhanced by bfforex"
#property version   "4.10"
#property description "SOEA with WFO, Volatility Risk, Regime Switching, Drawdown Gating, and Advanced Trade Management"
#property link      "https://github.com/bfforex/Self-Optimizing-Expert-Advisor-SOEA-"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS for State Management                                        |
//+------------------------------------------------------------------+
enum ENUM_REGIME_ID
{
    REGIME_IDLE = 0,    // Strategy halted or waiting for signal
    REGIME_TREND = 1,   // Trend-following strategy active
    REGIME_RANGE = 2    // Mean-reversion strategy active
};

enum ENUM_GATING_STATUS
{
    GATING_ACTIVE = 0,  // Full trading operations allowed
    GATING_REDUCED = 1, // Risk halved due to soft drawdown limit
    GATING_HALTED = 2   // Critical drawdown breach, trading suspended
};

enum ENUM_TRADE_STATUS
{
    TRADE_IDLE = 0,
    TRADE_ACTIVE = 1,
    TRADE_CLOSED = 2
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// --- WFO Configuration ---
input group "=== Walk-Forward Optimization ==="
input int    Inp_WFO_WindowMonths       = 36;
input int    Inp_WFO_StepMonths         = 6;
input int    Inp_WFO_StepOffset         = 0;
input string Inp_WFO_File_Name          = "WFO_Params.csv";
input double Inp_MinStability_R         = 1.0;
input double Inp_Stability_Tolerance    = 0.20;

// --- Risk and Drawdown Gating ---
input group "=== Risk Management ==="
input double Inp_FixedRiskPercent       = 1.0;      // Risk per trade (%)
input double Inp_MaxEquityDrawdown      = 15.0;     // Max drawdown threshold (%)
input double Inp_SoftGateThreshold      = 5.0;      // Soft gate trigger level (%)
input int    Inp_ATR_Period             = 20;       // ATR calculation period
input double Inp_ATR_Multiplier         = 2.5;      // Stop loss ATR multiplier
input double Inp_MinStopLossPoints      = 100;      // Minimum SL distance (points)
input string Inp_HWM_File_Name          = "HWM_Data.txt";
input string Inp_GateStatus_File        = "GateStatus.txt";

// --- Strategy Parameters ---
input group "=== Strategy Configuration ==="
input int    Inp_FastMAPeriod_Default   = 50;       // Fast MA period
input int    Inp_SlowMAPeriod_Default   = 200;      // Slow MA period
input int    Inp_RSI_Period             = 14;       // RSI period
input double Inp_RSI_Overbought         = 70.0;     // RSI overbought level
input double Inp_RSI_Oversold           = 30.0;     // RSI oversold level
input int    Inp_MinBarsBetweenTrades   = 3;        // Minimum bars between trades

// --- Trade Management ---
input group "=== Trade Management ==="
input double Inp_TakeProfitRatio        = 2.0;      // Risk-to-reward ratio
input bool   Inp_UseTrailingStop        = true;     // Enable trailing stop
input double Inp_TrailingStopPercent    = 0.5;      // Trailing stop % of ATR
input bool   Inp_UseBreakeven           = true;     // Move to breakeven
input double Inp_BreakevenTriggerATR    = 1.0;      // Breakeven trigger (ATR multiplier)
input bool   Inp_UsePartialExit         = false;    // Enable partial exits
input double Inp_PartialExit1_Percent   = 50.0;     // First partial exit %
input double Inp_PartialExit1_Level     = 1.0;      // First exit at R multiple
input int    Inp_MaxPositions           = 3;        // Max concurrent positions
input bool   Inp_CloseAllOnDayEnd       = true;     // Close at day end
input int    Inp_DayEndHour             = 22;       // Day end hour (UTC)

// --- External Integration ---
input group "=== Advanced Settings ==="
input bool   Inp_UseExternalDLL         = false;    // Use external regime detector
input string Inp_RegimeDLLName          = "RegimeDetector.dll";
input int    Inp_MagicNumber            = 123456;   // EA magic number
input int    Inp_Slippage               = 10;       // Max slippage (points)
input int    Inp_DebugLevel             = 1;        // 0=Off, 1=Normal, 2=Verbose

//+------------------------------------------------------------------+
//| Global Variables and Buffers                                      |
//+------------------------------------------------------------------+
CTrade              g_Trade;
CPositionInfo       g_PosInfo;
COrderInfo          g_OrderInfo;
CAccountInfo        g_AccountInfo;

int                 g_handle_MA_1;
int                 g_handle_MA_2;
int                 g_handle_ATR;
int                 g_handle_RSI;

double              g_MABuffer_1[];
double              g_MABuffer_2[];
double              g_ATRBuffer[];
double              g_RSIBuffer[];

datetime            g_LastBarTime = 0;
datetime            g_LastTradeTime = 0;
ENUM_REGIME_ID      g_CurrentRegime = REGIME_IDLE;
ENUM_GATING_STATUS  g_CurrentGatingStatus = GATING_ACTIVE;

int                 g_MA_Period_1 = 0;
int                 g_MA_Period_2 = 0;
bool                g_ParametersLoaded = false;
datetime            g_LastParameterLoadTime = 0;
int                 g_BarsSinceLastTrade = 0;

// Statistics tracking
struct SStrategyStats
{
    int total_trades;
    int winning_trades;
    int losing_trades;
    double gross_profit;
    double gross_loss;
    double max_drawdown;
    double current_drawdown;
    datetime last_reset;
};
SStrategyStats g_Stats = {0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0};

// Position tracking for partial exits
struct SPositionTracker
{
    ulong ticket;
    double entry_price;
    double stop_loss;
    double take_profit;
    double initial_volume;
    bool partial_exit_1_done;
    bool breakeven_set;
    datetime entry_time;
};
SPositionTracker g_PositionTrackers[];

//+------------------------------------------------------------------+
//| Forward Declarations                                              |
//+------------------------------------------------------------------+
class CDrawdownGate;
class CRiskManager;
class CTradeManager;
class CParameterLoader;
class CChartObjectsManager;
class CPartialExitManager;

//+------------------------------------------------------------------+
//| Drawdown Gate Class - Enhanced with Persistence                  |
//+------------------------------------------------------------------+
class CDrawdownGate
{
private:
    double m_HighWaterMark;
    ENUM_GATING_STATUS m_GateStatus;
    double m_InitialEquity;
    datetime m_LastUpdateTime;
    bool m_PersistenceEnabled;
    
    bool SaveGateStatus()
    {
        if (!m_PersistenceEnabled) return false;
        
        int fH = FileOpen(Inp_GateStatus_File, FILE_WRITE | FILE_TXT);
        if (fH == INVALID_HANDLE)
        {
            if (Inp_DebugLevel >= 1)
                Print("ERROR: Failed to save gate status. Error: ", GetLastError());
            return false;
        }
        
        FileWriteString(fH, IntegerToString((int)m_GateStatus) + "\n");
        FileWriteString(fH, TimeToString(TimeCurrent()));
        FileClose(fH);
        return true;
    }
    
    ENUM_GATING_STATUS LoadGateStatus()
    {
        int fH = FileOpen(Inp_GateStatus_File, FILE_READ | FILE_TXT);
        if (fH == INVALID_HANDLE)
            return GATING_ACTIVE;
        
        string status_str = FileReadString(fH);
        FileClose(fH);
        
        int status = (int)StringToInteger(status_str);
        if (status >= 0 && status <= 2)
            return (ENUM_GATING_STATUS)status;
        
        return GATING_ACTIVE;
    }
    
public:
    CDrawdownGate() : m_HighWaterMark(0.0), m_GateStatus(GATING_ACTIVE), 
                      m_InitialEquity(0.0), m_LastUpdateTime(0),
                      m_PersistenceEnabled(true) {}
    
    ENUM_GATING_STATUS GateStatus() const { return m_GateStatus; }
    double HighWaterMark() const { return m_HighWaterMark; }
    
    double GetCurrentDrawdown() const 
    { 
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if (m_HighWaterMark <= 0) return 0.0;
        
        double dd = ((m_HighWaterMark - current_equity) / m_HighWaterMark) * 100.0;
        return MathMax(0.0, dd); // Prevent negative drawdown
    }
    
    void LoadHighWaterMark()
    {
        m_InitialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        int fH = FileOpen(Inp_HWM_File_Name, FILE_READ | FILE_TXT);
        if (fH != INVALID_HANDLE)
        {
            string hwm_str = FileReadString(fH);
            FileClose(fH);
            
            m_HighWaterMark = StringToDouble(hwm_str);
            
            // Sanity check: HWM should be reasonable
            if (m_HighWaterMark < 0 || m_HighWaterMark > 1000000000.0)
            {
                if (Inp_DebugLevel >= 1)
                    Print("WARNING: Invalid HWM value detected (", m_HighWaterMark, "). Resetting.");
                m_HighWaterMark = m_InitialEquity;
            }
            
            // Validation: HWM should never be less than current equity
            m_HighWaterMark = MathMax(m_HighWaterMark, m_InitialEquity);
            
            if (Inp_DebugLevel >= 1)
                Print("HWM loaded: ", DoubleToString(m_HighWaterMark, 2), 
                      " | Current Equity: ", DoubleToString(m_InitialEquity, 2));
        }
        else
        {
            m_HighWaterMark = m_InitialEquity;
            if (Inp_DebugLevel >= 1)
                Print("HWM file not found. Initialized to current equity: ", 
                      DoubleToString(m_HighWaterMark, 2));
        }
        
        // Load previous gate status
        if (m_PersistenceEnabled)
        {
            m_GateStatus = LoadGateStatus();
            if (Inp_DebugLevel >= 1 && m_GateStatus != GATING_ACTIVE)
                Print("Restored gate status: ", EnumToString(m_GateStatus));
        }
    }
    
    void UpdateHighWaterMark()
    {
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if (current_equity > m_HighWaterMark)
        {
            m_HighWaterMark = current_equity;
            
            int fH = FileOpen(Inp_HWM_File_Name, FILE_WRITE | FILE_TXT);
            if (fH != INVALID_HANDLE)
            {
                FileWriteString(fH, DoubleToString(m_HighWaterMark, 2));
                FileClose(fH);
                
                if (Inp_DebugLevel >= 2)
                    Print("HWM updated to: ", DoubleToString(m_HighWaterMark, 2));
            }
            else
            {
                if (Inp_DebugLevel >= 1)
                    Print("ERROR: Failed to save HWM. Error: ", GetLastError());
            }
        }
    }
    
    void EnforceDrawdownGate(double max_dd_percent)
    {
        double current_dd = GetCurrentDrawdown();
        ENUM_GATING_STATUS old_status = m_GateStatus;
        
        // Hard Gate: Critical Breach
        if (current_dd >= max_dd_percent)
        {
            m_GateStatus = GATING_HALTED;
            if (old_status != GATING_HALTED && Inp_DebugLevel >= 1)
            {
                Print("!!! CRITICAL: Hard Gate Activated. DD: ", DoubleToString(current_dd, 2), 
                      "% | Threshold: ", DoubleToString(max_dd_percent, 2), "%");
            }
        }
        // Soft Gate: Mitigation
        else if (current_dd >= Inp_SoftGateThreshold)
        {
            m_GateStatus = GATING_REDUCED;
            if (old_status != GATING_REDUCED && Inp_DebugLevel >= 1)
            {
                Print("WARNING: Soft Gate Activated. DD: ", DoubleToString(current_dd, 2), 
                      "% | Threshold: ", DoubleToString(Inp_SoftGateThreshold, 2), "%");
            }
        }
        // Normal Operation
        else
        {
            m_GateStatus = GATING_ACTIVE;
            if (old_status != GATING_ACTIVE && Inp_DebugLevel >= 1)
            {
                Print("Gate status normalized. DD: ", DoubleToString(current_dd, 2), "%");
            }
        }
        
        // Save status if changed
        if (old_status != m_GateStatus)
        {
            SaveGateStatus();
        }
    }
    
    void ResetGate()
    {
        m_HighWaterMark = AccountInfoDouble(ACCOUNT_EQUITY);
        m_GateStatus = GATING_ACTIVE;
        UpdateHighWaterMark();
        SaveGateStatus();
        
        if (Inp_DebugLevel >= 1)
            Print("Drawdown Gate manually reset to: ", DoubleToString(m_HighWaterMark, 2));
    }
    
    void EnablePersistence(bool enable) { m_PersistenceEnabled = enable; }
};

//+------------------------------------------------------------------+
//| Risk Manager Class - Enhanced with Better Error Handling         |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
    int m_ATR_Handle;
    double m_LastATRValue;
    bool m_IsInitialized;
    
public:
    CRiskManager() : m_ATR_Handle(INVALID_HANDLE), m_LastATRValue(0.0), m_IsInitialized(false)
    {
        m_ATR_Handle = iATR(_Symbol, _Period, Inp_ATR_Period);
        if (m_ATR_Handle != INVALID_HANDLE)
        {
            m_IsInitialized = true;
        }
        else
        {
            if (Inp_DebugLevel >= 1)
                Print("ERROR: Failed to create ATR indicator handle");
        }
    }
    
    double GetATRValue()
    {
        if (!m_IsInitialized) return m_LastATRValue;
        
        double atr_buffer[];
        ArraySetAsSeries(atr_buffer, true);
        
        if (CopyBuffer(m_ATR_Handle, 0, 0, 3, atr_buffer) < 1)
        {
            if (Inp_DebugLevel >= 2)
                Print("Warning: Failed to copy ATR data. Using last value.");
            return m_LastATRValue;
        }
        
        m_LastATRValue = atr_buffer[0];
        return m_LastATRValue;
    }
    
    double CalculateATRStopDistance()
    {
        double atr = GetATRValue();
        
        // Fallback if ATR is invalid
        if (atr <= 0)
        {
            double avg_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
            atr = MathMax(avg_spread * 10.0, Inp_MinStopLossPoints * _Point);
            
            if (Inp_DebugLevel >= 2)
                Print("ATR invalid, using fallback: ", DoubleToString(atr, 5));
        }
        
        double sl_distance_points = (atr / _Point) * Inp_ATR_Multiplier;
        
        // Apply minimum stop level from broker
        double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        double min_distance = MathMax(min_stop_level * 2.0, Inp_MinStopLossPoints);
        
        sl_distance_points = MathMax(sl_distance_points, min_distance);
        
        return sl_distance_points;
    }
    
    double CalculateAdaptiveLotSize(double risk_percent, ENUM_GATING_STATUS status)
    {
        double current_risk = risk_percent;
        
        // Apply gating adjustments
        if (status == GATING_REDUCED)
            current_risk /= 2.0;
        else if (status == GATING_HALTED)
            return 0.0;
        
        double sl_distance_points = CalculateATRStopDistance();
        if (sl_distance_points < Inp_MinStopLossPoints) 
            sl_distance_points = Inp_MinStopLossPoints;
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if (equity <= 0)
        {
            if (Inp_DebugLevel >= 1)
                Print("ERROR: Invalid equity value");
            return 0.0;
        }
        
        double risk_amount = equity * (current_risk / 100.0);
        
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        
        // Validate tick parameters BEFORE division
        if (tick_size <= 0 || tick_value <= 0)
        {
            if (Inp_DebugLevel >= 1)
                Print("ERROR: Invalid tick parameters. Size: ", tick_size, " Value: ", tick_value);
            return 0.0;
        }
        
        double loss_per_lot = sl_distance_points * (tick_value / tick_size);
        if (loss_per_lot <= 0)
        {
            if (Inp_DebugLevel >= 1)
                Print("ERROR: Invalid loss per lot calculation");
            return 0.0;
        }
        
        double optimal_lot = risk_amount / loss_per_lot;
        
        // Normalize to symbol specifications
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        
        if (step_lot <= 0) step_lot = 0.01;
        
        if (optimal_lot < min_lot)
        {
            if (Inp_DebugLevel >= 2)
                Print("Calculated lot (", optimal_lot, ") below minimum (", min_lot, ")");
            return 0.0;
        }
        
        optimal_lot = MathFloor(optimal_lot / step_lot) * step_lot;
        optimal_lot = MathMin(optimal_lot, max_lot);
        
        if (Inp_DebugLevel >= 2)
            Print("Lot calculation: Risk=", current_risk, "% SL=", sl_distance_points, 
                  "pts Result=", optimal_lot, " lots");
        
        return optimal_lot;
    }
    
    bool IsInitialized() const { return m_IsInitialized; }
    
    ~CRiskManager()
    {
        if (m_ATR_Handle != INVALID_HANDLE)
            IndicatorRelease(m_ATR_Handle);
    }
};

//+------------------------------------------------------------------+
//| Partial Exit Manager Class                                        |
//+------------------------------------------------------------------+
class CPartialExitManager
{
private:
    struct SPartialExit
    {
        double price_level;
        double exit_percentage;
        bool executed;
    };
    
    SPartialExit m_ExitLevels[1];  // FIXED: Static array size
    int m_NumLevels;
    
    double NormalizeLot(double lot)
    {
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        
        if (step_lot <= 0) step_lot = 0.01;
        
        lot = MathFloor(lot / step_lot) * step_lot;
        lot = MathMax(min_lot, MathMin(lot, max_lot));
        
        return lot;
    }
    
public:
    CPartialExitManager()
    {
        m_NumLevels = 1;
        
        // Single partial exit configuration
        m_ExitLevels[0].exit_percentage = Inp_PartialExit1_Percent / 100.0;
        m_ExitLevels[0].executed = false;
    }
    
    void SetupExitLevels(double entry_price, double sl_price, ENUM_POSITION_TYPE pos_type)
    {
        double risk_distance = MathAbs(entry_price - sl_price);
        
        if (pos_type == POSITION_TYPE_BUY)
        {
            m_ExitLevels[0].price_level = entry_price + (risk_distance * Inp_PartialExit1_Level);
        }
        else
        {
            m_ExitLevels[0].price_level = entry_price - (risk_distance * Inp_PartialExit1_Level);
        }
        
        // Reset execution flags
        for (int i = 0; i < m_NumLevels; i++)
            m_ExitLevels[i].executed = false;
    }
    
    void CheckPartialExits(ulong ticket, CTrade &trade)
    {
        if (!Inp_UsePartialExit) return;
        if (!PositionSelectByTicket(ticket)) return;
        
        double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
        double current_volume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        for (int i = 0; i < m_NumLevels; i++)
        {
            if (m_ExitLevels[i].executed) continue;
            
            bool level_hit = false;
            
            if (pos_type == POSITION_TYPE_BUY)
                level_hit = (current_price >= m_ExitLevels[i].price_level);
            else
                level_hit = (current_price <= m_ExitLevels[i].price_level);
            
            if (level_hit)
            {
                double exit_volume = current_volume * m_ExitLevels[i].exit_percentage;
                exit_volume = NormalizeLot(exit_volume);
                
                if (exit_volume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
                {
                    if (trade.PositionClosePartial(ticket, exit_volume))
                    {
                        m_ExitLevels[i].executed = true;
                        
                        if (Inp_DebugLevel >= 1)
                            Print("Partial exit executed: ", 
                                  DoubleToString(m_ExitLevels[i].exit_percentage * 100, 0), 
                                  "% (", exit_volume, " lots) at ", current_price);
                    }
                }
            }
        }
    }
    
    void Reset()
    {
        for (int i = 0; i < m_NumLevels; i++)
            m_ExitLevels[i].executed = false;
    }
};

//+------------------------------------------------------------------+
//| Trade Manager Class - Enhanced                                    |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
    CTrade m_Trade;
    double m_LastTradePrice;
    ENUM_TRADE_STATUS m_TradeStatus;
    CPartialExitManager m_PartialExitMgr;
    
    bool MoveToBreakeven(ulong ticket, double entry_price, ENUM_POSITION_TYPE pos_type,
                        double current_sl, double current_tp)
    {
        double new_sl = entry_price + (10 * _Point); // Small buffer above entry
        
        if (pos_type == POSITION_TYPE_BUY)
        {
            if (current_sl >= entry_price) return false; // Already at or above BE
            new_sl = entry_price + (10 * _Point);
        }
        else
        {
            if (current_sl <= entry_price) return false; // Already at or below BE
            new_sl = entry_price - (10 * _Point);
        }
        
        if (m_Trade.PositionModify(ticket, new_sl, current_tp))
        {
            if (Inp_DebugLevel >= 1)
                Print("Stop moved to breakeven for ticket ", ticket, " at ", new_sl);
            return true;
        }
        
        return false;
    }
    
public:
    CTradeManager() : m_LastTradePrice(0.0), m_TradeStatus(TRADE_IDLE)
    {
        m_Trade.SetExpertMagicNumber(Inp_MagicNumber);
        m_Trade.SetDeviationInPoints(Inp_Slippage);
        m_Trade.SetTypeFilling(ORDER_FILLING_IOC);
        m_Trade.SetAsyncMode(false);
    }
    
    bool OpenTrade(ENUM_ORDER_TYPE order_type, double lot_size, double entry_price, 
                   double sl_price, double tp_price, string comment)
    {
        if (lot_size <= 0)
        {
            if (Inp_DebugLevel >= 2)
                Print("Cannot open trade: Invalid lot size");
            return false;
        }
        
        if (GetOpenPositionsCount() >= Inp_MaxPositions)
        {
            if (Inp_DebugLevel >= 2)
                Print("Cannot open trade: Max positions reached (", GetOpenPositionsCount(), ")");
            return false;
        }
        
        bool result = false;
        if (order_type == ORDER_TYPE_BUY)
            result = m_Trade.Buy(lot_size, _Symbol, entry_price, sl_price, tp_price, comment);
        else if (order_type == ORDER_TYPE_SELL)
            result = m_Trade.Sell(lot_size, _Symbol, entry_price, sl_price, tp_price, comment);
        
        if (result)
        {
            m_LastTradePrice = entry_price;
            m_TradeStatus = TRADE_ACTIVE;
            
            // Setup partial exits if enabled
            if (Inp_UsePartialExit)
            {
                ENUM_POSITION_TYPE pos_type = (order_type == ORDER_TYPE_BUY) ? 
                                               POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                m_PartialExitMgr.SetupExitLevels(entry_price, sl_price, pos_type);
            }
            
            if (Inp_DebugLevel >= 1)
                Print("Trade opened: ", comment, " | Lot: ", lot_size, " | Entry: ", 
                      entry_price, " | SL: ", sl_price, " | TP: ", tp_price);
            
            g_LastTradeTime = TimeCurrent();
            g_BarsSinceLastTrade = 0;
            
            return true;
        }
        else
        {
            if (Inp_DebugLevel >= 1)
                Print("Failed to open trade. Error: ", m_Trade.ResultRetcode(), 
                      " (", m_Trade.ResultRetcodeDescription(), ")");
            return false;
        }
    }
    
    void ManageOpenPositions(CRiskManager &risk_mgr)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if (!g_PosInfo.SelectByIndex(i)) continue;
            if (g_PosInfo.Symbol() != _Symbol) continue;
            if (g_PosInfo.Magic() != Inp_MagicNumber) continue;
            
            ulong ticket = g_PosInfo.Ticket();
            double entry_price = g_PosInfo.PriceOpen();
            double current_price = g_PosInfo.PriceCurrent();
            double sl = g_PosInfo.StopLoss();
            double tp = g_PosInfo.TakeProfit();
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)g_PosInfo.Type();
            
            double profit_distance = MathAbs(current_price - entry_price);
            double atr_stop = risk_mgr.CalculateATRStopDistance() * _Point;
            
            // 1. Check partial exits
            m_PartialExitMgr.CheckPartialExits(ticket, m_Trade);
            
            // 2. Move to breakeven if enabled
            if (Inp_UseBreakeven)
            {
                double breakeven_trigger = atr_stop * Inp_BreakevenTriggerATR;
                
                if (profit_distance >= breakeven_trigger)
                {
                    MoveToBreakeven(ticket, entry_price, pos_type, sl, tp);
                }
            }
            
            // 3. Implement trailing stop
            if (Inp_UseTrailingStop && sl > 0)
            {
                double trail_distance = atr_stop * Inp_TrailingStopPercent;
                double new_sl = 0.0;
                bool should_modify = false;
                
                if (pos_type == POSITION_TYPE_BUY)
                {
                    new_sl = current_price - trail_distance;
                    should_modify = (new_sl > sl) && (new_sl > entry_price);
                }
                else
                {
                    new_sl = current_price + trail_distance;
                    should_modify = (new_sl < sl) && (new_sl < entry_price);
                }
                
                if (should_modify && profit_distance > atr_stop * 1.5)
                {
                    if (m_Trade.PositionModify(ticket, new_sl, tp))
                    {
                        if (Inp_DebugLevel >= 2)
                            Print("Trailing stop updated: ", ticket, " New SL: ", new_sl);
                    }
                }
            }
            
            // 4. Check for day-end close
            if (Inp_CloseAllOnDayEnd)
            {
                MqlDateTime dt;
                TimeToStruct(TimeCurrent(), dt);
                
                if (dt.hour >= Inp_DayEndHour)
                {
                    if (m_Trade.PositionClose(ticket))
                    {
                        if (Inp_DebugLevel >= 1)
                            Print("Position closed at day end: ", ticket);
                    }
                }
            }
        }
    }
    
    void CloseAllPositions()
    {
        int closed = 0;
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if (!g_PosInfo.SelectByIndex(i)) continue;
            if (g_PosInfo.Symbol() != _Symbol) continue;
            if (g_PosInfo.Magic() != Inp_MagicNumber) continue;
            
            if (m_Trade.PositionClose(g_PosInfo.Ticket()))
                closed++;
        }
        
        if (Inp_DebugLevel >= 1 && closed > 0)
            Print("Closed ", closed, " positions.");
    }
    
    int GetOpenPositionsCount()
    {
        int count = 0;
        for (int i = 0; i < PositionsTotal(); i++)
        {
            if (!g_PosInfo.SelectByIndex(i)) continue;
            if (g_PosInfo.Symbol() != _Symbol) continue;
            if (g_PosInfo.Magic() != Inp_MagicNumber) continue;
            count++;
        }
        return count;
    }
};

//+------------------------------------------------------------------+
//| Parameter Loader Class                                            |
//+------------------------------------------------------------------+
class CParameterLoader
{
public:
    bool LoadWFOParameters(datetime current_time, int regime_id)
    {
        // FIXED: Use MQLInfoInteger instead of IsTesting/IsOptimization
        if (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
        {
            g_MA_Period_1 = Inp_FastMAPeriod_Default;
            g_MA_Period_2 = Inp_SlowMAPeriod_Default;
            return true;
        }
        
        int file_handle = FileOpen(Inp_WFO_File_Name, FILE_READ | FILE_CSV, '\t');
        if (file_handle == INVALID_HANDLE)
        {
            if (Inp_DebugLevel >= 1)
                Print("WFO file not found (", Inp_WFO_File_Name, "). Using defaults.");
            g_MA_Period_1 = Inp_FastMAPeriod_Default;
            g_MA_Period_2 = Inp_SlowMAPeriod_Default;
            return false;
        }
        
        bool found = false;
        int line_count = 0;
        
        // Skip header if exists
        if (!FileIsEnding(file_handle))
        {
            string header = FileReadString(file_handle);
            if (StringFind(header, "StartDate") >= 0 || StringFind(header, "S_StartDate") >= 0)
            {
                // Header detected, already skipped
            }
            else
            {
                // No header, seek back to start
                FileSeek(file_handle, 0, SEEK_SET);
            }
        }
        
        while (!FileIsEnding(file_handle))
        {
            string line = FileReadString(file_handle);
            if (line == "") continue;
            
            line_count++;
            
            string parts[];
            int count = StringSplit(line, '\t', parts);
            
            if (count >= 5)
            {
                datetime start_date = (datetime)StringToInteger(parts[0]);
                datetime end_date = (datetime)StringToInteger(parts[1]);
                int file_regime = (int)StringToInteger(parts[2]);
                int ma1 = (int)StringToInteger(parts[3]);
                int ma2 = (int)StringToInteger(parts[4]);
                
                if (current_time >= start_date && current_time < end_date && 
                    file_regime == regime_id && ma1 > 0 && ma2 > 0)
                {
                    g_MA_Period_1 = ma1;
                    g_MA_Period_2 = ma2;
                    found = true;
                    
                    if (Inp_DebugLevel >= 1)
                        Print("Loaded WFO parameters: Regime=", file_regime, 
                              " MA1=", ma1, " MA2=", ma2, 
                              " Period: ", TimeToString(start_date), " to ", TimeToString(end_date));
                    break;
                }
            }
        }
        FileClose(file_handle);
        
        if (!found)
        {
            g_MA_Period_1 = Inp_FastMAPeriod_Default;
            g_MA_Period_2 = Inp_SlowMAPeriod_Default;
            
            if (Inp_DebugLevel >= 1)
                Print("No matching WFO parameters found (", line_count, " lines checked). Using defaults.");
        }
        
        return found;
    }
};

//+------------------------------------------------------------------+
//| Chart Objects Manager Class                                       |
//+------------------------------------------------------------------+
class CChartObjectsManager
{
private:
    string m_prefix;
    
public:
    CChartObjectsManager(string prefix = "SOEA_") : m_prefix(prefix) {}
    
    void CreateOrUpdateHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width)
    {
        string obj_name = m_prefix + name;
        
        if (ObjectFind(0, obj_name) >= 0)
            ObjectDelete(0, obj_name);
        
        if (ObjectCreate(0, obj_name, OBJ_HLINE, 0, 0, price))
        {
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, obj_name, OBJPROP_STYLE, style);
            ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, width);
            ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
            ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, name);
        }
    }
    
    void CreateOrUpdateLabel(string name, int x, int y, string text, color clr, int font_size = 10)
    {
        string obj_name = m_prefix + name;
        
        if (ObjectFind(0, obj_name) >= 0)
            ObjectDelete(0, obj_name);
        
        if (ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0))
        {
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
            ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
            ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, font_size);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        }
    }
    
    void CreateOrUpdateArrow(string name, datetime time, double price, int arrow_code, 
                            color clr, string description = "")
    {
        string obj_name = m_prefix + name;
        
        if (ObjectFind(0, obj_name) >= 0)
            ObjectDelete(0, obj_name);
        
        if (ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price))
        {
            ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, arrow_code);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
            ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, description);
        }
    }
    
    void ClearAllObjects()
    {
        int count = 0;
        for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
        {
            string obj_name = ObjectName(0, i);
            if (StringFind(obj_name, m_prefix) == 0)
            {
                ObjectDelete(0, obj_name);
                count++;
            }
        }
        
        if (Inp_DebugLevel >= 2)
            Print("Cleared ", count, " chart objects.");
    }
};

//+------------------------------------------------------------------+
//| Global Class Instances                                            |
//+------------------------------------------------------------------+
CDrawdownGate       g_DrawdownGate;
CRiskManager        g_RiskManager;
CTradeManager       g_TradeManager;
CParameterLoader    g_ParamLoader;
CChartObjectsManager g_ChartMgr;

//+------------------------------------------------------------------+
//| External DLL Integration                                          |
//+------------------------------------------------------------------+
#import "RegimeDetector.dll"
int GetMarketRegimeID(int &market_regime_id);
#import

bool ValidateDLLAccess()
{
    if (!Inp_UseExternalDLL) return false;
    
    int test_regime = 1;
    int result = GetMarketRegimeID(test_regime);
    return (result == 0);
}

//+------------------------------------------------------------------+
//| Signal Generation Functions                                       |
//+------------------------------------------------------------------+
bool GenerateTrendSignal(bool &buy_signal, bool &sell_signal)
{
    buy_signal = false;
    sell_signal = false;
    
    if (CopyBuffer(g_handle_MA_1, 0, 0, 3, g_MABuffer_1) < 3)
    {
        if (Inp_DebugLevel >= 2)
            Print("Failed to copy MA1 buffer");
        return false;
    }
    
    if (CopyBuffer(g_handle_MA_2, 0, 0, 3, g_MABuffer_2) < 3)
    {
        if (Inp_DebugLevel >= 2)
            Print("Failed to copy MA2 buffer");
        return false;
    }
    
    // MA Crossover logic
    if (g_MABuffer_1[1] <= g_MABuffer_2[1] && g_MABuffer_1[0] > g_MABuffer_2[0])
    {
        buy_signal = true;
        if (Inp_DebugLevel >= 2)
            Print("TREND BUY signal: MA1[0]=", g_MABuffer_1[0], " MA2[0]=", g_MABuffer_2[0]);
    }
    
    if (g_MABuffer_1[1] >= g_MABuffer_2[1] && g_MABuffer_1[0] < g_MABuffer_2[0])
    {
        sell_signal = true;
        if (Inp_DebugLevel >= 2)
            Print("TREND SELL signal: MA1[0]=", g_MABuffer_1[0], " MA2[0]=", g_MABuffer_2[0]);
    }
    
    return true;
}

bool GenerateRangeSignal(bool &buy_signal, bool &sell_signal)
{
    buy_signal = false;
    sell_signal = false;
    
    if (CopyBuffer(g_handle_RSI, 0, 0, 3, g_RSIBuffer) < 3)
    {
        if (Inp_DebugLevel >= 2)
            Print("Failed to copy RSI buffer");
        return false;
    }
    
    // RSI mean-reversion logic
    if (g_RSIBuffer[1] <= Inp_RSI_Oversold && g_RSIBuffer[0] > Inp_RSI_Oversold)
    {
        buy_signal = true;
        if (Inp_DebugLevel >= 2)
            Print("RANGE BUY signal: RSI=", g_RSIBuffer[0]);
    }
    
    if (g_RSIBuffer[1] >= Inp_RSI_Overbought && g_RSIBuffer[0] < Inp_RSI_Overbought)
    {
        sell_signal = true;
        if (Inp_DebugLevel >= 2)
            Print("RANGE SELL signal: RSI=", g_RSIBuffer[0]);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Trade Dispatcher                                                  |
//+------------------------------------------------------------------+
void TradeDispatcher(ENUM_REGIME_ID regime_id, double lot_size)
{
    if (lot_size <= 0)
    {
        if (Inp_DebugLevel >= 2)
            Print("Trade dispatcher: Invalid lot size (", lot_size, ")");
        return;
    }
    
    if (g_TradeManager.GetOpenPositionsCount() >= Inp_MaxPositions)
    {
        if (Inp_DebugLevel >= 2)
            Print("Trade dispatcher: Max positions reached");
        return;
    }
    
    if (g_BarsSinceLastTrade < Inp_MinBarsBetweenTrades)
    {
        if (Inp_DebugLevel >= 2)
            Print("Trade dispatcher: Waiting for minimum bars (", g_BarsSinceLastTrade, 
                  "/", Inp_MinBarsBetweenTrades, ")");
        return;
    }
    
    bool buy_signal = false, sell_signal = false;
    double entry = 0.0, sl = 0.0, tp = 0.0;
    double atr_stop = g_RiskManager.CalculateATRStopDistance() * _Point;
    
    if (regime_id == REGIME_TREND)
    {
        if (!GenerateTrendSignal(buy_signal, sell_signal))
            return;
        
        if (buy_signal)
        {
            entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            sl = entry - atr_stop;
            tp = entry + (atr_stop * Inp_TakeProfitRatio);
            
            g_TradeManager.OpenTrade(ORDER_TYPE_BUY, lot_size, entry, sl, tp, 
                                    "SOEA_TREND_BUY_v4.1");
        }
        else if (sell_signal)
        {
            entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            sl = entry + atr_stop;
            tp = entry - (atr_stop * Inp_TakeProfitRatio);
            
            g_TradeManager.OpenTrade(ORDER_TYPE_SELL, lot_size, entry, sl, tp, 
                                    "SOEA_TREND_SELL_v4.1");
        }
    }
    else if (regime_id == REGIME_RANGE)
    {
        if (!GenerateRangeSignal(buy_signal, sell_signal))
            return;
        
        if (buy_signal)
        {
            entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            sl = entry - atr_stop;
            tp = entry + (atr_stop * Inp_TakeProfitRatio);
            
            g_TradeManager.OpenTrade(ORDER_TYPE_BUY, lot_size, entry, sl, tp, 
                                    "SOEA_RANGE_BUY_v4.1");
        }
        else if (sell_signal)
        {
            entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            sl = entry + atr_stop;
            tp = entry - (atr_stop * Inp_TakeProfitRatio);
            
            g_TradeManager.OpenTrade(ORDER_TYPE_SELL, lot_size, entry, sl, tp, 
                                    "SOEA_RANGE_SELL_v4.1");
        }
    }
}

//+------------------------------------------------------------------+
//| Update Chart Comment                                              |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dd = g_DrawdownGate.GetCurrentDrawdown();
    double hwm = g_DrawdownGate.HighWaterMark();
    
    string regime_text = "";
    if (g_CurrentRegime == REGIME_TREND)
        regime_text = "TREND";
    else if (g_CurrentRegime == REGIME_RANGE)
        regime_text = "RANGE";
    else
        regime_text = "IDLE";
    
    string gating_text = "";
    
    if (g_CurrentGatingStatus == GATING_ACTIVE)
        gating_text = "ACTIVE";
    else if (g_CurrentGatingStatus == GATING_REDUCED)
        gating_text = "REDUCED";
    else
        gating_text = "HALTED";
    
    string comment = StringFormat(
        "????????? SOEA v4.1 Enhanced Dashboard ?????????\n" +
        "?  Regime: %s | Gating: %s               ?\n" +
        "?????????????????????????????????????????????\n" +
        "?  Balance:  $%.2f\n" +
        "?  Equity:   $%.2f\n" +
        "?  HWM:      $%.2f\n" +
        "?  DD:       %.2f%% / %.1f%%\n" +
        "?????????????????????????????????????????????\n" +
        "?  Positions:  %d / %d\n" +
        "?  MA1: %d  |  MA2: %d  |  RSI: %d\n" +
        "?  ATR: %.5f  |  Spread: %d pts\n" +
        "?  Risk: %.2f%%  |  Magic: %d\n" +
        "?????????????????????????????????????????????\n" +
        "?  Bars Since Trade: %d (Min: %d)\n" +
        "?  Last Update: %s\n" +
        "?????????????????????????????????????????????",
        regime_text, gating_text,
        balance, equity, hwm,
        dd, Inp_MaxEquityDrawdown,
        g_TradeManager.GetOpenPositionsCount(), Inp_MaxPositions,
        g_MA_Period_1, g_MA_Period_2, Inp_RSI_Period,
        g_RiskManager.GetATRValue(),
        (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
        Inp_FixedRiskPercent, Inp_MagicNumber,
        g_BarsSinceLastTrade, Inp_MinBarsBetweenTrades,
        TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
    );
    
    Comment(comment);
}

//+------------------------------------------------------------------+
//| Update Chart Objects                                              |
//+------------------------------------------------------------------+
void UpdateChartObjects()
{
    if (ArraySize(g_MABuffer_1) >= 1 && ArraySize(g_MABuffer_2) >= 1)
    {
        g_ChartMgr.CreateOrUpdateHLine("FastMA", g_MABuffer_1[0], clrDodgerBlue, STYLE_SOLID, 2);
        g_ChartMgr.CreateOrUpdateHLine("SlowMA", g_MABuffer_2[0], clrRed, STYLE_SOLID, 2);
    }
    
    double hwm = g_DrawdownGate.HighWaterMark();
    double hard_gate_price = hwm * (1.0 - Inp_MaxEquityDrawdown / 100.0);
    double soft_gate_price = hwm * (1.0 - Inp_SoftGateThreshold / 100.0);
    
    g_ChartMgr.CreateOrUpdateHLine("HardGate", hard_gate_price, clrDarkRed, STYLE_DASHDOT, 3);
    g_ChartMgr.CreateOrUpdateHLine("SoftGate", soft_gate_price, clrOrange, STYLE_DASH, 2);
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double atr_stop = g_RiskManager.CalculateATRStopDistance() * _Point;
    
    g_ChartMgr.CreateOrUpdateHLine("ATR_Support", current_price - atr_stop, 
                                   clrCornflowerBlue, STYLE_DOT, 1);
    g_ChartMgr.CreateOrUpdateHLine("ATR_Resistance", current_price + atr_stop, 
                                   clrCrimson, STYLE_DOT, 1);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert Initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    if (Inp_DebugLevel >= 1)
    {
        Print("????????????????????????????????????????????????");
        Print("?  SOEA v4.1 Enhanced Initialization Started  ?");
        Print("????????????????????????????????????????????????");
    }
    
    // Validate inputs
    if (Inp_FixedRiskPercent <= 0 || Inp_FixedRiskPercent > 10)
    {
        Print("ERROR: Invalid risk percent. Must be 0.1-10.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if (Inp_MaxEquityDrawdown <= 0 || Inp_MaxEquityDrawdown > 50)
    {
        Print("ERROR: Invalid max drawdown. Must be 5.0-50.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Initialize indicators
    g_handle_MA_1 = iMA(_Symbol, _Period, Inp_FastMAPeriod_Default, 0, MODE_SMA, PRICE_CLOSE);
    if (g_handle_MA_1 == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create Fast MA indicator");
        return INIT_FAILED;
    }
    
    g_handle_MA_2 = iMA(_Symbol, _Period, Inp_SlowMAPeriod_Default, 0, MODE_SMA, PRICE_CLOSE);
    if (g_handle_MA_2 == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create Slow MA indicator");
        IndicatorRelease(g_handle_MA_1);
        return INIT_FAILED;
    }
    
    g_handle_ATR = iATR(_Symbol, _Period, Inp_ATR_Period);
    if (g_handle_ATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create ATR indicator");
        IndicatorRelease(g_handle_MA_1);
        IndicatorRelease(g_handle_MA_2);
        return INIT_FAILED;
    }
    
    g_handle_RSI = iRSI(_Symbol, _Period, Inp_RSI_Period, PRICE_CLOSE);
    if (g_handle_RSI == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create RSI indicator");
        IndicatorRelease(g_handle_MA_1);
        IndicatorRelease(g_handle_MA_2);
        IndicatorRelease(g_handle_ATR);
        return INIT_FAILED;
    }
    
    // Initialize buffers
    ArraySetAsSeries(g_MABuffer_1, true);
    ArraySetAsSeries(g_MABuffer_2, true);
    ArraySetAsSeries(g_ATRBuffer, true);
    ArraySetAsSeries(g_RSIBuffer, true);
    
    // Load HWM and gate status
    g_DrawdownGate.LoadHighWaterMark();
    
    // Load initial parameters
    g_ParamLoader.LoadWFOParameters(TimeCurrent(), REGIME_TREND);
    g_ParametersLoaded = true;
    g_LastParameterLoadTime = TimeCurrent();
    
    // Validate DLL if requested
    if (Inp_UseExternalDLL)
    {
        // FIXED: Use TerminalInfoInteger instead of IsDllsAllowed
        if (!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
        {
            Print("ERROR: DLL imports not allowed. Enable in Tools->Options->Expert Advisors.");
            return INIT_FAILED;
        }
        
        if (ValidateDLLAccess())
        {
            if (Inp_DebugLevel >= 1)
                Print("External DLL validated successfully.");
        }
        else
        {
            Print("WARNING: DLL validation failed. Using internal regime detection.");
        }
    }
    
    // Initialize statistics
    g_Stats.last_reset = TimeCurrent();
    
    if (Inp_DebugLevel >= 1)
    {
        Print("???????????????????????????????????????????????");
        Print("Symbol: ", _Symbol);
        Print("Period: ", EnumToString(_Period));
        Print("Initial Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        Print("Risk Per Trade: ", Inp_FixedRiskPercent, "%");
        Print("Max Drawdown: ", Inp_MaxEquityDrawdown, "%");
        Print("Soft Gate: ", Inp_SoftGateThreshold, "%");
        Print("Magic Number: ", Inp_MagicNumber);
        Print("???????????????????????????????????????????????");
        Print("SOEA v4.1 Enhanced Initialization Completed ?");
        Print("???????????????????????????????????????????????");
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (Inp_DebugLevel >= 1)
    {
        Print("???????????????????????????????????????????????");
        Print("SOEA v4.1 Enhanced Deinitialization");
        Print("Reason: ", reason);
        Print("???????????????????????????????????????????????");
    }
    
    g_DrawdownGate.UpdateHighWaterMark();
    
    if (g_handle_MA_1 != INVALID_HANDLE) IndicatorRelease(g_handle_MA_1);
    if (g_handle_MA_2 != INVALID_HANDLE) IndicatorRelease(g_handle_MA_2);
    if (g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if (g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    
    g_ChartMgr.ClearAllObjects();
    Comment("");
    
    if (Inp_DebugLevel >= 1)
        Print("Deinitialization completed.");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
    if (current_bar_time == 0 || current_bar_time == g_LastBarTime)
        return;
    
    g_LastBarTime = current_bar_time;
    g_BarsSinceLastTrade++;
    
    // 1. Update and enforce drawdown gating
    g_DrawdownGate.UpdateHighWaterMark();
    g_DrawdownGate.EnforceDrawdownGate(Inp_MaxEquityDrawdown);
    g_CurrentGatingStatus = g_DrawdownGate.GateStatus();
    
    if (g_CurrentGatingStatus == GATING_HALTED)
    {
        if (Inp_DebugLevel >= 1)
            Print("Trading halted by drawdown gate. Current DD: ", 
                  DoubleToString(g_DrawdownGate.GetCurrentDrawdown(), 2), "%");
        
        g_TradeManager.CloseAllPositions();
        UpdateChartComment();
        return;
    }
    
    // 2. Determine market regime
    int regime_id = REGIME_TREND;
    if (Inp_UseExternalDLL)
    {
        int status = GetMarketRegimeID(regime_id);
        if (status != 0)
        {
            if (Inp_DebugLevel >= 2)
                Print("DLL regime detection failed, using default (TREND)");
            regime_id = REGIME_TREND;
        }
    }
    else
    {
        // Simple internal regime detection based on MA spread
        if (ArraySize(g_MABuffer_1) >= 1 && ArraySize(g_MABuffer_2) >= 1)
        {
            double ma_spread = MathAbs(g_MABuffer_1[0] - g_MABuffer_2[0]);
            double atr = g_RiskManager.GetATRValue();
            
            if (atr > 0)
            {
                // If MAs are far apart (> 2 ATR), assume trending
                // If MAs are close (< 1 ATR), assume ranging
                if (ma_spread > atr * 2.0)
                    regime_id = REGIME_TREND;
                else if (ma_spread < atr)
                    regime_id = REGIME_RANGE;
                else
                    regime_id = REGIME_TREND; // Default to trend
            }
        }
    }
    g_CurrentRegime = (ENUM_REGIME_ID)regime_id;
    
    // 3. Load/update parameters (cached to avoid excessive file I/O)
    if (TimeCurrent() - g_LastParameterLoadTime > 3600)  // Reload every hour
    {
        bool loaded = g_ParamLoader.LoadWFOParameters(TimeCurrent(), g_CurrentRegime);
        g_LastParameterLoadTime = TimeCurrent();
        
        // Update MA indicators if parameters changed
        if (loaded && (g_MA_Period_1 != Inp_FastMAPeriod_Default || 
                       g_MA_Period_2 != Inp_SlowMAPeriod_Default))
        {
            // Release old handles
            if (g_handle_MA_1 != INVALID_HANDLE) IndicatorRelease(g_handle_MA_1);
            if (g_handle_MA_2 != INVALID_HANDLE) IndicatorRelease(g_handle_MA_2);
            
            // Create new handles with updated periods
            g_handle_MA_1 = iMA(_Symbol, _Period, g_MA_Period_1, 0, MODE_SMA, PRICE_CLOSE);
            g_handle_MA_2 = iMA(_Symbol, _Period, g_MA_Period_2, 0, MODE_SMA, PRICE_CLOSE);
            
            if (Inp_DebugLevel >= 1)
                Print("MA indicators updated: MA1=", g_MA_Period_1, " MA2=", g_MA_Period_2);
        }
    }
    
    // 4. Calculate adaptive lot size
    double lot_size = g_RiskManager.CalculateAdaptiveLotSize(Inp_FixedRiskPercent, 
                                                               g_CurrentGatingStatus);
    
    if (Inp_DebugLevel >= 2)
        Print("Calculated lot size: ", lot_size, " (Status: ", 
              EnumToString(g_CurrentGatingStatus), ")");
    
    // 5. Manage open positions (trailing stops, breakeven, partial exits)
    g_TradeManager.ManageOpenPositions(g_RiskManager);
    
    // 6. Dispatch trading signals
    TradeDispatcher(g_CurrentRegime, lot_size);
    
    // 7. Update visual feedback
    if (Inp_DebugLevel >= 1)
    {
        UpdateChartComment();
        
        // Update chart objects every 10 bars to reduce overhead
        static int chart_update_counter = 0;
        chart_update_counter++;
        
        if (chart_update_counter >= 10)
        {
            UpdateChartObjects();
            chart_update_counter = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Strategy Tester Fitness Function                                 |
//+------------------------------------------------------------------+
double OnTester()
{
    // Retrieve performance statistics from current optimization pass
    double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
    double max_dd = TesterStatistics(STAT_BALANCE_DD_RELATIVE);
    double recovery_factor = TesterStatistics(STAT_RECOVERY_FACTOR);
    int total_trades = (int)TesterStatistics(STAT_TRADES);
    double sharpe_ratio = TesterStatistics(STAT_SHARPE_RATIO);
    
    // Avoid division by zero
    if (max_dd <= 0 || total_trades < 10)
    {
        if (Inp_DebugLevel >= 2)
            Print("Insufficient trades or invalid drawdown. Rejecting.");
        return 0.0;
    }
    
    // Composite Robustness Index: Balance profit with risk
    double trade_quality = profit_factor / (1.0 + max_dd / 100.0);
    double trade_frequency_factor = MathMin((double)total_trades / 100.0, 2.0);
    double sharpe_factor = MathMax(sharpe_ratio, 0.1);
    
    double composite_index = trade_quality * MathSqrt(recovery_factor) * 
                            trade_frequency_factor * sharpe_factor;
    
    // Apply minimum stability threshold
    if (composite_index < Inp_MinStability_R)
    {
        if (Inp_DebugLevel >= 2)
            Print("Composite Index (", DoubleToString(composite_index, 4), 
                  ") below minimum (", DoubleToString(Inp_MinStability_R, 4), 
                  "). Rejecting parameters.");
        return 0.0;
    }
    
    // Penalty for excessive drawdown
    if (max_dd > 25.0)
    {
        composite_index *= 0.5;
        if (Inp_DebugLevel >= 2)
            Print("Excessive drawdown penalty applied: ", max_dd, "%");
    }
    
    // Penalty for low win rate
    double win_rate = (TesterStatistics(STAT_PROFIT_TRADES) / total_trades) * 100.0;
    if (win_rate < 30.0)
    {
        composite_index *= 0.7;
        if (Inp_DebugLevel >= 2)
            Print("Low win rate penalty applied: ", win_rate, "%");
    }
    
    if (Inp_DebugLevel >= 1)
    {
        Print("???????????????????????????????????????");
        Print("Optimization Result:");
        Print("  Profit Factor: ", profit_factor);
        Print("  Max DD: ", max_dd, "%");
        Print("  Recovery Factor: ", recovery_factor);
        Print("  Total Trades: ", total_trades);
        Print("  Win Rate: ", win_rate, "%");
        Print("  Sharpe Ratio: ", sharpe_ratio);
        Print("  Composite Index: ", composite_index);
        Print("???????????????????????????????????????");
    }
    
    return composite_index;
}

//+------------------------------------------------------------------+
//| Tester Deinitialization (WFO Results Persistence)                |
//+------------------------------------------------------------------+
void OnTesterDeinit()
{
    // FIXED: Use MQLInfoInteger instead of IsTesting/IsOptimization
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
        return;
    
    // Retrieve best optimization result
    double total_profit = TesterStatistics(STAT_PROFIT);
    int total_trades = (int)TesterStatistics(STAT_TRADES);
    double max_dd = TesterStatistics(STAT_BALANCE_DD_RELATIVE);
    double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
    
    // Get current test parameters
    int tested_ma1 = (g_MA_Period_1 > 0) ? g_MA_Period_1 : Inp_FastMAPeriod_Default;
    int tested_ma2 = (g_MA_Period_2 > 0) ? g_MA_Period_2 : Inp_SlowMAPeriod_Default;
    int tested_regime = (int)g_CurrentRegime;
    if (tested_regime == 0) tested_regime = REGIME_TREND;
    
    // Calculate out-of-sample period based on WFO offset
    datetime test_start = D'2020.01.01' + (Inp_WFO_StepOffset * 30 * 24 * 3600);
    datetime test_end = test_start + (Inp_WFO_StepMonths * 30 * 24 * 3600);
    
    // Only save if results meet minimum criteria
    if (total_trades < 10 || profit_factor < 1.1)
    {
        if (Inp_DebugLevel >= 1)
            Print("WFO results not saved (insufficient quality).");
        return;
    }
    
    // Persist results to CSV file
    int fH = FileOpen(Inp_WFO_File_Name, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, '\t');
    if (fH == INVALID_HANDLE)
    {
        // File doesn't exist, create with header
        fH = FileOpen(Inp_WFO_File_Name, FILE_WRITE | FILE_CSV | FILE_ANSI, '\t');
        if (fH != INVALID_HANDLE)
        {
            string header = "StartDate\tEndDate\tRegime\tMA1\tMA2\tProfit\tTrades\tDD\tPF\n";
            FileWriteString(fH, header);
        }
    }
    else
    {
        // File exists, seek to end
        FileSeek(fH, 0, SEEK_END);
    }
    
    if (fH != INVALID_HANDLE)
    {
        string record = StringFormat("%d\t%d\t%d\t%d\t%d\t%.2f\t%d\t%.2f\t%.2f\n",
            (long)test_start,
            (long)test_end,
            tested_regime,
            tested_ma1,
            tested_ma2,
            total_profit,
            total_trades,
            max_dd,
            profit_factor
        );
        
        FileWriteString(fH, record);
        FileClose(fH);
        
        if (Inp_DebugLevel >= 1)
        {
            Print("???????????????????????????????????????");
            Print("WFO results saved:");
            Print("  Period: ", TimeToString(test_start), " to ", TimeToString(test_end));
            Print("  Regime: ", tested_regime);
            Print("  MA1: ", tested_ma1, " | MA2: ", tested_ma2);
            Print("  Profit: $", total_profit);
            Print("  Trades: ", total_trades);
            Print("  Max DD: ", max_dd, "%");
            Print("  Profit Factor: ", profit_factor);
            Print("???????????????????????????????????????");
        }
    }
    else
    {
        Print("ERROR: Failed to save WFO results. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Trade Transaction Handler (Optional)                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Track trade statistics
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong deal_ticket = trans.deal;
        if (deal_ticket > 0)
        {
            if (HistoryDealSelect(deal_ticket))
            {
                long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                
                if (deal_entry == DEAL_ENTRY_OUT) // Position closed
                {
                    g_Stats.total_trades++;
                    
                    if (deal_profit > 0)
                    {
                        g_Stats.winning_trades++;
                        g_Stats.gross_profit += deal_profit;
                    }
                    else if (deal_profit < 0)
                    {
                        g_Stats.losing_trades++;
                        g_Stats.gross_loss += MathAbs(deal_profit);
                    }
                    
                    if (Inp_DebugLevel >= 2)
                    {
                        Print("Trade closed: Profit=$", deal_profit, 
                              " | Total Trades: ", g_Stats.total_trades,
                              " | Win Rate: ", 
                              (g_Stats.total_trades > 0) ? 
                              (g_Stats.winning_trades * 100.0 / g_Stats.total_trades) : 0, "%");
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Optional)                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // Handle button clicks or other chart events
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == "SOEA_ResetButton")
        {
            g_DrawdownGate.ResetGate();
            Print("Drawdown gate manually reset by user.");
        }
        else if (sparam == "SOEA_CloseAllButton")
        {
            g_TradeManager.CloseAllPositions();
            Print("All positions manually closed by user.");
        }
    }
}

//+------------------------------------------------------------------+
//| END OF SOEA v4.1                                                 |
//+------------------------------------------------------------------+
