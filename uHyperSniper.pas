unit uHyperSniper;

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;

const
  NO_OPEN = 0;
  LONG_POS    = 1;
  SHORT_POS   = 2;

type
  TEMAStackData = record
    Pts: Integer;
    EMA9: Double;
    EMA21: Double;
    EMA50: Double;
    EMA200: Double;
    LTBull: Boolean;
    LTBear: Boolean;
  end;

  TMACDData = record
    Pts: Integer;
    Histogram: Double;
    HistogramPrev: Double;
    BullDiv: Boolean;
    BearDiv: Boolean;
  end;

  TRSIData = record
    Pts: Integer;
    RSI: Double;
    PrevRSI: Double;
    ExtremeOS: Boolean;
    ExtremeOB: Boolean;
  end;

  TStochData = record
    Pts: Integer;
    PctK: Double;
    PctD: Double;
  end;

  TBBData = record
    Pts: Integer;
    PctB: Double;
    Bandwidth: Double;
    AvgBandwidth: Double;
    Squeeze: Boolean;
    SqueezeBreakoutUp: Boolean;
    SqueezeBreakoutDown: Boolean;
  end;

  TOBVData = record
    Pts: Integer;
    OBV: Double;
    OBVEMA: Double;
  end;

  TADXData = record
    ADX: Double;
    PlusDI: Double;
    MinusDI: Double;
    ADXRising: Boolean;
  end;

  TSupertrendData = record
    Trend: string; // 'BULL', 'BEAR', 'NEUTRAL'
    Line: Double;
  end;

  TVolumeDeltaData = record
    Delta: Double;
    Ratio: Double;
  end;

  TFVGData = record
    Pts: Integer;
    BullFVGAbove: Double;
    BullFVGSize: Double;
    BearFVGBelow: Double;
    BearFVGSize: Double;
  end;

  TDecisionDetails = record
    Price: Double;
    Score: Integer;
    Flags: TArray<string>;
    Filters: TArray<string>;
    EMA: TEMAStackData;
    MACD: TMACDData;
    RSI: TRSIData;
    Stoch: TStochData;
    BB: TBBData;
    OBV: TOBVData;
    ADX: TADXData;
    Supertrend: TSupertrendData;
    MTF4h: string;
    MTFD: string;
    Chop: Double;
    MS: string;
    OIPctChange: Double;
    OBI: Double;
    VDRatio: Double;
  end;

function TradingDecision(
  const Closes1H, Highs1H, Lows1H, Volumes1H: TArray<Double>;
  const Closes4H, Highs4H, Lows4H: TArray<Double>;
  const ClosesD, HighsD, LowsD: TArray<Double>;
  out Details: TDecisionDetails;
  MinutesTo4hClose: Integer = 60;
  ReturnDetails: Boolean = False;
  UTCHour: Integer = -1;
  OrderBookImbalance: Double = 1.0;
  VDRatio: Double = 1.0;
  const OI1H: TArray<Double> = nil;
  FundingRate: Double = 0.0;
  MajorBias: string = 'NEUTRAL';
  VolClimaxMult: Double = 3.0;
  ScoreThresholdTrend: Integer = 6;
  ScoreThresholdRange: Integer = 7;
  SessionStart: Integer = 8;
  SessionEnd: Integer = 20;
  ExtremeScore: Integer = 10
): Integer;

function CalcEMA(const Values: TArray<Double>; Period: Integer): TArray<Double>;
function CalcSMA(const Values: TArray<Double>; Period: Integer): TArray<Double>;
function CalcRSIValue(const Closes: TArray<Double>; Period: Integer = 14): Double;

function CalcEMAStack(const Closes: TArray<Double>): TEMAStackData;
function CalcMACD(const Closes: TArray<Double>): TMACDData;
function CalcRSI(const Closes: TArray<Double>; Period: Integer = 14): TRSIData;
function CalcStochastic(const Closes, Highs, Lows: TArray<Double>; N: Integer = 14): TStochData;
function CalcBB(const Closes, Volumes: TArray<Double>; N: Integer = 20): TBBData;
function CalcOBV(const Closes, Volumes: TArray<Double>): TOBVData;
function CalcATR(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): TArray<Double>;
function CalcAtrEma(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 50): TArray<Double>;
function CalcADX(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): TADXData;
function CalcSupertrend(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 10; Multiplier: Double = 3.0): TSupertrendData;
function CalcChop(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): Double;
function CalcMarketStructure(const Highs, Lows: TArray<Double>; Period: Integer = 5): string;
function CalcLiquiditySweep(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 20): string;
function CalcFVG(const Highs, Lows, Closes: TArray<Double>; Lookback: Integer = 15): TFVGData;
function CalcMTFBias(const Closes, Highs, Lows: TArray<Double>): string;

implementation

function CalcEMA(const Values: TArray<Double>; Period: Integer): TArray<Double>;
var
  K, Sum: Double;
  I: Integer;
begin
  SetLength(Result, Length(Values));
  if Length(Values) < Period then
  begin
    for I := 0 to Length(Values) - 1 do
      Result[I] := 0.0;
    Exit;
  end;

  K := 2.0 / (Period + 1);
  for I := 0 to Length(Values) - 1 do
    Result[I] := 0.0;

  Sum := 0.0;
  for I := 0 to Period - 1 do
    Sum := Sum + Values[I];

  Result[Period - 1] := Sum / Period;

  for I := 0 to Period - 2 do
    Result[I] := 0.0;

  for I := Period to Length(Values) - 1 do
    Result[I] := Values[I] * K + Result[I - 1] * (1.0 - K);
end;

function CalcSMA(const Values: TArray<Double>; Period: Integer): TArray<Double>;
var
  I, J: Integer;
  Sum: Double;
begin
  SetLength(Result, Length(Values));
  for I := 0 to Length(Values) - 1 do
    Result[I] := 0.0;
  
  for I := Period - 1 to Length(Values) - 1 do
  begin
    Sum := 0.0;
    for J := I - Period + 1 to I do
      Sum := Sum + Values[J];
    Result[I] := Sum / Period;
  end;
end;

function CalcRSIValue(const Closes: TArray<Double>; Period: Integer = 14): Double;
var
  Changes: TArray<Double>;
  AvgGain, AvgLoss, RS, CurrChange: Double;
  I: Integer;
begin
  if Length(Closes) < Period + 1 then
     Exit(50.0);
  
  SetLength(Changes, Length(Closes) - 1);
  for I := 1 to Length(Closes) - 1 do
    Changes[I - 1] := Closes[I] - Closes[I - 1];
    
  AvgGain := 0.0;
  AvgLoss := 0.0;
  
  for I := 0 to Period - 1 do
  begin
    if Changes[I] > 0 then
      AvgGain := AvgGain + Changes[I]
    else AvgLoss := AvgLoss + Abs(Changes[I]);
  end;
  AvgGain := AvgGain / Period;
  AvgLoss := AvgLoss / Period;
  
  for I := Period to Length(Changes) - 1 do
  begin
    CurrChange := Changes[I];
    if CurrChange > 0 then
    begin
      AvgGain := (AvgGain * (Period - 1) + CurrChange) / Period;
      AvgLoss := (AvgLoss * (Period - 1)) / Period;
    end
    else
    begin
      AvgGain := (AvgGain * (Period - 1)) / Period;
      AvgLoss := (AvgLoss * (Period - 1) + Abs(CurrChange)) / Period;
    end;
  end;
  
  if AvgLoss = 0 then Exit(100.0);
  RS := AvgGain / AvgLoss;
  Result := 100.0 - (100.0 / (1.0 + RS));
end;

function CalcEMAStack(const Closes: TArray<Double>): TEMAStackData;
var
  EMA9_Arr, EMA21_Arr, EMA50_Arr, EMA200_Arr: TArray<Double>;
begin
  EMA9_Arr := CalcEMA(Closes, 9);
  EMA21_Arr := CalcEMA(Closes, 21);
  EMA50_Arr := CalcEMA(Closes, 50);
  EMA200_Arr := CalcEMA(Closes, 200);

  Result.EMA9 := EMA9_Arr[High(EMA9_Arr)];
  Result.EMA21 := EMA21_Arr[High(EMA21_Arr)];
  Result.EMA50 := EMA50_Arr[High(EMA50_Arr)];
  Result.EMA200 := EMA200_Arr[High(EMA200_Arr)];

  if (Result.EMA9 > Result.EMA21) and (Result.EMA21 > Result.EMA50) then
    Result.Pts := 2
  else if (Result.EMA9 < Result.EMA21) and (Result.EMA21 < Result.EMA50) then
    Result.Pts := -2
  else
    Result.Pts := 0;

  Result.LTBull := Result.EMA50 > Result.EMA200;
  Result.LTBear := Result.EMA50 < Result.EMA200;
end;

function CalcMACD(const Closes: TArray<Double>): TMACDData;
var
  EMA12, EMA26, MACDLine, Signal, Histogram: TArray<Double>;
  Win, Mid, I: Integer;
  HCurr, HPrev: Double;
  CWin, HWin: TArray<Double>;
  CLo1, CLo2, HLo1, HLo2, CHi1, CHi2, HHi1, HHi2: Double;

  function MinVal(const Arr: TArray<Double>; StartIdx, EndIdx: Integer): Double;
  var K: Integer;
  begin
    Result := Arr[StartIdx];
    for K := StartIdx + 1 to EndIdx do if Arr[K] < Result then Result := Arr[K];
  end;

  function MaxVal(const Arr: TArray<Double>; StartIdx, EndIdx: Integer): Double;
  var K: Integer;
  begin
    Result := Arr[StartIdx];
    for K := StartIdx + 1 to EndIdx do
      if Arr[K] > Result then
        Result := Arr[K];
  end;

begin
  Result.Pts := 0;
  Result.BullDiv := False;
  Result.BearDiv := False;
  if Length(Closes) < 26 then
    Exit;

  EMA12 := CalcEMA(Closes, 12);
  EMA26 := CalcEMA(Closes, 26);
  
  SetLength(MACDLine, Length(Closes));
  for I := 0 to Length(Closes) - 1 do
    MACDLine[I] := EMA12[I] - EMA26[I];

  Signal := CalcEMA(MACDLine, 9);

  SetLength(Histogram, Length(Closes));
  for I := 0 to Length(Closes) - 1 do
    Histogram[I] := MACDLine[I] - Signal[I];

  HCurr := Histogram[High(Histogram)];
  if Length(Histogram) >= 2 then
    HPrev := Histogram[High(Histogram) - 1]
  else
    HPrev := 0.0;

  if (HCurr > 0) and (HCurr > HPrev) then
    Result.Pts := 2
  else if (HCurr > 0) and (HCurr <= HPrev) then
    Result.Pts := 1
  else if (HCurr < 0) and (HCurr > HPrev) then
    Result.Pts := -1
  else
    Result.Pts := -2;
  
  Result.Histogram := HCurr;
  Result.HistogramPrev := HPrev;

  Win := 20;
  if (Length(Closes) >= Win) and (Length(Histogram) >= Win) then
  begin
    SetLength(CWin, Win);
    SetLength(HWin, Win);
    for I := 0 to Win - 1 do
    begin
      CWin[I] := Closes[Length(Closes) - Win + I];
      HWin[I] := Histogram[Length(Histogram) - Win + I];
    end;
    
    Mid := Win div 2;
    CLo1 := MinVal(CWin, 0, Mid - 1);
    CLo2 := MinVal(CWin, Mid, Win - 1);
    HLo1 := MinVal(HWin, 0, Mid - 1);
    HLo2 := MinVal(HWin, Mid, Win - 1);
    
    CHi1 := MaxVal(CWin, 0, Mid - 1);
    CHi2 := MaxVal(CWin, Mid, Win - 1);
    HHi1 := MaxVal(HWin, 0, Mid - 1);
    HHi2 := MaxVal(HWin, Mid, Win - 1);
    
    Result.BullDiv := (CLo2 < CLo1) and (HLo2 > HLo1);
    Result.BearDiv := (CHi2 > CHi1) and (HHi2 < HHi1);
  end;
end;

function CalcRSI(const Closes: TArray<Double>; Period: Integer = 14): TRSIData;
var
  PrevCloses: TArray<Double>;
  I: Integer;
begin
  Result.RSI := CalcRSIValue(Closes, Period);
  if Length(Closes) > Period + 1 then
  begin
    SetLength(PrevCloses, Length(Closes) - 1);
    for I := 0 to Length(Closes) - 2 do
      PrevCloses[I] := Closes[I];
    Result.PrevRSI := CalcRSIValue(PrevCloses, Period);
  end
  else
    Result.PrevRSI := 50.0;

  if (Result.RSI > 55) and (Result.RSI > Result.PrevRSI) then
    Result.Pts := 1
  else if (Result.RSI > 30) and (Result.PrevRSI < 30) then
    Result.Pts := 1
  else if (Result.RSI < 45) and (Result.RSI < Result.PrevRSI) then
    Result.Pts := -1
  else if (Result.RSI < 70) and (Result.PrevRSI > 70) then
    Result.Pts := -1
  else
    Result.Pts := 0;
  
  Result.ExtremeOS := Result.RSI < 25;
  Result.ExtremeOB := Result.RSI > 75;
end;

function CalcStochastic(const Closes, Highs, Lows: TArray<Double>; N: Integer = 14): TStochData;
var
  KRaw, KLine, DLine: TArray<Double>;
  I, J: Integer;
  Lo, Hi, Rng: Double;
  KCurr, DCurr, KPrev, DPrev: Double;
  CrossUp, CrossDown: Boolean;
begin
  if Length(Closes) < N + 6 then
  begin
    Result.Pts := 0;
    Result.PctK := 50.0;
    Result.PctD := 50.0;
    Exit;
  end;

  SetLength(KRaw, Length(Closes) - N + 1);
  for I := N - 1 to Length(Closes) - 1 do
  begin
    Lo := Lows[I - N + 1];
    Hi := Highs[I - N + 1];
    for J := I - N + 2 to I do
    begin
      if Lows[J] < Lo then
        Lo := Lows[J];
      if Highs[J] > Hi then
        Hi := Highs[J];
    end;

    Rng := Hi - Lo;
    if Rng <> 0 then
      KRaw[I - N + 1] := ((Closes[I] - Lo) / Rng) * 100.0
    else
      KRaw[I - N + 1] := 50.0;
  end;

  KLine := CalcSMA(KRaw, 3);
  DLine := CalcSMA(KLine, 3);

  KCurr := KLine[High(KLine)];
  DCurr := DLine[High(DLine)];
  if Length(KLine) >= 2 then KPrev := KLine[High(KLine)-1] else KPrev := KCurr;
  if Length(DLine) >= 2 then
    DPrev := DLine[High(DLine)-1] else DPrev := DCurr;

  CrossUp := (KPrev < DPrev) and (KCurr > DCurr);
  CrossDown := (KPrev > DPrev) and (KCurr < DCurr);

  if CrossUp and (KCurr < 25) then
     Result.Pts := 1
  else if (KCurr > DCurr) and (KCurr > 50) and (DCurr > 50) then
     Result.Pts := 1
  else if CrossDown and (KCurr > 75) then
     Result.Pts := -1
  else if (KCurr < DCurr) and (KCurr < 50) and (DCurr < 50) then
     Result.Pts := -1
  else
     Result.Pts := 0;
  
  Result.PctK := KCurr;
  Result.PctD := DCurr;
end;

function CalcBB(const Closes, Volumes: TArray<Double>; N: Integer = 20): TBBData;
var
  BWHistory: TArray<Double>;
  SumX, SumX2, M, VarX, S, U, Lo, BW, OldVal: Double;
  I: Integer;
  AvgBW, MLast, SLast, ULast, LoLast, Rng, RSIV: Double;
  VolAvg: Double;
  VolHigh, SqueezeUp, SqueezeDn: Boolean;
  RecentBWCount, SqueezeCount: Integer;
begin
  if (Length(Closes) < N + 20) or (Length(Volumes) < 20) then
  begin
    Result.Pts := 0;
    Result.PctB := 0.5;
    Result.Bandwidth := 0.0;
    Result.AvgBandwidth := 0.0;
    Result.Squeeze := False;
    Result.SqueezeBreakoutUp := False;
    Result.SqueezeBreakoutDown := False;
    Exit;
  end;

  SetLength(BWHistory, Length(Closes) - N + 1);
  SumX := 0.0;
  SumX2 := 0.0;
  for I := 0 to N - 2 do
  begin
    SumX := SumX + Closes[I];
    SumX2 := SumX2 + Sqr(Closes[I]);
  end;

  for I := N - 1 to Length(Closes) - 1 do
  begin
    SumX := SumX + Closes[I];
    SumX2 := SumX2 + Sqr(Closes[I]);

    M := SumX / N;
    VarX := (SumX2 / N) - Sqr(M);
    if VarX < 0 then
      VarX := 0.0;
    S := Sqrt(VarX);

    U := M + 2 * S;
    Lo := M - 2 * S;
    if M <> 0 then
      BW := ((U - Lo) / M) * 100.0 else BW := 0.0;
    BWHistory[I - N + 1] := BW;

    OldVal := Closes[I - N + 1];
    SumX := SumX - OldVal;
    SumX2 := SumX2 - Sqr(OldVal);
  end;

  AvgBW := 0.0;
  for I := Length(BWHistory) - 20 to Length(BWHistory) - 1 do
    AvgBW := AvgBW + BWHistory[I];
  AvgBW := AvgBW / 20.0;

  Result.Bandwidth := BWHistory[High(BWHistory)];

  MLast := 0.0;
  for I := Length(Closes) - N to Length(Closes) - 1 do
    MLast := MLast + Closes[I];
  MLast := MLast / N;

  SLast := 0.0;
  for I := Length(Closes) - N to Length(Closes) - 1 do
    SLast := SLast + Sqr(Closes[I] - MLast);

  SLast := Sqrt(SLast / N);

  ULast := MLast + 2 * SLast;
  LoLast := MLast - 2 * SLast;
  Rng := ULast - LoLast;

  if Rng <> 0 then Result.PctB := (Closes[High(Closes)] - LoLast) / Rng else Result.PctB := 0.5;

  Result.Squeeze := True;
  RecentBWCount := Min(10, Length(BWHistory));
  if RecentBWCount < 10 then Result.Squeeze := False
  else
  begin
    for I := Length(BWHistory) - 10 to Length(BWHistory) - 1 do
      if BWHistory[I] >= AvgBW then
      begin
        Result.Squeeze := False;
        Break;
      end;
  end;

  VolAvg := 0.0;
  for I := Length(Volumes) - 20 to Length(Volumes) - 1 do VolAvg := VolAvg + Volumes[I];
  VolAvg := VolAvg / 20.0;
  VolHigh := Volumes[High(Volumes)] > 1.5 * VolAvg;

  SqueezeUp := Result.Squeeze and (Closes[High(Closes)] > ULast) and VolHigh;
  SqueezeDn := Result.Squeeze and (Closes[High(Closes)] < LoLast) and VolHigh;

  Result.SqueezeBreakoutUp := SqueezeUp;
  Result.SqueezeBreakoutDown := SqueezeDn;

  RSIV := CalcRSIValue(Closes);
  if (Result.PctB < 0.05) and (RSIV < 35) then
    Result.Pts := 1
  else if SqueezeUp then
    Result.Pts := 1
  else if (Result.PctB > 0.95) and (RSIV > 65) then
    Result.Pts := -1
  else if SqueezeDn then
    Result.Pts := -1
  else
    Result.Pts := 0;

  Result.AvgBandwidth := AvgBW;
end;

function CalcOBV(const Closes, Volumes: TArray<Double>): TOBVData;
var
  OBV, OBVEMAArr: TArray<Double>;
  I: Integer;
  OBVCurr, OBVPrev, OBVEMA: Double;
  OBVRising, OBVAboveEMA, PriceFlat, PriceRising, OBVDiv: Boolean;
begin
  if Length(Closes) < 22 then
  begin
    Result.Pts := 0; Result.OBV := 0.0; Result.OBVEMA := 0.0;
    Exit;
  end;

  SetLength(OBV, Length(Closes));
  OBV[0] := 0.0;
  for I := 1 to High(Closes) do
  begin
    if Closes[I] > Closes[I - 1] then
      OBV[I] := OBV[I - 1] + Volumes[I]
    else if Closes[I] < Closes[I - 1] then
      OBV[I] := OBV[I - 1] - Volumes[I]
    else OBV[I] := OBV[I - 1];
  end;

  OBVEMAArr := CalcEMA(OBV, 20);
  OBVCurr := OBV[High(OBV)];
  OBVPrev := OBV[High(OBV) - 1];
  OBVEMA := OBVEMAArr[High(OBVEMAArr)];

  OBVRising := OBVCurr > OBVPrev;
  OBVAboveEMA := OBVCurr > OBVEMA;

  if Closes[High(Closes)-1] = 0 then
    PriceFlat := False
  else
    PriceFlat := (Abs(Closes[High(Closes)] - Closes[High(Closes)-1]) / Closes[High(Closes)-1]) < 0.001;

  PriceRising := Closes[High(Closes)] > Closes[High(Closes)-1];
  OBVDiv := PriceRising and not OBVRising;

  if OBVAboveEMA and OBVRising then
    Result.Pts := 1
  else if OBVRising and PriceFlat then
    Result.Pts := 1
  else if not OBVAboveEMA and not OBVRising then
    Result.Pts := -1
  else if OBVDiv then
    Result.Pts := -1
  else
    Result.Pts := 0;

  Result.OBV := OBVCurr;
  Result.OBVEMA := OBVEMA;
end;

function CalcATR(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): TArray<Double>;
var
  TR: TArray<Double>;
  Sum: Double;
  I: Integer;
begin
  SetLength(Result, Length(Closes));
  if Length(Closes) < Period then
  begin
    for I := 0 to High(Result) do
      Result[I] := 0.0;
    Exit;
  end;

  SetLength(TR, Length(Closes));
  TR[0] := Highs[0] - Lows[0];
  for I := 1 to High(Closes) do
    TR[I] := Max(Highs[I] - Lows[I], Max(Abs(Highs[I] - Closes[I-1]), Abs(Lows[I] - Closes[I-1])));

  for I := 0 to High(Result) do
    Result[I] := 0.0;
  Sum := 0.0;
  for I := 0 to Period - 1 do
    Sum := Sum + TR[I];
  Result[Period - 1] := Sum / Period;

  for I := Period to High(Closes) do
    Result[I] := (Result[I-1] * (Period - 1) + TR[I]) / Period;
end;

function CalcAtrEma(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 50): TArray<Double>;
var
  ATR: TArray<Double>;
  Sum, K: Double;
  I: Integer;
begin
  ATR := CalcATR(Highs, Lows, Closes, 14);
  SetLength(Result, Length(ATR));
  for I := 0 to High(Result) do
    Result[I] := 0.0;
  if Length(ATR) < Period then
    Exit;

  Sum := 0.0;
  for I := 0 to Period - 1 do
    Sum := Sum + ATR[I];

  Result[Period - 1] := Sum / Period;
  
  K := 2.0 / (Period + 1);
  for I := Period to High(ATR) do
    Result[I] := ATR[I] * K + Result[I-1] * (1.0 - K);
end;

function CalcADX(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): TADXData;
var
  TR, UpMove, DownMove: TArray<Double>;
  I: Integer;
  DMPlus, DMMinus: Double;
  TRS, PlusDMS, MinusDMS: TArray<Double>;
  PlusDI, MinusDI, DX, ADXSeries: TArray<Double>;
  Denom, Sum: Double;

  function WilderSmooth(const Data: TArray<Double>; P: Integer): TArray<Double>;
  var K: Integer;
  begin
    SetLength(Result, Length(Data));
    for K := 0 to High(Result) do
      Result[K] := 0.0;
    if Length(Data) <= P then
      Exit;
    Sum := 0.0;

    for K := 1 to P do Sum := Sum + Data[K];
    Result[P] := Sum;
    for K := P + 1 to High(Data) do
      Result[K] := Result[K-1] - (Result[K-1] / P) + Data[K];
  end;

begin
  Result.ADX := 0.0; Result.PlusDI := 0.0; Result.MinusDI := 0.0; Result.ADXRising := False;
  if Length(Closes) < 2 * Period then
    Exit;

  SetLength(TR, Length(Closes));
  SetLength(UpMove, Length(Closes));
  SetLength(DownMove, Length(Closes));

  for I := 1 to High(Closes) do
  begin
    TR[I] := Max(Highs[I] - Lows[I], Max(Abs(Highs[I] - Closes[I-1]), Abs(Lows[I] - Closes[I-1])));
    DMPlus := Highs[I] - Highs[I-1];
    DMMinus := Lows[I-1] - Lows[I];
    if (DMPlus > DMMinus) and (DMPlus > 0) then
      UpMove[I] := DMPlus
    else
      UpMove[I] := 0.0;
    if (DMMinus > DMPlus) and (DMMinus > 0) then
      DownMove[I] := DMMinus
    else
    DownMove[I] := 0.0;
  end;

  TRS := WilderSmooth(TR, Period);
  PlusDMS := WilderSmooth(UpMove, Period);
  MinusDMS := WilderSmooth(DownMove, Period);

  SetLength(PlusDI, Length(Closes));
  SetLength(MinusDI, Length(Closes));
  for I := 0 to High(Closes) do
  begin
    if TRS[I] <> 0 then
      PlusDI[I] := 100.0 * (PlusDMS[I] / TRS[I])
    else
      PlusDI[I] := 0.0;
    if TRS[I] <> 0 then
      MinusDI[I] := 100.0 * (MinusDMS[I] / TRS[I]) else MinusDI[I] := 0.0;
  end;

  SetLength(DX, Length(Closes));
  for I := 0 to High(Closes) do
    DX[I] := 0.0;

  for I := Period to High(Closes) do
  begin
    Denom := PlusDI[I] + MinusDI[I];
    if Denom <> 0 then
      DX[I] := 100.0 * Abs(PlusDI[I] - MinusDI[I]) / Denom
    else DX[I] := 0.0;
  end;

  SetLength(ADXSeries, Length(Closes));
  for I := 0 to High(Closes) do ADXSeries[I] := 0.0;

  if Length(DX) >= 2 * Period then
  begin
    Sum := 0.0;
    for I := Period to 2 * Period - 1 do Sum := Sum + DX[I];
    ADXSeries[2 * Period - 1] := Sum / Period;
    for I := 2 * Period to High(Closes) do
      ADXSeries[I] := (ADXSeries[I-1] * (Period - 1) + DX[I]) / Period;
  end;

  if Length(ADXSeries) > 1 then
    Result.ADXRising := ADXSeries[High(ADXSeries)] > ADXSeries[High(ADXSeries)-1];

  Result.ADX := ADXSeries[High(ADXSeries)];
  Result.PlusDI := PlusDI[High(PlusDI)];
  Result.MinusDI := MinusDI[High(MinusDI)];
end;

function CalcSupertrend(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 10; Multiplier: Double = 3.0): TSupertrendData;
var
  ATR, HL2, LongStop, ShortStop: TArray<Double>;
  Trend: TArray<Integer>;
  I: Integer;
  CurrLong, PrevLong, CurrShort, PrevShort: Double;
begin
  if Length(Closes) < Period then
  begin
    Result.Trend := 'NEUTRAL';
    Result.Line := 0.0;
    Exit;
  end;

  ATR := CalcATR(Highs, Lows, Closes, Period);
  SetLength(HL2, Length(Closes));
  SetLength(LongStop, Length(Closes));
  SetLength(ShortStop, Length(Closes));
  SetLength(Trend, Length(Closes));

  for I := 0 to High(Closes) do
  begin
    HL2[I] := (Highs[I] + Lows[I]) / 2.0;
    LongStop[I] := 0.0;
    ShortStop[I] := 0.0;
    Trend[I] := 1;
  end;

  for I := Period to High(Closes) do
  begin
    CurrLong := HL2[I] - Multiplier * ATR[I];
    PrevLong := LongStop[I-1];
    if Closes[I-1] > PrevLong then
      LongStop[I] := Max(CurrLong, PrevLong) else LongStop[I] := CurrLong;

    CurrShort := HL2[I] + Multiplier * ATR[I];
    PrevShort := ShortStop[I-1];
    if Closes[I-1] < PrevShort then
      ShortStop[I] := Min(CurrShort, PrevShort) else ShortStop[I] := CurrShort;

    if (Trend[I-1] = -1) and (Closes[I] > ShortStop[I-1]) then
      Trend[I] := 1
    else if (Trend[I-1] = 1) and (Closes[I] < LongStop[I-1]) then
      Trend[I] := -1
    else Trend[I] := Trend[I-1];
  end;

  if Trend[High(Trend)] = 1 then
  begin
    Result.Trend := 'BULL';
    Result.Line := LongStop[High(LongStop)];
  end
  else
  begin
    Result.Trend := 'BEAR';
    Result.Line := ShortStop[High(ShortStop)];
  end;
end;

function CalcChop(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 14): Double;
var
  Trs: TArray<Double>;
  SumTR, MaxHigh, MinLow: Double;
  I: Integer;
begin
  if Length(Closes) < Period + 1 then
    Exit(50.0);

  SetLength(Trs, Period);
  for I := Length(Closes) - Period to Length(Closes) - 1 do
    Trs[I - (Length(Closes) - Period)] := Max(Highs[I] - Lows[I], Max(Abs(Highs[I] - Closes[I-1]), Abs(Lows[I] - Closes[I-1])));

  SumTR := 0.0;
  for I := 0 to Period - 1 do
     SumTR := SumTR + Trs[I];

  MaxHigh := Highs[Length(Closes) - Period];
  MinLow := Lows[Length(Closes) - Period];
  for I := Length(Closes) - Period + 1 to Length(Closes) - 1 do
  begin
    if Highs[I] > MaxHigh then
      MaxHigh := Highs[I];
    if Lows[I] < MinLow then
      MinLow := Lows[I];
  end;

  if MaxHigh - MinLow = 0 then
    Exit(50.0);

  Result := 100.0 * Log10(SumTR / (MaxHigh - MinLow)) / Log10(Period);
end;

function CalcMarketStructure(const Highs, Lows: TArray<Double>; Period: Integer = 5): string;
var
  PrevLow, CurrLow, PrevHigh, CurrHigh: Double;
  I: Integer;
begin
  if Length(Highs) < Period * 2 then
    Exit('NEUTRAL');

  PrevLow := Lows[Length(Lows) - Period * 2];
  for I := Length(Lows) - Period * 2 + 1 to Length(Lows) - Period - 1 do
    if Lows[I] < PrevLow then
      PrevLow := Lows[I];

  CurrLow := Lows[Length(Lows) - Period];
  for I := Length(Lows) - Period + 1 to Length(Lows) - 1 do
    if Lows[I] < CurrLow then
       CurrLow := Lows[I];

  PrevHigh := Highs[Length(Highs) - Period * 2];
  for I := Length(Highs) - Period * 2 + 1 to Length(Highs) - Period - 1 do
    if Highs[I] > PrevHigh then
      PrevHigh := Highs[I];

  CurrHigh := Highs[Length(Highs) - Period];
  for I := Length(Highs) - Period + 1 to Length(Highs) - 1 do
    if Highs[I] > CurrHigh then
       CurrHigh := Highs[I];

  if CurrLow > PrevLow then
    Result := 'BULL'
  else if CurrHigh < PrevHigh then
    Result := 'BEAR'
  else Result := 'NEUTRAL';
end;

function CalcLiquiditySweep(const Highs, Lows, Closes: TArray<Double>; Period: Integer = 20): string;
var
  PrevLow, PrevHigh, CurrLow, CurrHigh, CurrClose, PrevClose: Double;
  I: Integer;
begin
  if Length(Closes) < Period + 2 then
    Exit('NONE');

  PrevLow := Lows[Length(Lows) - Period - 1];
  PrevHigh := Highs[Length(Highs) - Period - 1];
  for I := Length(Closes) - Period to Length(Closes) - 2 do
  begin
    if Lows[I] < PrevLow then
      PrevLow := Lows[I];
    if Highs[I] > PrevHigh then
      PrevHigh := Highs[I];
  end;

  CurrLow := Lows[High(Lows)];
  CurrHigh := Highs[High(Highs)];
  CurrClose := Closes[High(Closes)];
  PrevClose := Closes[High(Closes) - 1];

  if (CurrLow < PrevLow) and (CurrClose > PrevLow)
               and (CurrClose > PrevClose) then
     Result := 'BULL_SWEEP'
  else if (CurrHigh > PrevHigh) and (CurrClose < PrevHigh) and
                 (CurrClose < PrevClose) then
     Result := 'BEAR_SWEEP'
  else
     Result := 'NONE';
end;

function CalcFVG(const Highs, Lows, Closes: TArray<Double>; Lookback: Integer = 15): TFVGData;
var
  CurrentPrice: Double;
  HM2, LM2, HM0, LM0: Double;
  I, IM2, IM0, J: Integer;
  GapBottom, GapTop: Double;
  IsFilled: Boolean;
begin
  Result.Pts := 0;
  Result.BullFVGAbove := 0.0;
  Result.BullFVGSize := 0.0;
  Result.BearFVGBelow := 0.0;
  Result.BearFVGSize := 0.0;

  if Length(Closes) < Lookback + 2 then
    Exit;
  CurrentPrice := Closes[High(Closes)];
  
  HM2 := Highs[High(Highs) - 2];
  LM2 := Lows[High(Lows) - 2];
  HM0 := Highs[High(Highs)];
  LM0 := Lows[High(Lows)];
  
  if LM0 > HM2 then Result.Pts := 2
  else if HM0 < LM2 then Result.Pts := -2;
  
  for I := High(Closes) - 2 downto High(Closes) - Lookback - 2 do
  begin
    if I < 2 then Continue;
    IM2 := I - 2;
    IM0 := I;
    
    if Highs[IM0] < Lows[IM2] then
    begin
      GapBottom := Highs[IM0];
      GapTop := Lows[IM2];
      IsFilled := False;
      for J := I + 1 to High(Closes) do
        if Highs[J] >= GapTop then
        begin
          IsFilled := True;
          Break;
        end;
        
      if not IsFilled and (GapBottom > CurrentPrice) then
      begin
        Result.BullFVGAbove := (GapBottom - CurrentPrice) / CurrentPrice * 100.0;
        Result.BullFVGSize := (GapTop - GapBottom) / GapBottom * 100.0;
        Break;
      end;
    end;
    
    if Lows[IM0] > Highs[IM2] then
    begin
      GapTop := Lows[IM0];
      GapBottom := Highs[IM2];
      IsFilled := False;
      for J := I + 1 to High(Closes) do
        if Lows[J] <= GapBottom then
        begin
          IsFilled := True; Break;
        end;

      if not IsFilled and (GapTop < CurrentPrice) then
      begin
        Result.BearFVGBelow := (CurrentPrice - GapTop) / GapTop * 100.0;
        Result.BearFVGSize := (GapTop - GapBottom) / GapBottom * 100.0;
        Break;
      end;
    end;
  end;
end;

function CalcMTFBias(const Closes, Highs, Lows: TArray<Double>): string;
var
  EMA9, EMA21, EMA50: TArray<Double>;
  EMA12, EMA26, MACD, Sig: TArray<Double>;
  Hist: Double;
  BullStack, BearStack: Boolean;
  I: Integer;
begin
  if Length(Closes) < 70 then
    Exit('NEUTRAL');

  EMA9 := CalcEMA(Closes, 9);
  EMA21 := CalcEMA(Closes, 21);
  EMA50 := CalcEMA(Closes, 50);

  EMA12 := CalcEMA(Closes, 12);
  EMA26 := CalcEMA(Closes, 26);

  SetLength(MACD, Length(Closes));
  for I := 0 to High(Closes) do
    MACD[I] := EMA12[I] - EMA26[I];

  Sig := CalcEMA(MACD, 9);
  Hist := MACD[High(MACD)] - Sig[High(Sig)];

  if (EMA9[High(EMA9)] > EMA21[High(EMA21)]) and (EMA21[High(EMA21)] > EMA50[High(EMA50)]) and
       (Hist > 0) then
    Result := 'BULL'
  else if (EMA9[High(EMA9)] < EMA21[High(EMA21)]) and
      (EMA21[High(EMA21)] < EMA50[High(EMA50)]) and (Hist < 0) then
    Result := 'BEAR'
  else
    Result := 'NEUTRAL';
end;

function TradingDecision(
  const Closes1H, Highs1H, Lows1H, Volumes1H: TArray<Double>;
  const Closes4H, Highs4H, Lows4H: TArray<Double>;
  const ClosesD, HighsD, LowsD: TArray<Double>;
  out Details: TDecisionDetails;
  MinutesTo4hClose: Integer = 60;
  ReturnDetails: Boolean = False;
  UTCHour: Integer = -1;
  OrderBookImbalance: Double = 1.0; 
  VDRatio: Double = 1.0;            
  const OI1H: TArray<Double> = nil;
  FundingRate: Double = 0.0;
  MajorBias: string = 'NEUTRAL';
  VolClimaxMult: Double = 3.0;
  ScoreThresholdTrend: Integer = 6;
  ScoreThresholdRange: Integer = 7;
  SessionStart: Integer = 8;
  SessionEnd: Integer = 20;
  ExtremeScore: Integer = 10): Integer;
var
  EMAData: TEMAStackData;
  MACDData: TMACDData;
  RSIData: TRSIData;
  StochData: TStochData;
  BBData: TBBData;
  OBVData: TOBVData;
  ADXData: TADXData;
  SuperData: TSupertrendData;
  ATRArr, ATREMAArr: TArray<Double>;
  ATRCurr, ATREMAVal: Double;
  LowVolAtr: Boolean;
  ChopVal, OBIVal: Double;
  MS1H, SweepVal: string;
  MACDConfirm, MTFSyncPts, FVGPts, FVGVoidPts, RSIPts: Integer;
  BBSqueezeBonus, MikroPts, ADXPts, ChopPts: Integer;
  HCurr, HPrev: Double;
  IsSession: Boolean;
  Bias4H, BiasD: string;
  FlagsList, FiltersList: TStringList;
  Score: Integer;
  VolAvg: Double;
  LowVol, VolClimax: Boolean;
  MACDMandate: Boolean;
  Regime: string;
  Candidate, FinalDecision: Integer;
  ThresholdLong, ThresholdShort: Integer;
  ValidSession: Boolean;
  STMatchLong, STMatchShort: Boolean;
  OIPctChange, OIM2, OIRecent: Double;
  IsShortSqueeze, IsLongSqueeze: Boolean;
  I: Integer;
begin
  Result := NO_OPEN;
  Details.Score := 0;
  SetLength(Details.Flags, 0);
  SetLength(Details.Filters, 0);

  if (Length(Closes1H) < 100) or (Length(Closes4H) < 40) or (Length(ClosesD) < 20) then
  begin
    if ReturnDetails then
    begin
      SetLength(Details.Filters, 1);
      Details.Filters[0] := 'INSUFFICIENT_DATA_LENGTH';
    end;
    Exit;
  end;

  EMAData := CalcEMAStack(Closes1H);
  MACDData := CalcMACD(Closes1H);
  RSIData := CalcRSI(Closes1H);
  StochData := CalcStochastic(Closes1H, Highs1H, Lows1H);
  BBData := CalcBB(Closes1H, Volumes1H);
  OBVData := CalcOBV(Closes1H, Volumes1H);
  
  ADXData := CalcADX(Highs1H, Lows1H, Closes1H);
  SuperData := CalcSupertrend(Highs1H, Lows1H, Closes1H);
  
  ATRArr := CalcATR(Highs1H, Lows1H, Closes1H);
  ATREMAArr := CalcAtrEma(Highs1H, Lows1H, Closes1H);
  ATRCurr := ATRArr[High(ATRArr)];
  ATREMAVal := ATREMAArr[High(ATREMAArr)];
  LowVolAtr := ATRCurr < (1.1 * ATREMAVal);

  OBIVal := OrderBookImbalance;
  ChopVal := CalcChop(Highs1H, Lows1H, Closes1H);
  MS1H := CalcMarketStructure(Highs1H, Lows1H, 8);
  SweepVal := CalcLiquiditySweep(Highs1H, Lows1H, Closes1H, 20);

  MACDConfirm := 0;
  HCurr := MACDData.Histogram;
  HPrev := MACDData.HistogramPrev;
  if (HCurr > 0) and (HPrev > 0) and (HCurr > HPrev) then
    MACDConfirm := 1
  else if (HCurr < 0) and (HPrev < 0) and (HCurr < HPrev) then
    MACDConfirm := -1;

  if UTCHour = -1 then
    UTCHour := 12;
  IsSession := (UTCHour >= SessionStart) and (UTCHour <= SessionEnd);

  Bias4H := CalcMTFBias(Closes4H, Highs4H, Lows4H);
  BiasD := CalcMTFBias(ClosesD, HighsD, LowsD);

  MTFSyncPts := 0;
  if (Bias4H = 'BULL') and (BiasD = 'BULL') then
    MTFSyncPts := 2
  else if (Bias4H = 'BEAR') and (BiasD = 'BEAR') then
    MTFSyncPts := -2;

  FlagsList := TStringList.Create;
  FiltersList := TStringList.Create;
  try
    if EMAData.LTBull then
      FlagsList.Add('LT_BULL');
    if EMAData.LTBear then
      FlagsList.Add('LT_BEAR');
    if MACDData.BullDiv then
      FlagsList.Add('BULL_DIV');
    if MACDData.BearDiv then
      FlagsList.Add('BEAR_DIV');
    if RSIData.ExtremeOS then
      FlagsList.Add('EXTREME_OS');
    if RSIData.ExtremeOB then
      FlagsList.Add('EXTREME_OB');
    if SuperData.Trend = 'BULL' then
      FlagsList.Add('SUPER_BULL');
    if SuperData.Trend = 'BEAR' then
      FlagsList.Add('SUPER_BEAR');

    if ChopVal > 61.8 then
      FlagsList.Add('CHOP_NOISE')
    else if ChopVal < 38.2 then
      FlagsList.Add('CHOP_TREND');

    if MS1H = 'BULL' then
      FlagsList.Add('MS_HIGHER_LOW')
    else if MS1H = 'BEAR' then
      FlagsList.Add('MS_LOWER_HIGH');

    if SweepVal = 'BULL_SWEEP' then
      FlagsList.Add('LIQUIDITY_SWEEP_BULL')
    else if SweepVal = 'BEAR_SWEEP' then
      FlagsList.Add('LIQUIDITY_SWEEP_BEAR');

    Score := (EMAData.Pts * 2) + (MACDData.Pts * 2) + (MACDConfirm * 1) + (MTFSyncPts * 2);
    if IsSession then
      Score := Score + 1;

    var FVGData := CalcFVG(Highs1H, Lows1H, Closes1H);
    FVGPts := FVGData.Pts;
    if FVGPts <> 0 then
    begin
      if FVGPts > 0 then FlagsList.Add('FVG_BULL') else FlagsList.Add('FVG_BEAR');
    end;
    
    if FVGData.BullFVGAbove > 0.0 then
      FlagsList.Add('FVG_VOID_ABOVE');
    if FVGData.BearFVGBelow > 0.0 then
      FlagsList.Add('FVG_VOID_BELOW');
    Score := Score + FVGPts;

    FVGVoidPts := 0;
    if (FVGData.BullFVGAbove >= 1.0) and (FVGData.BullFVGAbove <= 3.0) then
    begin
      FVGVoidPts := 1;
      FlagsList.Add('FVG_VOID_MAGNET_UP');
    end
    else if (FVGData.BearFVGBelow >= 1.0) and (FVGData.BearFVGBelow <= 3.0) then
    begin
      FVGVoidPts := -1;
      FlagsList.Add('FVG_VOID_MAGNET_DN');
    end;
    Score := Score + FVGVoidPts;

    RSIPts := RSIData.Pts;
    if RSIData.RSI < 25 then RSIPts := 2
    else if RSIData.RSI > 75 then RSIPts := -2;
    Score := Score + RSIPts;
    
    Score := Score + StochData.Pts + BBData.Pts + OBVData.Pts;

    BBSqueezeBonus := 0;
    if BBData.SqueezeBreakoutUp then
    begin
      BBSqueezeBonus := 2;
      FlagsList.Add('BB_SQUEEZE_UP');
    end
    else if BBData.SqueezeBreakoutDown then
    begin
      BBSqueezeBonus := -2;
      FlagsList.Add('BB_SQUEEZE_DN');
    end;
    Score := Score + BBSqueezeBonus;

    MikroPts := 0;
    if OBIVal > 1.3 then
    begin
      MikroPts := MikroPts + 2;
      FlagsList.Add('MIKRO_SUPPORT_OBI');
    end
    else if OBIVal < 0.7 then
    begin
       MikroPts := MikroPts - 2;
       FlagsList.Add('MIKRO_RESIST_OBI');
    end;
    
    if VDRatio > 1.2 then
    begin
      MikroPts := MikroPts + 2;
      FlagsList.Add('MIKRO_BUY_AGGR');
    end
    else if VDRatio < 0.8 then
    begin
      MikroPts := MikroPts - 2;
      FlagsList.Add('MIKRO_SELL_AGGR');
    end;

    Score := Score + MikroPts;

    ADXPts := 0;
    if (ADXData.ADX > 25) and ADXData.ADXRising then
    begin
      if (EMAData.Pts > 0) and (BiasD = 'BULL') then
        ADXPts := 2
      else if (EMAData.Pts < 0) and (BiasD = 'BEAR') then
        ADXPts := -2;
    end;
    Score := Score + ADXPts;
    if ADXPts > 0 then FlagsList.Add('ADX_TREND_BULL')
    else if ADXPts < 0 then FlagsList.Add('ADX_TREND_BEAR');

    ChopPts := 0;
    if ChopVal < 38.2 then
      ChopPts := 2
    else if ChopVal > 61.8 then
            ChopPts := -1;
    Score := Score + ChopPts;

    VolAvg := 0.0;
    for I := Length(Volumes1H) - 20 to Length(Volumes1H) - 1 do
      VolAvg := VolAvg + Volumes1H[I];

    VolAvg := VolAvg / 20.0;

    LowVol := Volumes1H[High(Volumes1H)] < (0.2 * VolAvg);
    VolClimax := Volumes1H[High(Volumes1H)] > (VolClimaxMult * VolAvg);

    if LowVol then
      FiltersList.Add('LOW_VOLUME');

    if LowVolAtr then
      FiltersList.Add('ATR_SILENCE_BLOCK');

    if MinutesTo4HClose < 15 then
      FiltersList.Add('M4H_CLOSE_PROXIMITY');

    MACDMandate := MACDConfirm = 0;
    if ADXData.ADX > 30 then MACDMandate := False;
    if Abs(Score) >= ExtremeScore then
    begin
      MACDMandate := False;
      FlagsList.Add('EXTREME_SCORE_PATH_ACTIVATED');
    end;
    if MACDMandate then FiltersList.Add('MACD_NO_CONFIRM');

    Candidate := NO_OPEN;
    if ADXData.ADX > 30 then Regime := 'TREND' else Regime := 'RANGE';
    
    IsShortSqueeze := False;
    IsLongSqueeze := False;
    
    ThresholdLong := ScoreThresholdTrend;
    ThresholdShort := Max(4, ScoreThresholdTrend - 1);
    
    if (Abs(MTFSyncPts) >= 2) or (Abs(MikroPts) >= 2) or (ChopVal < 35.0) or (Abs(BBSqueezeBonus) > 0) then
    begin
      ThresholdLong := Max(2, ThresholdLong - 2);
      ThresholdShort := Max(2, ThresholdShort - 2);
    end;
    
    ValidSession := IsSession or VolClimax or (Abs(Score) >= ExtremeScore);

    if Regime = 'TREND' then
    begin
      if (Score >= ThresholdLong) and (EMAData.Pts >= 1) then
      begin
        if (MS1H <> 'BEAR') or (Score >= ExtremeScore) then Candidate := LONG_POS;
      end
      else if (Score <= -ThresholdShort) and (EMAData.Pts <= -1) then
      begin
        if (MS1H <> 'BULL') or (Score <= -ExtremeScore) then Candidate := SHORT_POS;
      end;
    end
    else
    begin
      if (ChopVal > 55.0) and (Abs(Score) < ExtremeScore) and (SweepVal = 'NONE') then
        FiltersList.Add('CHOP_NOISE_BLOCK')
      else
      begin
        if (Score >= ScoreThresholdRange) and (Bias4H = 'BULL') and (MS1H <> 'BEAR') then Candidate := LONG_POS
        else if (Score <= -ScoreThresholdRange) and (Bias4H = 'BEAR') and (MS1H <> 'BULL') then Candidate := SHORT_POS;
      end;
    end;

    OIPctChange := 0.0;
    if Length(OI1H) >= 3 then
    begin
      OIM2 := (OI1H[High(OI1H)] + OI1H[High(OI1H)-1] + OI1H[High(OI1H)-2]) / 3.0;
      OIRecent := OI1H[High(OI1H)];

      if OIM2 > 0 then
         OIPctChange := (OIRecent - OIM2) / OIM2 * 100.0
      else
         OIPctChange := 0.0;

      if (Candidate = LONG_POS) and (OIPctChange < -0.5) then
      begin
        IsShortSqueeze := True; Candidate := NO_OPEN; FiltersList.Add('SHORT_SQUEEZE_BLOCK');
      end
      else if (Candidate = SHORT_POS) and (OIPctChange < -0.5) then
      begin
        IsLongSqueeze := True; Candidate := NO_OPEN; FiltersList.Add('LONG_SQUEEZE_BLOCK');
      end;
    end;

    if (not IsShortSqueeze) and (SweepVal = 'BULL_SWEEP') and (MS1H = 'BULL') then
    begin
      Candidate := LONG_POS; FlagsList.Add('SWEEP_LONG_SETUP');
    end;
    if (not IsLongSqueeze) and (SweepVal = 'BEAR_SWEEP') and (MS1H = 'BEAR') then
    begin
      Candidate := SHORT_POS; FlagsList.Add('SWEEP_SHORT_SETUP');
    end;
    if (not IsShortSqueeze) and MACDData.BullDiv and (Score >= 6) and (Bias4H = 'BULL') and (MS1H = 'BULL') then
    begin
      Candidate := LONG_POS; FlagsList.Add('MACD_DIV_LONG_SETUP');
    end;
    if (not IsLongSqueeze) and MACDData.BearDiv and (Score <= -6) and (Bias4H = 'BEAR') and (MS1H = 'BEAR') then
    begin
      Candidate := SHORT_POS; FlagsList.Add('MACD_DIV_SHORT_SETUP');
    end;

    if (FundingRate <> 0.0) then
    begin
      if (Candidate = LONG_POS) and (FundingRate > 0.0005) then
      begin
        Candidate := NO_OPEN; FiltersList.Add('FUNDING_EUPHORIA_BLOCK');
      end
      else if (Candidate = SHORT_POS) and (FundingRate < -0.0005) then
      begin
        Candidate := NO_OPEN; FiltersList.Add('FUNDING_PANIC_BLOCK');
      end;
    end;

    if MajorBias <> 'NEUTRAL' then
    begin
      if (Candidate = LONG_POS) and (MajorBias = 'BEAR') then
      begin
        Candidate := NO_OPEN; FiltersList.Add('BTC_CORRELATION_VETO');
      end
      else if (Candidate = SHORT_POS) and (MajorBias = 'BULL') then
      begin
        Candidate := NO_OPEN; FiltersList.Add('BTC_CORRELATION_VETO');
      end;
    end;

    FinalDecision := Candidate;
    STMatchLong := (SuperData.Trend = 'BULL') or (SweepVal = 'BULL_SWEEP');
    STMatchShort := (SuperData.Trend = 'BEAR') or (SweepVal = 'BEAR_SWEEP');

    if (FinalDecision = LONG_POS) and (BiasD = 'BEAR') then
    begin
      FinalDecision := NO_OPEN; FiltersList.Add('MTF_D1_BEAR_BLOCK');
    end;
    if (FinalDecision = SHORT_POS) and (BiasD = 'BULL') then
    begin
      FinalDecision := NO_OPEN; FiltersList.Add('MTF_D1_BULL_BLOCK');
    end;

    if (FinalDecision <> NO_OPEN) and not ValidSession then
    begin
      FinalDecision := NO_OPEN; FiltersList.Add('OFF_SESSION_LOW_VOL');
    end;

    if (FinalDecision = LONG_POS) and not STMatchLong then
    begin
      FinalDecision := NO_OPEN; FiltersList.Add('SUPERTREND_MISMATCH');
    end;
    if (FinalDecision = SHORT_POS) and not STMatchShort then
    begin
      FinalDecision := NO_OPEN; FiltersList.Add('SUPERTREND_MISMATCH');
    end;

    if (FiltersList.IndexOf('MACD_NO_CONFIRM') >= 0) or
          (FiltersList.IndexOf('SUPERTREND_MISMATCH') >= 0) then
      FinalDecision := NO_OPEN;

    if FinalDecision = LONG_POS then
    begin
      if (Regime = 'RANGE') and (RSIData.RSI > 70) then
      begin
        FinalDecision := NO_OPEN; FiltersList.Add('RSI_RANGE_LIMIT');
      end;
      if BBData.PctB > 1.1 then
      begin
        FinalDecision := NO_OPEN; FiltersList.Add('BB_STRETCH_BLOCK');
      end;
    end
    else if FinalDecision = SHORT_POS then
    begin
      if (Regime = 'RANGE') and (RSIData.RSI < 30) then
      begin
        FinalDecision := NO_OPEN; FiltersList.Add('RSI_RANGE_LIMIT');
      end;
      if BBData.PctB < -0.1 then
      begin
        FinalDecision := NO_OPEN; FiltersList.Add('BB_STRETCH_BLOCK');
      end;
    end;

    if (LowVol or LowVolAtr) and (Regime = 'RANGE') and
                 (Abs(Score) < ExtremeScore) then
      FinalDecision := NO_OPEN;

    Result := FinalDecision;

    if ReturnDetails then
    begin
      Details.Price := Closes1H[High(Closes1H)];
      Details.Score := Score;
      Details.EMA := EMAData;
      Details.MACD := MACDData;
      Details.RSI := RSIData;
      Details.Stoch := StochData;
      Details.BB := BBData;
      Details.OBV := OBVData;
      Details.ADX := ADXData;
      Details.Supertrend := SuperData;
      Details.MTF4h := Bias4H;
      Details.MTFD := BiasD;
      Details.Chop := ChopVal;
      Details.MS := MS1H;
      Details.OIPctChange := OIPctChange;
      Details.OBI := OBIVal;
      Details.VDRatio := VDRatio;

      SetLength(Details.Flags, FlagsList.Count);
      for I := 0 to FlagsList.Count - 1 do
        Details.Flags[I] := FlagsList[I];

      SetLength(Details.Filters, FiltersList.Count);
      for I := 0 to FiltersList.Count - 1 do
        Details.Filters[I] := FiltersList[I];
    end;

  finally
    FlagsList.Free;
    FiltersList.Free;
  end;
end;

end.
