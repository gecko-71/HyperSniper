program HyperSniperBacktest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.DateUtils,
  System.Math,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Winapi.Windows,
  Data.DB,
  FireDAC.Comp.Client,
  uBacktestEngine in 'uBacktestEngine.pas',
  uDataManager in 'uDataManager.pas',
  uHyperSniper in 'uHyperSniper.pas';

var
  DataManager: TDataFetchManager;
  JanStart, JanEnd, FebStart, FebEnd: TDateTime;
  Symbols: TStringList;
  Config: TJSONObject;
  ResultsJan, ResultsFeb: TList<TBacktestResult>;
  I: Integer;
  Symbol: string;
  DataFull: TFDMemTable;
  ResJan, ResFeb: TBacktestResult;
  TotalN, TotalWins: Integer;
  AllPnLs: TList<Double>;
  PnLValue: Double;


procedure LoadConfig;
var
  ConfigPath: string;
  LList: TStringList;
begin
  ConfigPath := 'best_configs_global.json';
  if TFile.Exists(ConfigPath) then
  begin
    LList := TStringList.Create;
    try
      LList.LoadFromFile(ConfigPath, TEncoding.UTF8);
      Config := TJSONObject.ParseJSONValue(LList.Text) as TJSONObject;
      Writeln('OK: Config loaded from ', ConfigPath);
    finally
      LList.Free;
    end;
  end;
end;

procedure RenderPeriodReport(const APeriodName: string; const AResults: TList<TBacktestResult>);
var
  Res: TBacktestResult;
  TotalN, TotalWins, TotalL, TotalS: Integer;
  AllPnLs: TList<Double>;
  OverallHR, AvgPnL, SumPnL: Double;
  PnL: Double;
  Status: string;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;

  TotalN := 0;
  TotalWins := 0;
  TotalL := 0;
  TotalS := 0;

  AllPnLs := TList<Double>.Create;
  try
    for Res in AResults do
    begin
      Inc(TotalN, Res.TotalSignals);
      Inc(TotalWins, Res.Wins);
      Inc(TotalL, Res.LongN);
      Inc(TotalS, Res.ShortN);
      if Assigned(Res.Signals) then
      begin
        for var Sig in Res.Signals do
        begin
          if not IsNaN(Sig.PnLPct) and not IsInfinite(Sig.PnLPct) then
             AllPnLs.Add(Sig.PnLPct);
        end;
      end;
    end;

    OverallHR := 0;
    AvgPnL := 0;
    SumPnL := 0;

    if TotalN > 0 then
    begin
      OverallHR := TotalWins / TotalN * 100;
      for PnL in AllPnLs do SumPnL := SumPnL + PnL;
      AvgPnL := SumPnL / TotalN;
    end;

    if IsNaN(OverallHR) or IsInfinite(OverallHR) then
       OverallHR := 0;

    if IsNaN(AvgPnL) or IsInfinite(AvgPnL) then
       AvgPnL := 0;

    if IsNaN(SumPnL) or IsInfinite(SumPnL) then
       SumPnL := 0;

    Writeln('══════════════════════════════════════════════════════════════════════════');
    Writeln('  PERIOD: ' + APeriodName);
    Writeln('══════════════════════════════════════════════════════════════════════════');
    Writeln('');
    Writeln('  ┌── ORIGINAL ──────────────────────────────────────────────┐');
    Writeln(Format('  │  %-56s │', [Format('Signals : %d  (LONG=%d, SHORT=%d)', [TotalN, TotalL, TotalS], FS)], FS));
    Writeln(Format('  │  %-56s │', [Format('Hit Rate: %.1f%%', [OverallHR], FS)], FS));
    Writeln(Format('  │  %-56s │', [Format('Avg PnL : %.2f%%  |  Total PnL: %.2f%%', [AvgPnL, SumPnL], FS)], FS));
    Writeln('  └──────────────────────────────────────────────────────────┘');
    Writeln('');
    Writeln('  Symbol              n    HR%   AvgPnL   L  S   L_HR   S_HR  Status');
    Writeln('  ───────────────── ──── ────── ─────── ── ── ────── ──────  ────────────');

    for Res in AResults do
    begin
      Status := '       ';
      if Res.TotalSignals > 0 then
      begin
        if Res.HitRate >= 57 then
           Status := '✅ GOOD'
        else if Res.HitRate >= 52 then
           Status := '✅ OK'
        else if Res.HitRate >= 48 then
           Status := '🟠 NEUTRAL'
        else
           Status := '❌ WEAK';
      end;

      if Res.TotalSignals = 0 then
        Writeln(Format('  %-17s %4s %6s %7s %2s %2s %6s %6s  %s', [Res.Symbol, '-', '-', '-', '-', '-', '-', '-', 'NONE'], FS))
      else
        Writeln(Format('  %-17s %4d %5.1f%% %6.2f%% %2d %2d %5.1f%% %5.1f%%  %s',
          [Res.Symbol, Res.TotalSignals, Res.HitRate, Res.AvgPnL, Res.LongN, Res.ShortN, Res.LongHR, Res.ShortHR, Status], FS));
    end;
    Writeln('');
  finally
    AllPnLs.Free;
  end;
end;

procedure RenderSymbolLivePrediction(const ASymbol: string; DataManager: TDataFetchManager; AConfig: TJSONObject);
var
  Data: TFDMemTable;
  Today, TargetStart: TDateTime;
  CurrentHour, I: Integer;
  Decision: Integer;
  Details: TDecisionDetails;
  FactStr, PredictedStr, StatusStr: string;
  FS: TFormatSettings;
  O, C: Double;
  C1H, H1H, L1H, V1H, O1H: TArray<Double>;
  T1H: TArray<TDateTime>;
  OI1H, F1H: TArray<Double>;
  Table4H, TableD: TFDMemTable;
  C4H, H4H, L4H, CD, HD, LD, dummy1, dummy2, dummy4, dummy5: TArray<Double>;
  T4H, TD: TArray<TDateTime>;
  Idx4H, IdxD, s1h, s4h, sd: Integer;
  M4H, Raw: Integer;
begin
  Today := Trunc(Now);
  CurrentHour := HourOf(Now);

  if CurrentHour < 10 then
    TargetStart := Today - 1 + EncodeTime(1, 0, 0, 0)
  else
    TargetStart := Today + EncodeTime(1, 0, 0, 0);

  Data := DataManager.GetHistoricalData(ASymbol, Today - 45, Now);
  if not Assigned(Data) or (Data.RecordCount < 100) then
  begin
    if Assigned(Data) then Data.Free;
    Exit;
  end;

  FS := TFormatSettings.Invariant;
  
  Writeln('');
  Writeln('══════════════════════════════════════════════════════════════════════════');
  Writeln('  ' + ASymbol + ' LIVE PREDICTION (TODAY ' + FormatDateTime('YYYY-MM-DD', Today) + ')');
  Writeln('══════════════════════════════════════════════════════════════════════════');
  Writeln('  Hour       Fact        Predicted (Score)  Status    Reason / Filter');
  Writeln('  ─────────  ──────────  ─────────────────  ────────  ────────────────────');

  Table4H := TBacktestEngine.ResampleTF(Data, '4h');
  TableD  := TBacktestEngine.ResampleTF(Data, 'D');
  try
    TBacktestEngine.MemTableToArray(Data, C1H, H1H, L1H, V1H, O1H, T1H, OI1H, F1H);
    TBacktestEngine.MemTableToArray(Table4H, C4H, H4H, L4H, dummy1, dummy2, T4H, dummy4, dummy5);
    TBacktestEngine.MemTableToArray(TableD, CD, HD, LD, dummy1, dummy2, TD, dummy4, dummy5);

    Idx4H := 0;
    IdxD := 0;
    
    var v_climax: Double := 3.0;
    var s_trend: Integer := 6;
    var s_range: Integer := 7;
    var s_start: Integer := 8;
    var s_end: Integer := 20;
    var e_score: Integer := 10;
    if Assigned(AConfig) and Assigned(AConfig.GetValue(ASymbol)) then
    begin
      var Obj := AConfig.GetValue(ASymbol) as TJSONObject;
      v_climax := StrToFloatDef(Obj.GetValue('vol_climax_mult').Value, 3.0, FS);
      s_trend := StrToIntDef(Obj.GetValue('score_threshold_trend').Value, 6);
      s_range := StrToIntDef(Obj.GetValue('score_threshold_range').Value, 7);
      s_start := StrToIntDef(Obj.GetValue('session_start').Value, 8);
      s_end := StrToIntDef(Obj.GetValue('session_end').Value, 20);
      e_score := StrToIntDef(Obj.GetValue('extreme_score').Value, 10);
    end;

    for I := 0 to High(T1H) do
    begin
      var TS := T1H[I];
      if (TS < TargetStart) then Continue;
      if (TS > Now) then Break;

      O := O1H[I];
      C := C1H[I];
      if C > O then FactStr := 'LONG' else if C < O then FactStr := 'SHORT' else FactStr := 'FLAT';

      PredictedStr := 'WAIT';
      StatusStr := '⚪ -';
      var ReasonStr: string := '';

      if I > 0 then
      begin
        var PrevTS := T1H[I-1];
        while (Idx4H < High(T4H)) and (T4H[Idx4H+1] <= PrevTS) do Inc(Idx4H);
        while (IdxD < High(TD)) and (TD[IdxD+1] <= PrevTS) do Inc(IdxD);

        s1h := Max(0, I - 210);
        s4h := Max(0, Idx4H + 1 - 60);
        sd  := Max(0, IdxD + 1 - 60);

        var wC1H := Copy(C1H, s1h, I - s1h); 
        var wH1H := Copy(H1H, s1h, I - s1h);
        var wL1H := Copy(L1H, s1h, I - s1h);
        var wV1H := Copy(V1H, s1h, I - s1h);
        var wOI1H := Copy(OI1H, s1h, I - s1h);

        var wC4H := Copy(C4H, s4h, Idx4H - s4h + 1);
        var wH4H := Copy(H4H, s4h, Idx4H - s4h + 1);
        var wL4H := Copy(L4H, s4h, Idx4H - s4h + 1);

        var wCD := Copy(CD, sd, IdxD - sd + 1);
        var wHD := Copy(HD, sd, IdxD - sd + 1);
        var wLD := Copy(LD, sd, IdxD - sd + 1);

        Raw := (HourOf(PrevTS) * 60 + MinuteOf(PrevTS)) mod 240;
        if Raw = 0 then M4H := 0 else M4H := 240 - Raw;

        Decision := uHyperSniper.TradingDecision(wC1H, wH1H, wL1H, wV1H, wC4H, wH4H, wL4H, wCD, wHD, wLD, Details,
          M4H, True, HourOf(PrevTS), 1.0, 1.0, wOI1H, F1H[I-1], 'NEUTRAL',
          v_climax, s_trend, s_range, s_start, s_end, e_score);

        var ScoreVal: Double := 0;
        if not IsNaN(Details.Score) and not IsInfinite(Details.Score) then
          ScoreVal := Details.Score;

        var RoundScore: Integer := Round(ScoreVal);
        var ScoreStr: string;
        if RoundScore > 0 then ScoreStr := '+' + IntToStr(RoundScore) else ScoreStr := IntToStr(RoundScore);

        if Decision = 1 then PredictedStr := 'LONG (' + ScoreStr + ')'
        else if Decision = 2 then PredictedStr := 'SHORT (' + ScoreStr + ')'
        else PredictedStr := 'WAIT (' + ScoreStr + ')';

        if (Decision = 1) then
        begin
          if (FactStr = 'LONG') then StatusStr := '✅ HIT' else StatusStr := '❌ MISS';
        end
        else if (Decision = 2) then
        begin
          if (FactStr = 'SHORT') then StatusStr := '✅ HIT' else StatusStr := '❌ MISS';
        end
        else 
        begin
          StatusStr := '⚪ -';
          if Length(Details.Filters) > 0 then ReasonStr := Details.Filters[0];
        end;
      end;

      Writeln(Format('  %.2d:00 UTC  %-10s  %-17s  %-8s  %s', [HourOf(TS), FactStr, PredictedStr, StatusStr, ReasonStr], FS));
    end;

  finally
    Table4H.Free;
    TableD.Free;
    Data.Free;
  end;
  Writeln('══════════════════════════════════════════════════════════════════════════');
end;

begin
  // Set console to UTF-8
  SetConsoleOutputCP(65001);
  Writeln('Initializing HyperSniper Backtester...');
  
  JanStart := EncodeDateTime(2026, 1, 1, 0, 0, 0, 0);
  JanEnd   := EncodeDateTime(2026, 1, 31, 23, 59, 59, 0);
  FebStart := EncodeDateTime(2026, 2, 1, 0, 0, 0, 0);
  FebEnd   := EncodeDateTime(2026, 2, 28, 23, 59, 59, 0);

  DataManager := TDataFetchManager.Create;
  Symbols := TStringList.Create;
  ResultsJan := TList<TBacktestResult>.Create;
  ResultsFeb := TList<TBacktestResult>.Create;
  
  try
    LoadConfig;
    if Assigned(Config) then
    begin
      for I := 0 to Config.Count - 1 do
        Symbols.Add(Config.Pairs[I].JsonString.Value);
    end
    else
    begin
      Symbols.Add('BTC/USDT'); Symbols.Add('ETH/USDT'); Symbols.Add('SOL/USDT');
    end;

    for Symbol in Symbols do
    begin
      Writeln('Fetching and testing ' + Symbol + '...');
      DataFull := DataManager.GetHistoricalData(Symbol, EncodeDate(2025, 12, 15), FebEnd);
      
      if Assigned(DataFull) and (DataFull.RecordCount > 300) then
      begin
        Writeln(Format('OK (%d candles)', [DataFull.RecordCount]));
        ResJan := TBacktestEngine.ExecuteBacktest(Symbol, DataFull, JanStart, JanEnd, 210, Config);
        ResFeb := TBacktestEngine.ExecuteBacktest(Symbol, DataFull, FebStart, FebEnd, 210, Config);
        ResultsJan.Add(ResJan);
        ResultsFeb.Add(ResFeb);
        DataFull.Free;
      end
      else
        Writeln('FAILED');
    end;

    Writeln('');
    Writeln('==========================================================================');
    Writeln('  BACKTEST HYPERSNIPER V7.3 -- REAL HISTORICAL DATA');
    Writeln(Format('  Period: Jan + Feb 2026 | Generated: %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    Writeln('==========================================================================');
    Writeln('');
    Writeln(Format('  Symbols  : %d', [Symbols.Count]));
    Writeln('  Periods  : January 2026 (01.01–31.01) | February 2026 (01.02–28.02)');
    Writeln('  Method   : Open[i+1]→Close[i+1] | Warmup: 210 candles 1H');
    Writeln('  Config   : best_configs_global.json');
    Writeln('');

    RenderPeriodReport('JANUARY 2026', ResultsJan);
    RenderPeriodReport('FEBRUARY 2026', ResultsFeb);

    TotalN := 0; TotalWins := 0;
    AllPnLs := TList<Double>.Create;
    try
      for var R in ResultsJan do begin Inc(TotalN, R.TotalSignals); Inc(TotalWins, R.Wins); if Assigned(R.Signals) then for var S in R.Signals do AllPnLs.Add(S.PnLPct); end;
      for var R in ResultsFeb do begin Inc(TotalN, R.TotalSignals); Inc(TotalWins, R.Wins); if Assigned(R.Signals) then for var S in R.Signals do AllPnLs.Add(S.PnLPct); end;
      
      var FS := TFormatSettings.Invariant;
      Writeln('══════════════════════════════════════════════════════════════════════════');
      Writeln('  TOTAL SUMMARY');
      Writeln('══════════════════════════════════════════════════════════════════════════');
      Writeln('');
      Writeln(Format('  Total signals: %d', [TotalN], FS));
      if TotalN > 0 then
      begin
        var HR := TotalWins / TotalN * 100;
        if IsNaN(HR) or IsInfinite(HR) then HR := 0;
        
        var StatusTotal := 'WEAK';
        if HR >= 55 then StatusTotal := '✅ PASS'
        else if HR >= 50 then StatusTotal := '🟠 NEUTRAL'
        else StatusTotal := '❌ FAIL';
        
        var SPnL := 0.0; 
        for PnLValue in AllPnLs do 
          if not IsNaN(PnLValue) and not IsInfinite(PnLValue) then SPnL := SPnL + PnLValue;
        
        var APnL := 0.0;
        if TotalN > 0 then APnL := SPnL / TotalN;
        if IsNaN(APnL) or IsInfinite(APnL) then APnL := 0;
        if IsNaN(SPnL) or IsInfinite(SPnL) then SPnL := 0;

        Writeln(Format('  Hit Rate:       %.1f%%  -- %s', [HR, StatusTotal], FS));
        Writeln(Format('  Avg PnL/sig:    %.2f%%', [APnL], FS));
        Writeln(Format('  Total PnL:      %.2f%%', [SPnL], FS));
      end;

      Writeln('');
      Writeln('  TOP PERFORMERS (>5 signals, highest HR):');
      var AllResults := TList<TBacktestResult>.Create;
      try
        AllResults.AddRange(ResultsJan);
        AllResults.AddRange(ResultsFeb);
        AllResults.Sort(TComparer<TBacktestResult>.Construct(
          function(const L, R: TBacktestResult): Integer
          begin
            Result := CompareValue(R.HitRate, L.HitRate);
          end));

        var LFS := TFormatSettings.Invariant;
        var Count := 0;
        for var TR in AllResults do
        begin
          if (TR.TotalSignals >= 5) and (Count < 3) then
          begin
             Writeln(Format('  %-17s   HR=%5.1f%%  n=%d', [TR.Symbol, TR.HitRate, TR.TotalSignals], LFS));
             Inc(Count);
          end;
        end;
      finally
        AllResults.Free;
      end;
      Writeln('');
      Writeln('══════════════════════════════════════════════════════════════════════════');
    finally
      AllPnLs.Free;
    end;

    Writeln('');
    Writeln('══════════════════════════════════════════════════════════════════════════');
    Writeln('  PROJECT TOTAL LIVE PREDICTION SUMMARY');
    Writeln('══════════════════════════════════════════════════════════════════════════');
    
    for Symbol in Symbols do
      RenderSymbolLivePrediction(Symbol, DataManager, Config);

  finally
    if Assigned(Config) then Config.Free;
    Symbols.Free;
    DataManager.Free;

    for var R in ResultsJan do
    begin
      R.Signals.Free;
      R.Errors.Free;
    end;
    ResultsJan.Free;

    for var R in ResultsFeb do
    begin
      R.Signals.Free;
      R.Errors.Free;
    end;
    ResultsFeb.Free;
  end;
  
  Readln;
end.
