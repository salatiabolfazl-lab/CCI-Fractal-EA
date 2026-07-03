//+------------------------------------------------------------------+
//|                                                   CCI_Fractal_EA |
//|                       Version 1.0                                |
//|                        MetaTrader 5                              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

//-------------------------------------------------------------------
#include <Trade/Trade.mqh>

//-------------------------------------------------------------------
CTrade trade;

//===================================================================
// INPUTS
//===================================================================

input group "===== General ====="

input ulong   InpMagic                    = 2026070101;
input double  InpLots                     = 0.01;

input group "===== Indicators ====="

input int     InpCCIPeriod                = 9;

input group "===== Fractal StopLoss ====="

input int     InpFractalLookback          = 200;
input double  InpFractalSLBufferPips      = 20.0;

input group "===== Capital Protection ====="

input bool    InpEnableCapitalProtection  = true;
input double  InpCapitalProtectionUSD     = 10.0;

input group "===== Emergency Exit ====="

input bool    InpEnableEmergencyCCIExit   = true;

input group "===== Exit Confirmation ====="

input bool    InpEnableExitConfirmation   = true;

//===================================================================
// CONSTANTS
//===================================================================

#define CCI_UPPER_LEVEL   100.0
#define CCI_LOWER_LEVEL  -100.0

//===================================================================
// GLOBAL HANDLES
//===================================================================

int hCCI       = INVALID_HANDLE;
int hFractals  = INVALID_HANDLE;

//===================================================================
// POSITION STATE
//===================================================================

struct PositionState
{
   bool               Exists;

   ulong              Ticket;

   ENUM_POSITION_TYPE Type;

   double             Volume;

   double             EntryPrice;

   double             StopLoss;

   double             TakeProfit;

   double             Profit;

   datetime           EntryTime;

   datetime           EntryBarTime;
};

//===================================================================
// EA STATE
//===================================================================

struct EAState
{
   datetime CurrentBarTime;

   datetime PreviousBarTime;

   bool     NewBar;

   double   CurrentCCI;

   double   PreviousCCI;

   bool     BuyExitZoneReached;

   bool     SellExitZoneReached;

   bool     BuyCrossLocked;

   bool     SellCrossLocked;
};

//===================================================================
// GLOBAL STATES
//===================================================================

EAState State;

PositionState BuyPosition;

PositionState SellPosition;

//===================================================================
// PRICE HELPERS
//===================================================================

double Ask()
{
   return(SymbolInfoDouble(_Symbol,SYMBOL_ASK));
}
//-------------------------------------------------------------------
double Bid()
{
   return(SymbolInfoDouble(_Symbol,SYMBOL_BID));
}
//-------------------------------------------------------------------
double Pip()
{
   if(_Digits==3 || _Digits==5)
      return(_Point*10.0);

   return(_Point);
}
//-------------------------------------------------------------------
double NormalizePrice(double price)
{
   return(NormalizeDouble(price,_Digits));
}

//===================================================================
// RESET POSITION
//===================================================================

void ResetPosition(PositionState &pos)
{
   pos.Exists=false;

   pos.Ticket=0;

   pos.Type=WRONG_VALUE;

   pos.Volume=0.0;

   pos.EntryPrice=0.0;

   pos.StopLoss=0.0;

   pos.TakeProfit=0.0;

   pos.Profit=0.0;

   pos.EntryTime=0;

   pos.EntryBarTime=0;
}
//-------------------------------------------------------------------
void ResetAllPositions()
{
   ResetPosition(BuyPosition);

   ResetPosition(SellPosition);
}

//===================================================================
// ACCOUNT
//===================================================================

bool IsHedgingAccount()
{
   return(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==
          ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}
//-------------------------------------------------------------------
bool IsNettingAccount()
{
   return(!IsHedgingAccount());
}

//===================================================================
// BAR ENGINE
//===================================================================

bool UpdateBarState()
{
   datetime bar=iTime(_Symbol,_Period,0);

   if(bar!=State.CurrentBarTime)
   {
      State.PreviousBarTime=State.CurrentBarTime;

      State.CurrentBarTime=bar;

      State.NewBar=true;

      State.BuyCrossLocked=false;

      State.SellCrossLocked=false;

      return(true);
   }

   State.NewBar=false;

   return(false);
}

//===================================================================
// CCI ENGINE
//===================================================================

bool UpdateCCI()
{
   double buffer[];

   ArraySetAsSeries(buffer,true);

   if(CopyBuffer(hCCI,0,0,2,buffer)!=2)
      return(false);

   State.CurrentCCI=buffer[0];

   State.PreviousCCI=buffer[1];

   return(true);
}

//===================================================================
// FRACTAL HELPERS
//===================================================================

bool ReadFractalHigh(double &buffer[])
{
   ArraySetAsSeries(buffer,true);

   if(CopyBuffer(
      hFractals,
      0,
      2,
      InpFractalLookback,
      buffer)<=0)
      return(false);

   return(true);
}
//-------------------------------------------------------------------
bool ReadFractalLow(double &buffer[])
{
   ArraySetAsSeries(buffer,true);

   if(CopyBuffer(
      hFractals,
      1,
      2,
      InpFractalLookback,
      buffer)<=0)
      return(false);

   return(true);
}

//==================== END OF PART 1 ====================
//===================================================================
// POSITION ENGINE
//===================================================================

bool LoadPosition(PositionState &pos,const ulong ticket)
{
   if(ticket==0)
      return(false);

   if(!PositionSelectByTicket(ticket))
      return(false);

   pos.Exists=true;

   pos.Ticket=ticket;

   pos.Type=
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   pos.Volume=
      PositionGetDouble(POSITION_VOLUME);

   pos.EntryPrice=
      PositionGetDouble(POSITION_PRICE_OPEN);

   pos.StopLoss=
      PositionGetDouble(POSITION_SL);

   pos.TakeProfit=
      PositionGetDouble(POSITION_TP);

   pos.Profit=
      PositionGetDouble(POSITION_PROFIT);

   pos.EntryTime=
      (datetime)PositionGetInteger(POSITION_TIME);

   return(true);
}
//-------------------------------------------------------------------
void SyncPositions()
{
   ResetAllPositions();

   int total=PositionsTotal();

   for(int i=0;i<total;i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;

      ENUM_POSITION_TYPE type=
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      switch(type)
      {
         case POSITION_TYPE_BUY:

            if(!BuyPosition.Exists)
               LoadPosition(BuyPosition,ticket);

            break;

         case POSITION_TYPE_SELL:

            if(!SellPosition.Exists)
               LoadPosition(SellPosition,ticket);

            break;
      }
   }
}
//-------------------------------------------------------------------
bool HasBuy()
{
   return(BuyPosition.Exists);
}
//-------------------------------------------------------------------
bool HasSell()
{
   return(SellPosition.Exists);
}

//===================================================================
// CCI CROSS ENGINE
//===================================================================

bool CrossUp(
   const double previous,
   const double current,
   const double level)
{
   return(previous<level && current>=level);
}
//-------------------------------------------------------------------
bool CrossDown(
   const double previous,
   const double current,
   const double level)
{
   return(previous>level && current<=level);
}
//-------------------------------------------------------------------
bool IsBuyEntryCross()
{
   return CrossUp(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_LOWER_LEVEL);
}
//-------------------------------------------------------------------
bool IsSellEntryCross()
{
   return CrossDown(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_UPPER_LEVEL);
}
//-------------------------------------------------------------------
bool IsBuyExitCross()
{
   return CrossDown(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_UPPER_LEVEL);
}
//-------------------------------------------------------------------
bool IsSellExitCross()
{
   return CrossUp(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_LOWER_LEVEL);
}

//===================================================================
// EXIT ZONES
//===================================================================

void UpdateExitZones()
{
   if(State.CurrentCCI>CCI_UPPER_LEVEL)
      State.BuyExitZoneReached=true;

   if(State.CurrentCCI<CCI_LOWER_LEVEL)
      State.SellExitZoneReached=true;
}
//-------------------------------------------------------------------
void ResetBuyExitZone()
{
   State.BuyExitZoneReached=false;
}
//-------------------------------------------------------------------
void ResetSellExitZone()
{
   State.SellExitZoneReached=false;
}

//===================================================================
// ENTRY LOCK
//===================================================================

bool CanOpenBuy()
{
   if(HasBuy())
      return(false);

   if(State.BuyCrossLocked)
      return(false);

   return(true);
}
//-------------------------------------------------------------------
bool CanOpenSell()
{
   if(HasSell())
      return(false);

   if(State.SellCrossLocked)
      return(false);

   return(true);
}
//-------------------------------------------------------------------
void LockBuyEntry()
{
   State.BuyCrossLocked=true;
}
//-------------------------------------------------------------------
void LockSellEntry()
{
   State.SellCrossLocked=true;
}

//==================== END OF PART 2 ====================
//===================================================================
// FRACTAL ENGINE
//===================================================================

double GetNearestValidFractalLow(const double referencePrice)
{
   double buffer[];

   if(!ReadFractalLow(buffer))
      return(EMPTY_VALUE);

   double nearest=EMPTY_VALUE;

   for(int i=0;i<ArraySize(buffer);i++)
   {
      if(buffer[i]==EMPTY_VALUE)
         continue;

      if(buffer[i]>=referencePrice)
         continue;

      if(nearest==EMPTY_VALUE || buffer[i]>nearest)
         nearest=buffer[i];
   }

   return(nearest);
}
//-------------------------------------------------------------------
double GetNearestValidFractalHigh(const double referencePrice)
{
   double buffer[];

   if(!ReadFractalHigh(buffer))
      return(EMPTY_VALUE);

   double nearest=EMPTY_VALUE;

   for(int i=0;i<ArraySize(buffer);i++)
   {
      if(buffer[i]==EMPTY_VALUE)
         continue;

      if(buffer[i]<=referencePrice)
         continue;

      if(nearest==EMPTY_VALUE || buffer[i]<nearest)
         nearest=buffer[i];
   }

   return(nearest);
}

//===================================================================
// STOP LOSS ENGINE
//===================================================================

double StopBuffer()
{
   return(InpFractalSLBufferPips*Pip());
}
//-------------------------------------------------------------------
double CalculateBuyStopLoss(const double entryPrice)
{
   double fractal=
      GetNearestValidFractalLow(entryPrice);

   if(fractal!=EMPTY_VALUE)
      return NormalizePrice(
         fractal-StopBuffer());

   return NormalizePrice(
      entryPrice-StopBuffer());
}
//-------------------------------------------------------------------
double CalculateSellStopLoss(const double entryPrice)
{
   double fractal=
      GetNearestValidFractalHigh(entryPrice);

   if(fractal!=EMPTY_VALUE)
      return NormalizePrice(
         fractal+StopBuffer());

   return NormalizePrice(
      entryPrice+StopBuffer());
}
//-------------------------------------------------------------------
bool IsValidBuySL(const double sl)
{
   return(sl<Bid());
}
//-------------------------------------------------------------------
bool IsValidSellSL(const double sl)
{
   return(sl>Ask());
}
//-------------------------------------------------------------------
double GetBuyStopLoss(const double entryPrice)
{
   double sl=CalculateBuyStopLoss(entryPrice);

   if(!IsValidBuySL(sl))
      sl=NormalizePrice(
         entryPrice-StopBuffer());

   return(sl);
}
//-------------------------------------------------------------------
double GetSellStopLoss(const double entryPrice)
{
   double sl=CalculateSellStopLoss(entryPrice);

   if(!IsValidSellSL(sl))
      sl=NormalizePrice(
         entryPrice+StopBuffer());

   return(sl);
}

//===================================================================
// EXIT VALIDATION
//===================================================================

bool CanCloseBuy()
{
   if(!BuyPosition.Exists)
      return(false);

   if(State.CurrentBarTime==
      BuyPosition.EntryBarTime)
      return(false);

   if(InpEnableExitConfirmation)
   {
      if(!State.BuyExitZoneReached)
         return(false);
   }

   return(IsBuyExitCross());
}
//-------------------------------------------------------------------
bool CanCloseSell()
{
   if(!SellPosition.Exists)
      return(false);

   if(State.CurrentBarTime==
      SellPosition.EntryBarTime)
      return(false);

   if(InpEnableExitConfirmation)
   {
      if(!State.SellExitZoneReached)
         return(false);
   }

   return(IsSellExitCross());
}

//==================== END OF PART 3 ====================
//===================================================================
// TRADE ENGINE
//===================================================================

//-------------------------------------------------------------------
bool OpenBuy()
{
   if(!CanOpenBuy())
      return(false);

   double price=Ask();

   double sl=GetBuyStopLoss(price);

   trade.SetExpertMagicNumber(InpMagic);

   if(!trade.Buy(
      InpLots,
      _Symbol,
      0.0,
      sl,
      0.0,
      "CCI BUY"))
   {
      Print(__FUNCTION__,
            " RetCode=",
            trade.ResultRetcode());

      return(false);
   }

   SyncPositions();

   if(BuyPosition.Exists)
   {
      BuyPosition.EntryBarTime=
         State.CurrentBarTime;
   }

   ResetBuyExitZone();

   LockBuyEntry();

   return(true);
}

//-------------------------------------------------------------------
bool OpenSell()
{
   if(!CanOpenSell())
      return(false);

   double price=Bid();

   double sl=GetSellStopLoss(price);

   trade.SetExpertMagicNumber(InpMagic);

   if(!trade.Sell(
      InpLots,
      _Symbol,
      0.0,
      sl,
      0.0,
      "CCI SELL"))
   {
      Print(__FUNCTION__,
            " RetCode=",
            trade.ResultRetcode());

      return(false);
   }

   SyncPositions();

   if(SellPosition.Exists)
   {
      SellPosition.EntryBarTime=
         State.CurrentBarTime;
   }

   ResetSellExitZone();

   LockSellEntry();

   return(true);
}

//-------------------------------------------------------------------
bool CloseBuy()
{
   if(!BuyPosition.Exists)
      return(false);

   if(!PositionSelectByTicket(
      BuyPosition.Ticket))
   {
      SyncPositions();

      return(false);
   }

   if(!trade.PositionClose(
      BuyPosition.Ticket))
   {
      Print(__FUNCTION__,
            " RetCode=",
            trade.ResultRetcode());

      return(false);
   }

   SyncPositions();

   return(true);
}

//-------------------------------------------------------------------
bool CloseSell()
{
   if(!SellPosition.Exists)
      return(false);

   if(!PositionSelectByTicket(
      SellPosition.Ticket))
   {
      SyncPositions();

      return(false);
   }

   if(!trade.PositionClose(
      SellPosition.Ticket))
   {
      Print(__FUNCTION__,
            " RetCode=",
            trade.ResultRetcode());

      return(false);
   }

   SyncPositions();

   return(true);
}

//===================================================================
// CAPITAL PROTECTION
//===================================================================

void CapitalProtection()
{
   if(!InpEnableCapitalProtection)
      return;

   if(BuyPosition.Exists)
   {
      if(PositionSelectByTicket(
         BuyPosition.Ticket))
      {
         double profit=
            PositionGetDouble(
               POSITION_PROFIT);

         if(profit<=
            -InpCapitalProtectionUSD)
         {
            CloseBuy();

            return;
         }
      }
   }

   if(SellPosition.Exists)
   {
      if(PositionSelectByTicket(
         SellPosition.Ticket))
      {
         double profit=
            PositionGetDouble(
               POSITION_PROFIT);

         if(profit<=
            -InpCapitalProtectionUSD)
         {
            CloseSell();

            return;
         }
      }
   }
}

//===================================================================
// EMERGENCY EXIT
//===================================================================

bool IsEmergencyBuyExit()
{
   if(!InpEnableEmergencyCCIExit)
      return(false);

   return CrossDown(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_LOWER_LEVEL);
}

//-------------------------------------------------------------------
bool IsEmergencySellExit()
{
   if(!InpEnableEmergencyCCIExit)
      return(false);

   return CrossUp(
      State.PreviousCCI,
      State.CurrentCCI,
      CCI_UPPER_LEVEL);
}

//-------------------------------------------------------------------
void EmergencyExit()
{
   if(BuyPosition.Exists)
   {
      if(IsEmergencyBuyExit())
      {
         CloseBuy();

         return;
      }
   }

   if(SellPosition.Exists)
   {
      if(IsEmergencySellExit())
      {
         CloseSell();

         return;
      }
   }
}

//==================== END OF PART 4 ====================
//===================================================================
// RUNTIME ENGINE
//===================================================================

//-------------------------------------------------------------------
bool CheckEnvironment()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return(false);

   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return(false);

   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=
      SYMBOL_TRADE_MODE_FULL)
      return(false);

   return(true);
}

//-------------------------------------------------------------------
bool UpdateIndicators()
{
   if(!UpdateCCI())
      return(false);

   return(true);
}

//-------------------------------------------------------------------
void ProcessExitZones()
{
   UpdateExitZones();
}

//-------------------------------------------------------------------
void ProcessExits()
{
   ProcessExitZones();

   if(BuyPosition.Exists)
   {
      if(CanCloseBuy())
      {
         CloseBuy();
         return;
      }
   }

   if(SellPosition.Exists)
   {
      if(CanCloseSell())
      {
         CloseSell();
         return;
      }
   }
}

//-------------------------------------------------------------------
void ProcessEntries()
{
   if(IsBuyEntryCross())
   {
      OpenBuy();
      return;
   }

   if(IsSellEntryCross())
   {
      OpenSell();
      return;
   }
}

//-------------------------------------------------------------------
void ExecuteTradingCycle()
{
   SyncPositions();

   CapitalProtection();

   EmergencyExit();

   ProcessExits();

   if(State.NewBar)
      ProcessEntries();
}

//===================================================================
// INITIALIZATION
//===================================================================

//-------------------------------------------------------------------
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);

   hCCI=
      iCCI(
         _Symbol,
         _Period,
         InpCCIPeriod,
         PRICE_TYPICAL);

   if(hCCI==INVALID_HANDLE)
      return(INIT_FAILED);

   hFractals=
      iFractals(
         _Symbol,
         _Period);

   if(hFractals==INVALID_HANDLE)
      return(INIT_FAILED);

   ResetAllPositions();

   State.CurrentBarTime=
      iTime(_Symbol,_Period,0);

   State.PreviousBarTime=0;

   State.NewBar=false;

   State.BuyExitZoneReached=false;

   State.SellExitZoneReached=false;

   State.BuyCrossLocked=false;

   State.SellCrossLocked=false;

   return(INIT_SUCCEEDED);
}

//-------------------------------------------------------------------
void OnDeinit(const int reason)
{
   if(hCCI!=INVALID_HANDLE)
      IndicatorRelease(hCCI);

   if(hFractals!=INVALID_HANDLE)
      IndicatorRelease(hFractals);
}

//===================================================================
// MAIN LOOP
//===================================================================

//-------------------------------------------------------------------
void OnTick()
{
   if(!CheckEnvironment())
      return;

   UpdateBarState();

   if(!UpdateIndicators())
      return;

   ExecuteTradingCycle();
}

//==================== END OF PART 5 ====================
//===================================================================
// PART 6
// LOG ENGINE + DEBUG + COMMON HELPERS
//===================================================================

//-------------------------------------------------------------------
string PositionTypeToString(ENUM_POSITION_TYPE type)
{
   switch(type)
   {
      case POSITION_TYPE_BUY:
         return("BUY");

      case POSITION_TYPE_SELL:
         return("SELL");
   }

   return("UNKNOWN");
}

//-------------------------------------------------------------------
void PrintPosition(const PositionState &pos)
{
   if(!pos.Exists)
      return;

   Print("--------------------------------");

   Print("Ticket : ",pos.Ticket);

   Print("Type   : ",PositionTypeToString(pos.Type));

   Print("Volume : ",DoubleToString(pos.Volume,2));

   Print("Entry  : ",DoubleToString(pos.EntryPrice,_Digits));

   Print("SL     : ",DoubleToString(pos.StopLoss,_Digits));

   Print("Profit : ",DoubleToString(pos.Profit,2));

   Print("--------------------------------");
}

//-------------------------------------------------------------------
void PrintEAState()
{
   Print("============== EA STATE ==============");

   Print("Current CCI : ",
         DoubleToString(State.CurrentCCI,2));

   Print("Previous CCI : ",
         DoubleToString(State.PreviousCCI,2));

   Print("New Bar : ",
         State.NewBar);

   Print("Buy Exit Zone : ",
         State.BuyExitZoneReached);

   Print("Sell Exit Zone : ",
         State.SellExitZoneReached);

   Print("Buy Lock : ",
         State.BuyCrossLocked);

   Print("Sell Lock : ",
         State.SellCrossLocked);

   Print("======================================");
}

//-------------------------------------------------------------------
void PrintTradeResult()
{
   Print("Trade Result");

   Print("RetCode : ",
         trade.ResultRetcode());

   Print("Deal : ",
         trade.ResultDeal());

   Print("Order : ",
         trade.ResultOrder());

   Print("Price : ",
         DoubleToString(
            trade.ResultPrice(),
            _Digits));

   Print("Volume : ",
         DoubleToString(
            trade.ResultVolume(),
            2));
}

//-------------------------------------------------------------------
bool IsTradingAllowedNow()
{
   return(
      TerminalInfoInteger(
         TERMINAL_TRADE_ALLOWED)
      &&
      MQLInfoInteger(
         MQL_TRADE_ALLOWED)
      &&
      AccountInfoInteger(
         ACCOUNT_TRADE_ALLOWED)
   );
}

//-------------------------------------------------------------------
bool SymbolTradingEnabled()
{
   return(
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_MODE)
      ==
      SYMBOL_TRADE_MODE_FULL);
}

//-------------------------------------------------------------------
double CurrentSpreadPoints()
{
   return(
      (Ask()-Bid())/_Point);
}

//-------------------------------------------------------------------
double CurrentSpreadPips()
{
   return(
      CurrentSpreadPoints()/
      ((_Digits==3 || _Digits==5)?10.0:1.0));
}

//-------------------------------------------------------------------
void RefreshPositionProfit()
{
   if(BuyPosition.Exists)
   {
      if(PositionSelectByTicket(BuyPosition.Ticket))
      {
         BuyPosition.Profit=
            PositionGetDouble(POSITION_PROFIT);
      }
   }

   if(SellPosition.Exists)
   {
      if(PositionSelectByTicket(SellPosition.Ticket))
      {
         SellPosition.Profit=
            PositionGetDouble(POSITION_PROFIT);
      }
   }
}

//-------------------------------------------------------------------
void RefreshPositionStops()
{
   if(BuyPosition.Exists)
   {
      if(PositionSelectByTicket(BuyPosition.Ticket))
      {
         BuyPosition.StopLoss=
            PositionGetDouble(POSITION_SL);

         BuyPosition.TakeProfit=
            PositionGetDouble(POSITION_TP);
      }
   }

   if(SellPosition.Exists)
   {
      if(PositionSelectByTicket(SellPosition.Ticket))
      {
         SellPosition.StopLoss=
            PositionGetDouble(POSITION_SL);

         SellPosition.TakeProfit=
            PositionGetDouble(POSITION_TP);
      }
   }
}

//-------------------------------------------------------------------
void RefreshRuntimeData()
{
   RefreshPositionProfit();

   RefreshPositionStops();
}

//===================================================================
// END OF PART 6
//===================================================================
//===================================================================
// PART 7
// VALIDATION ENGINE + TRADE FILTERS + FINAL HELPERS
//===================================================================

//-------------------------------------------------------------------
bool IsValidVolume(double volume)
{
   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(volume<minLot)
      return(false);

   if(volume>maxLot)
      return(false);

   double steps=(volume-minLot)/stepLot;

   if(MathAbs(steps-MathRound(steps))>0.0000001)
      return(false);

   return(true);
}

//-------------------------------------------------------------------
double NormalizeVolume(double volume)
{
   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   volume=MathMax(minLot,volume);
   volume=MathMin(maxLot,volume);

   volume=MathFloor(volume/stepLot)*stepLot;

   return(NormalizeDouble(volume,2));
}

//-------------------------------------------------------------------
bool CheckStopsLevel(double sl,bool isBuy)
{
   int stopLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   if(stopLevel<=0)
      return(true);

   double distance;

   if(isBuy)
      distance=(Bid()-sl)/_Point;
   else
      distance=(sl-Ask())/_Point;

   return(distance>=stopLevel);
}

//-------------------------------------------------------------------
bool CheckFreezeLevel(double price)
{
   int freeze=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   if(freeze<=0)
      return(true);

   double current=(Ask()+Bid())*0.5;

   return(MathAbs(current-price)/_Point>freeze);
}

//-------------------------------------------------------------------
bool CheckMargin(double volume,ENUM_ORDER_TYPE type)
{
   double margin=0.0;

   double price=(type==ORDER_TYPE_BUY)?Ask():Bid();

   if(!OrderCalcMargin(
      type,
      _Symbol,
      volume,
      price,
      margin))
      return(false);

   return(AccountInfoDouble(ACCOUNT_FREEMARGIN)>=margin);
}

//-------------------------------------------------------------------
bool ValidateBuyRequest()
{
   double volume=NormalizeVolume(InpLots);

   if(!IsValidVolume(volume))
      return(false);

   double sl=GetBuyStopLoss(Ask());

   if(!CheckStopsLevel(sl,true))
      return(false);

   if(!CheckMargin(volume,ORDER_TYPE_BUY))
      return(false);

   return(true);
}

//-------------------------------------------------------------------
bool ValidateSellRequest()
{
   double volume=NormalizeVolume(InpLots);

   if(!IsValidVolume(volume))
      return(false);

   double sl=GetSellStopLoss(Bid());

   if(!CheckStopsLevel(sl,false))
      return(false);

   if(!CheckMargin(volume,ORDER_TYPE_SELL))
      return(false);

   return(true);
}

//-------------------------------------------------------------------
bool ValidateRuntime()
{
   if(!IsTradingAllowedNow())
      return(false);

   if(!SymbolTradingEnabled())
      return(false);

   return(true);
}

//-------------------------------------------------------------------
void RuntimeUpdate()
{
   RefreshRuntimeData();

   SyncPositions();
}

//-------------------------------------------------------------------
void RuntimeCycle()
{
   RuntimeUpdate();

   CapitalProtection();

   EmergencyExit();

   ProcessExits();

   if(State.NewBar)
      ProcessEntries();
}

//-------------------------------------------------------------------
void SafeTradingLoop()
{
   if(!ValidateRuntime())
      return;

   RuntimeCycle();
}

//===================================================================
// END OF PART 7
//===================================================================
//===================================================================
// PART 8
// FINAL EXECUTION ENGINE
//===================================================================

//-------------------------------------------------------------------
void ExecuteBuySignal()
{
   if(!State.NewBar)
      return;

   if(!CanOpenBuy())
      return;

   if(!IsBuyEntryCross())
      return;

   if(!ValidateBuyRequest())
      return;

   OpenBuy();
}

//-------------------------------------------------------------------
void ExecuteSellSignal()
{
   if(!State.NewBar)
      return;

   if(!CanOpenSell())
      return;

   if(!IsSellEntryCross())
      return;

   if(!ValidateSellRequest())
      return;

   OpenSell();
}

//-------------------------------------------------------------------
void ExecuteExitSignals()
{
   if(BuyPosition.Exists)
   {
      if(CanCloseBuy())
      {
         CloseBuy();
         return;
      }
   }

   if(SellPosition.Exists)
   {
      if(CanCloseSell())
      {
         CloseSell();
         return;
      }
   }
}

//-------------------------------------------------------------------
void ExecuteProtection()
{
   CapitalProtection();

   EmergencyExit();
}

//-------------------------------------------------------------------
void ExecuteEA()
{
   SyncPositions();

   RefreshRuntimeData();

   ExecuteProtection();

   ExecuteExitSignals();

   if(State.NewBar)
   {
      ExecuteBuySignal();

      ExecuteSellSignal();
   }
}

//===================================================================
// FINAL ONTICK
//===================================================================

void OnTick()
{
   if(!ValidateRuntime())
      return;

   UpdateBarState();

   if(!UpdateIndicators())
      return;

   ExecuteEA();
}

//===================================================================
// VERSION INFORMATION
//===================================================================

string Version()
{
   return("CCI Fractal EA Version 1.0");
}

//-------------------------------------------------------------------
void PrintHeader()
{
   static bool printed=false;

   if(printed)
      return;

   printed=true;

   Print("========================================");

   Print(Version());

   Print("Symbol : ",_Symbol);

   Print("TimeFrame : ",EnumToString(_Period));

   Print("Magic : ",InpMagic);

   Print("Lots : ",DoubleToString(InpLots,2));

   Print("CCI Period : ",InpCCIPeriod);

   Print("Capital Protection : ",InpCapitalProtectionUSD," USD");

   Print("========================================");
}

//===================================================================
// END OF FILE (Version 1.0)
//===================================================================