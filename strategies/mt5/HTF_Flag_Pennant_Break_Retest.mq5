//+------------------------------------------------------------------+
//| HTF Flag/Pennant Break-and-Retest EA                              |
//| Closed-candle logic; H1 execution with D1/H4 trend filter.        |
//| Review and test on demo before any live use.                      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Higher-Timeframe Flag/Pennant Break-and-Retest strategy"

#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES InpBiasTimeframe = PERIOD_D1;
input int InpFastEMA = 50;
input int InpSlowEMA = 200;
input int InpSlopeLookback = 5;
input bool InpUseADX = true;
input int InpADXPeriod = 14;
input double InpMinADX = 18.0;

input int InpPatternBars = 12;
input int InpImpulseBars = 8;
input double InpImpulseATR = 2.0;
input double InpMaxRetracement = 0.55;
input double InpMaxPatternATR = 2.5;
input double InpParallelTolerance = 0.12;
input int InpMinQuality = 60;

input double InpBreakoutBodyATR = 0.35;
input double InpRetestDistanceATR = 0.35;
input int InpRetestExpiryBars = 12;
input double InpConfirmBodyATR = 0.15;

input double InpRiskPercent = 0.5; // 0.1% to 1.0% equity
input double InpRewardRisk = 2.0;  // 1.5, 2.0, 2.5 or 3.0
input int InpATRPeriod = 14;
input double InpStopBufferATR = 0.2;
input double InpMaxDailyLossPercent = 2.0; // 0 disables
input int InpMaxTradesPerDay = 3;           // 0 disables

input int InpMaxSpreadPoints = 30;
input double InpMinATRPoints = 0.0; // 0 disables
input double InpMaxATRPoints = 0.0; // 0 disables
input bool InpUseSessionFilter = false;
input int InpSessionStartHour = 7; // broker/server time
input int InpSessionEndHour = 17;  // broker/server time
input ulong InpMagicNumber = 211121;

enum SetupState { WAIT_PATTERN=0, WAIT_RETEST=1, WAIT_CONFIRMATION=2 };
SetupState g_state = WAIT_PATTERN;
int g_direction = 0;
int g_barsAfterBreakout = 0;
int g_entriesToday = 0;
int g_dayKey = -1;
double g_dayStartEquity = 0.0;
double g_breakoutLevel = 0.0;
double g_retestSwing = 0.0;
double g_stop = 0.0;
double g_target = 0.0;
int g_quality = 0;
string g_pattern = "—";
datetime g_lastBarTime = 0;

int hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hADX = INVALID_HANDLE, hATR = INVALID_HANDLE;

bool ReadOne(int handle, int buffer, int shift, double &value)
{
   double data[];
   ArraySetAsSeries(data, true);
   if(CopyBuffer(handle, buffer, shift, 1, data) != 1) return false;
   value = data[0];
   return true;
}

double Mean(const double &v[], int count)
{
   double s=0.0;
   for(int i=0;i<count;i++) s+=v[i];
   return s/count;
}

double RegressionSlope(const MqlRates &rates[], int first, int count, bool useHigh)
{
   // rates[] is a series array: first is the newest bar in the selected pattern window.
   double sx=0, sy=0, sxx=0, sxy=0;
   for(int j=0;j<count;j++)
   {
      int idx=first + count - 1 - j; // oldest to newest
      double x=j;
      double y=useHigh ? rates[idx].high : rates[idx].low;
      sx+=x; sy+=y; sxx+=x*x; sxy+=x*y;
   }
   double den=count*sxx-sx*sx;
   if(MathAbs(den)<1e-10) return 0.0;
   return (count*sxy-sx*sy)/den;
}

double RegressionAtLast(const MqlRates &rates[], int first, int count, bool useHigh)
{
   double slope=RegressionSlope(rates,first,count,useHigh);
   double sum=0.0;
   for(int j=0;j<count;j++)
   {
      int idx=first+count-1-j;
      sum += (useHigh ? rates[idx].high : rates[idx].low) - slope*j;
   }
   double intercept=sum/count;
   return intercept+slope*(count-1);
}

double RegressionAtFirst(const MqlRates &rates[], int first, int count, bool useHigh)
{
   double slope=RegressionSlope(rates,first,count,useHigh);
   double sum=0.0;
   for(int j=0;j<count;j++)
   {
      int idx=first+count-1-j;
      sum += (useHigh ? rates[idx].high : rates[idx].low) - slope*j;
   }
   return sum/count;
}

void DrawTrend(const string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   ObjectDelete(0,name);
   if(ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2))
   {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   }
}

void DrawLevel(const string name, double price, color clr, ENUM_LINE_STYLE style=STYLE_DASH)
{
   ObjectDelete(0,name);
   if(ObjectCreate(0,name,OBJ_HLINE,0,0,price))
   {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   }
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,PERIOD_H1,0);
   if(t==0 || t==g_lastBarTime) return false;
   g_lastBarTime=t;
   return true;
}

int CurrentDayKey()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return dt.year*1000+dt.day_of_year;
}

void ResetDailyGuard()
{
   int key=CurrentDayKey();
   if(key!=g_dayKey)
   {
      g_dayKey=key;
      g_entriesToday=0;
      g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   }
}

bool DailyGuardOK()
{
   ResetDailyGuard();
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxDailyLossPercent>0 && g_dayStartEquity>0)
   {
      double loss=(g_dayStartEquity-eq)/g_dayStartEquity*100.0;
      if(loss>=InpMaxDailyLossPercent) return false;
   }
   if(InpMaxTradesPerDay>0 && g_entriesToday>=InpMaxTradesPerDay) return false;
   return true;
}

bool SessionOK()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpSessionStartHour==InpSessionEndHour) return true;
   if(InpSessionStartHour<InpSessionEndHour)
      return dt.hour>=InpSessionStartHour && dt.hour<InpSessionEndHour;
   return dt.hour>=InpSessionStartHour || dt.hour<InpSessionEndHour;
}

bool SpreadOK()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0) return false;
   return (ask-bid)/point <= InpMaxSpreadPoints;
}

bool HasOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   }
   return false;
}

int GetBias()
{
   double fast,slow,fastOld,adx;
   if(!ReadOne(hFast,0,1,fast) || !ReadOne(hSlow,0,1,slow) ||
      !ReadOne(hFast,0,1+InpSlopeLookback,fastOld)) return 0;
   if(InpUseADX && !ReadOne(hADX,2,1,adx)) return 0;
   if(InpUseADX && adx<InpMinADX) return 0;
   double htfClose=iClose(_Symbol,InpBiasTimeframe,1);
   if(htfClose==0) return 0;
   if(htfClose>fast && fast>slow && fast>fastOld) return 1;
   if(htfClose<fast && fast<slow && fast<fastOld) return -1;
   return 0;
}

bool GetATR(double &atr)
{
   return ReadOne(hATR,0,1,atr) && atr>0;
}

bool FindPattern(const MqlRates &r[], int bias, double atr,
                 bool &isFlag, bool &isPennant, double &upper, double &lower, int &quality)
{
   int n=InpPatternBars;
   // Pattern is rates[1..n], breakout candidate is rates[0].
   double hi=-DBL_MAX, lo=DBL_MAX;
   for(int i=1;i<=n;i++) { hi=MathMax(hi,r[i].high); lo=MathMin(lo,r[i].low); }
   double height=hi-lo;
   if(height<=0 || height>atr*InpMaxPatternATR) return false;

   int impulseEnd=n+1;
   int origin=n+InpImpulseBars+1;
   double bullImpulse=r[impulseEnd].close-r[origin].close;
   double bearImpulse=r[origin].close-r[impulseEnd].close;
   double impulse=(bias==1 ? bullImpulse : bearImpulse);
   double atrAtImpulse=0.0;
   if(!ReadOne(hATR,0,InpPatternBars+1,atrAtImpulse) || atrAtImpulse<=0) return false;
   if(impulse<atrAtImpulse*InpImpulseATR) return false;
   double retrace=(bias==1 ? (r[impulseEnd].high-lo) : (hi-r[impulseEnd].low))/impulse;
   if(retrace<0.0 || retrace>InpMaxRetracement) return false;

   double upperSlope=RegressionSlope(r,1,n,true);
   double lowerSlope=RegressionSlope(r,1,n,false);
   isFlag=false; isPennant=false;
   if(bias==1)
   {
      isFlag=upperSlope<0 && lowerSlope<0 && MathAbs(upperSlope-lowerSlope)<=atr*InpParallelTolerance;
      isPennant=upperSlope<0 && lowerSlope>0;
   }
   else if(bias==-1)
   {
      isFlag=upperSlope>0 && lowerSlope>0 && MathAbs(upperSlope-lowerSlope)<=atr*InpParallelTolerance;
      isPennant=upperSlope>0 && lowerSlope<0;
   }
   if(!isFlag && !isPennant) return false;

   upper=RegressionAtLast(r,1,n,true);
   lower=RegressionAtLast(r,1,n,false);
   double upperStart=RegressionAtFirst(r,1,n,true);
   double lowerStart=RegressionAtFirst(r,1,n,false);
   DrawTrend("MK_Flag_Upper_"+_Symbol+"_"+(string)InpMagicNumber,r[n].time,upperStart,r[1].time,upper,clrOrange);
   DrawTrend("MK_Flag_Lower_"+_Symbol+"_"+(string)InpMagicNumber,r[n].time,lowerStart,r[1].time,lower,clrAqua);
   double impulseScore=MathMin(30.0,30.0*impulse/(InpImpulseATR*atrAtImpulse*1.5));
   double pullbackScore=MathMax(0.0,25.0*(1.0-MathMin(retrace,1.0)));
   double compactScore=MathMax(0.0,25.0*(1.0-MathMin(height/(atr*InpMaxPatternATR),1.0)));
   quality=(int)MathRound(MathMin(100.0,impulseScore+pullbackScore+compactScore+20.0));
   return quality>=InpMinQuality;
}

double NormalizeVolume(double volume)
{
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) return 0;
   volume=MathFloor(volume/step)*step;
   volume=MathMax(0.0,MathMin(maxVol,volume));
   if(volume<minVol) return 0;
   int digits=2;
   if(step>=1.0) digits=0; else if(step>=0.1) digits=1; else if(step>=0.01) digits=2; else digits=3;
   return NormalizeDouble(volume,digits);
}

bool PlaceTrade(int direction, double entry, double stop)
{
   double riskCash=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0;
   double oneLotLoss=0.0;
   ENUM_ORDER_TYPE type=(direction==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,stop,oneLotLoss)) return false;
   oneLotLoss=MathAbs(oneLotLoss);
   if(oneLotLoss<=0) return false;
   double volume=NormalizeVolume(riskCash/oneLotLoss);
   if(volume<=0) return false;

   double riskDistance=MathAbs(entry-stop);
   double target=(direction==1 ? entry+riskDistance*InpRewardRisk : entry-riskDistance*InpRewardRisk);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   stop=NormalizeDouble(stop,digits);
   target=NormalizeDouble(target,digits);
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   bool ok=(direction==1 ? trade.Buy(volume,_Symbol,0.0,stop,target,g_pattern) :
                            trade.Sell(volume,_Symbol,0.0,stop,target,g_pattern));
   if(ok)
   {
      g_entriesToday++;
      DrawLevel("MK_Stop_"+_Symbol+"_"+(string)InpMagicNumber,stop,clrTomato);
      DrawLevel("MK_Target_"+_Symbol+"_"+(string)InpMagicNumber,target,clrLime);
      Comment(g_pattern," | Quality ",g_quality,"/100 | Risk ",DoubleToString(InpRiskPercent,2),"% | RR 1:",DoubleToString(InpRewardRisk,1));
   }
   else Print("Order rejected: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   return ok;
}

int OnInit()
{
   if(_Period!=PERIOD_H1 || InpPatternBars<5 || InpImpulseBars<3)
   {
      Print("Attach this EA to an H1 chart.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRiskPercent<0.1 || InpRiskPercent>1.0 ||
      (InpRewardRisk!=1.5 && InpRewardRisk!=2.0 && InpRewardRisk!=2.5 && InpRewardRisk!=3.0))
      return INIT_PARAMETERS_INCORRECT;

   hFast=iMA(_Symbol,InpBiasTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(_Symbol,InpBiasTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hADX=iADX(_Symbol,InpBiasTimeframe,InpADXPeriod);
   hATR=iATR(_Symbol,PERIOD_H1,InpATRPeriod);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hADX==INVALID_HANDLE || hATR==INVALID_HANDLE)
      return INIT_FAILED;
   ResetDailyGuard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFast!=INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow!=INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
}

void OnTick()
{
   if(!IsNewBar()) return;
   ResetDailyGuard();

   int need=InpPatternBars+InpImpulseBars+3;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,PERIOD_H1,1,need,rates)<need) return;

   double atr;
   if(!GetATR(atr)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double atrPoints=atr/point;
   if((InpMinATRPoints>0 && atrPoints<InpMinATRPoints) ||
      (InpMaxATRPoints>0 && atrPoints>InpMaxATRPoints)) return;
   int bias=GetBias();
   if(HasOurPosition()) return;

   if(g_state==WAIT_PATTERN)
   {
      if(bias==0 || !DailyGuardOK() || !SessionOK() || !SpreadOK()) return;
      bool flag=false,pennant=false;
      double upper=0,lower=0;
      int quality=0;
      if(!FindPattern(rates,bias,atr,flag,pennant,upper,lower,quality)) return;
      double body=MathAbs(rates[0].close-rates[0].open);
      if(body<atr*InpBreakoutBodyATR) return;

      if(bias==1 && rates[0].close>upper)
      {
         g_direction=1; g_breakoutLevel=upper; g_barsAfterBreakout=0;
         g_quality=quality; g_pattern=(flag ? "Bull Flag" : "Bull Pennant");
         g_state=WAIT_RETEST;
         DrawLevel("MK_Breakout_"+_Symbol+"_"+(string)InpMagicNumber,g_breakoutLevel,clrGold);
         Print(g_pattern," breakout confirmed. Quality ",quality);
      }
      else if(bias==-1 && rates[0].close<lower)
      {
         g_direction=-1; g_breakoutLevel=lower; g_barsAfterBreakout=0;
         g_quality=quality; g_pattern=(flag ? "Bear Flag" : "Bear Pennant");
         g_state=WAIT_RETEST;
         DrawLevel("MK_Breakout_"+_Symbol+"_"+(string)InpMagicNumber,g_breakoutLevel,clrGold);
         Print(g_pattern," breakout confirmed. Quality ",quality);
      }
      return;
   }

   if(g_state==WAIT_RETEST)
   {
      g_barsAfterBreakout++;
      if(g_barsAfterBreakout>InpRetestExpiryBars)
      {
         g_state=WAIT_PATTERN; return;
      }
      double tol=atr*InpRetestDistanceATR;
      if(g_direction==1)
      {
         if(rates[0].close<g_breakoutLevel-2.0*tol) { g_state=WAIT_PATTERN; return; }
         if(rates[0].low<=g_breakoutLevel+tol && rates[0].close>=g_breakoutLevel-tol)
         {
            g_retestSwing=rates[0].low;
            g_state=WAIT_CONFIRMATION;
         }
      }
      else if(g_direction==-1)
      {
         if(rates[0].close>g_breakoutLevel+2.0*tol) { g_state=WAIT_PATTERN; return; }
         if(rates[0].high>=g_breakoutLevel-tol && rates[0].close<=g_breakoutLevel+tol)
         {
            g_retestSwing=rates[0].high;
            g_state=WAIT_CONFIRMATION;
         }
      }
      return;
   }

   if(g_state==WAIT_CONFIRMATION)
   {
      g_barsAfterBreakout++;
      if(g_barsAfterBreakout>InpRetestExpiryBars) { g_state=WAIT_PATTERN; return; }
      double body=MathAbs(rates[0].close-rates[0].open);
      if(body<atr*InpConfirmBodyATR) return;
      if(!DailyGuardOK() || !SessionOK() || !SpreadOK()) return;

      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(g_direction==1 && rates[0].close>rates[0].open && rates[0].close>g_breakoutLevel)
      {
         double stop=g_retestSwing-atr*InpStopBufferATR;
         if(stop<bid) PlaceTrade(1,ask,stop);
         g_state=WAIT_PATTERN;
      }
      else if(g_direction==-1 && rates[0].close<rates[0].open && rates[0].close<g_breakoutLevel)
      {
         double stop=g_retestSwing+atr*InpStopBufferATR;
         if(stop>ask) PlaceTrade(-1,bid,stop);
         g_state=WAIT_PATTERN;
      }
   }
}
