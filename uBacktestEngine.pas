unit uBacktestEngine;

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections, System.DateUtils,
  System.JSON, Data.DB, FireDAC.Comp.Client,
  uHyperSniper, uDataManager;

type
  TTradeSignal = record
    Timestamp: TDateTime;
    Decision: string; // 'LONG', 'SHORT'
    Entry: Double;
    ExitPrice: Double;
    PnLPct: Double;
    IsWin: Boolean;
    Score: Integer;
  end;

  TBacktestResult = record
    Symbol: string;
    TotalSignals: Integer;
    Wins: Integer;
    Losses: Integer;
    HitRate: Double;
    AvgPnL: Double;
    TotalPnL: Double;
    LongN: Integer;
    ShortN: Integer;
    LongHR: Double;
    ShortHR: Double;
    MaxWin: Double;
    MaxLoss: Double;
    Signals: TList<TTradeSignal>;
    Errors: TStringList;
  end;

  TBacktestEngine = class
  public
    class function ResampleTF(ASource: TFDMemTable; const ARule: string): TFDMemTable;
    class procedure MemTableToArray(AMemTable: TFDMemTable;
      var Closes, Highs, Lows, Volumes, Opens: TArray<Double>;
      var Timestamps: TArray<TDateTime>;
      var OI: TArray<Double>;
      var Funding: TArray<Double>);
    class function ExecuteBacktest(
      const ASymbol: string;
      ADataFull: TFDMemTable;
      APeriodStart, APeriodEnd: TDateTime;
      AWarmupN: Integer;
      AConfig: TJSONObject
    ): TBacktestResult;
  end;

implementation

class function TBacktestEngine.ResampleTF(ASource: TFDMemTable; const ARule: string): TFDMemTable;
var
  Interval: Integer;
  CurrentPeriod: TDateTime;
  H, L, O, C, V, OI, F: Double;
  First: Boolean;

  function GetPeriodStart(ADT: TDateTime; const ARule: string): TDateTime;
  begin
    Result := RecodeTime(ADT, HourOf(ADT), 0, 0, 0);
    if ARule = '4h' then
    begin
      Result := RecodeTime(ADT, 0, 0, 0, 0);
      Result := IncHour(Result, (HourOf(ADT) div 4) * 4);
    end
    else if ARule = 'D' then
      Result := RecodeTime(ADT, 0, 0, 0, 0);
  end;

begin
  Result := TFDMemTable.Create(nil);
  Result.FieldDefs.Add('timestamp', ftDateTime);
  Result.FieldDefs.Add('open', ftFloat);
  Result.FieldDefs.Add('high', ftFloat);
  Result.FieldDefs.Add('low', ftFloat);
  Result.FieldDefs.Add('close', ftFloat);
  Result.FieldDefs.Add('volume', ftFloat);
  Result.FieldDefs.Add('oi', ftFloat);
  Result.FieldDefs.Add('funding', ftFloat);
  Result.CreateDataSet;
  Result.IndexFieldNames := 'timestamp';

  if ASource.IsEmpty then Exit;

  ASource.First;
  CurrentPeriod := GetPeriodStart(ASource.FieldByName('timestamp').AsDateTime, ARule);
  H := -1e10; L := 1e10; O := ASource.FieldByName('open').AsFloat; V := 0; OI := 0; F := 0;
  First := True;

  while not ASource.Eof do
  begin
    var TS := ASource.FieldByName('timestamp').AsDateTime;
    var PeriodStart := GetPeriodStart(TS, ARule);

    if PeriodStart <> CurrentPeriod then
    begin
      Result.Append;
      Result.FieldByName('timestamp').AsDateTime := CurrentPeriod;
      Result.FieldByName('open').AsFloat := O;
      Result.FieldByName('high').AsFloat := H;
      Result.FieldByName('low').AsFloat := L;
      Result.FieldByName('close').AsFloat := C;
      Result.FieldByName('volume').AsFloat := V;
      Result.FieldByName('oi').AsFloat := OI;
      Result.FieldByName('funding').AsFloat := F;
      Result.Post;

      CurrentPeriod := PeriodStart;
      O := ASource.FieldByName('open').AsFloat;
      H := ASource.FieldByName('high').AsFloat;
      L := ASource.FieldByName('low').AsFloat;
      V := 0;
    end;

    C := ASource.FieldByName('close').AsFloat;
    V := V + ASource.FieldByName('volume').AsFloat;
    H := Max(H, ASource.FieldByName('high').AsFloat);
    L := Min(L, ASource.FieldByName('low').AsFloat);
    OI := ASource.FieldByName('oi').AsFloat;
    F := ASource.FieldByName('funding').AsFloat;

    ASource.Next;
  end;

  Result.Append;
  Result.FieldByName('timestamp').AsDateTime := CurrentPeriod;
  Result.FieldByName('open').AsFloat := O;
  Result.FieldByName('high').AsFloat := H;
  Result.FieldByName('low').AsFloat := L;
  Result.FieldByName('close').AsFloat := C;
  Result.FieldByName('volume').AsFloat := V;
  Result.FieldByName('oi').AsFloat := OI;
  Result.FieldByName('funding').AsFloat := F;
  Result.Post;
end;

class procedure TBacktestEngine.MemTableToArray(AMemTable: TFDMemTable;
  var Closes, Highs, Lows, Volumes, Opens: TArray<Double>;
  var Timestamps: TArray<TDateTime>;
  var OI: TArray<Double>;
  var Funding: TArray<Double>);
var
  I: Integer;
begin
  AMemTable.First;
  SetLength(Closes, AMemTable.RecordCount);
  SetLength(Highs, AMemTable.RecordCount);
  SetLength(Lows, AMemTable.RecordCount);
  SetLength(Volumes, AMemTable.RecordCount);
  SetLength(Opens, AMemTable.RecordCount);
  SetLength(Timestamps, AMemTable.RecordCount);
  SetLength(OI, AMemTable.RecordCount);
  SetLength(Funding, AMemTable.RecordCount);

  I := 0;
  while not AMemTable.Eof do
  begin
    Closes[I] := AMemTable.FieldByName('close').AsFloat;
    Highs[I] := AMemTable.FieldByName('high').AsFloat;
    Lows[I] := AMemTable.FieldByName('low').AsFloat;
    Volumes[I] := AMemTable.FieldByName('volume').AsFloat;
    Opens[I] := AMemTable.FieldByName('open').AsFloat;
    Timestamps[I] := AMemTable.FieldByName('timestamp').AsDateTime;
    OI[I] := AMemTable.FieldByName('oi').AsFloat;
    Funding[I] := AMemTable.FieldByName('funding').AsFloat;
    Inc(I);
    AMemTable.Next;
  end;
end;

class function TBacktestEngine.ExecuteBacktest(const ASymbol: string;
  ADataFull: TFDMemTable; APeriodStart, APeriodEnd: TDateTime;
  AWarmupN: Integer; AConfig: TJSONObject): TBacktestResult;
var
  Table4H, TableD: TFDMemTable;
  C1H, H1H, L1H, V1H, OI1H, F1H: TArray<Double>;
  T1H: TArray<TDateTime>;
  C4H, H4H, L4H, V4H, OI4H, F4H: TArray<Double>;
  T4H: TArray<TDateTime>;
  CD, HD, LD, VD, OID, FD: TArray<Double>;
  TD: TArray<TDateTime>;
  I, Idx4H, IdxD: Integer;
  Details: TDecisionDetails;
  Decision: Integer;
  Signal: TTradeSignal;
  Raw: Integer;
  M4H: Integer;
  EntryPrice, ExitPrice, PnL: Double;
  PnLs: TList<Double>;
  dummy1, dummy2, dummy3, dummy4, dummy5: TArray<Double>;
  dummyT: TArray<TDateTime>;
  O1H: TArray<Double>;
begin
  Result.Symbol := ASymbol;
  Result.TotalSignals := 0;
  Result.Wins := 0;
  Result.Losses := 0;
  Result.HitRate := 0;
  Result.AvgPnL := 0;
  Result.TotalPnL := 0;
  Result.LongN := 0;
  Result.ShortN := 0;
  Result.LongHR := 0;
  Result.ShortHR := 0;
  Result.MaxWin := 0;
  Result.MaxLoss := 0;
  Result.Signals := TList<TTradeSignal>.Create;
  Result.Errors := TStringList.Create;
  PnLs := TList<Double>.Create;

  Table4H := ResampleTF(ADataFull, '4h');
  TableD  := ResampleTF(ADataFull, 'D');
  try
    MemTableToArray(ADataFull, C1H, H1H, L1H, V1H, O1H, T1H, OI1H, F1H);

    MemTableToArray(Table4H, C4H, H4H, L4H, dummy1, dummy2, T4H, dummy4, dummy5);
    MemTableToArray(TableD, CD, HD, LD, dummy1, dummy2, TD, dummy4, dummy5);

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
      v_climax := StrToFloatDef(Obj.GetValue('vol_climax_mult').Value, 3.0, TFormatSettings.Invariant);
      s_trend := StrToIntDef(Obj.GetValue('score_threshold_trend').Value, 6);
      s_range := StrToIntDef(Obj.GetValue('score_threshold_range').Value, 7);
      s_start := StrToIntDef(Obj.GetValue('session_start').Value, 8);
      s_end := StrToIntDef(Obj.GetValue('session_end').Value, 20);
      e_score := StrToIntDef(Obj.GetValue('extreme_score').Value, 10);
    end;

    for I := 0 to High(T1H) do
    begin
      if I < AWarmupN then
        Continue;

      var TS := T1H[I];

      if (TS < APeriodStart) or (TS > APeriodEnd) then
        Continue;

      if I + 1 > High(T1H) then
         Break;

      while (Idx4H < High(T4H)) and (T4H[Idx4H+1] <= TS) do
        Inc(Idx4H);

      while (IdxD < High(TD)) and (TD[IdxD+1] <= TS) do
        Inc(IdxD);

      var s1h := Max(0, I + 1 - 210);
      var s4h := Max(0, Idx4H + 1 - 60);
      var sd  := Max(0, IdxD + 1 - 60);

      var wC1H := Copy(C1H, s1h, I - s1h + 1);
      var wH1H := Copy(H1H, s1h, I - s1h + 1);
      var wL1H := Copy(L1H, s1h, I - s1h + 1);
      var wV1H := Copy(V1H, s1h, I - s1h + 1);
      var wOI1H := Copy(OI1H, s1h, I - s1h + 1);

      var wC4H := Copy(C4H, s4h, Idx4H - s4h + 1);
      var wH4H := Copy(H4H, s4h, Idx4H - s4h + 1);
      var wL4H := Copy(L4H, s4h, Idx4H - s4h + 1);

      var wCD := Copy(CD, sd, IdxD - sd + 1);
      var wHD := Copy(HD, sd, IdxD - sd + 1);
      var wLD := Copy(LD, sd, IdxD - sd + 1);

      if (Length(wC4H) < 20) or (Length(wCD) < 10) then Continue;

      Raw := (HourOf(TS) * 60 + MinuteOf(TS)) mod 240;
      if Raw = 0 then
        M4H := 0
      else
        M4H := 240 - Raw;

      try
        Decision := TradingDecision(
          wC1H, wH1H, wL1H, wV1H,
          wC4H, wH4H, wL4H,
          wCD, wHD, wLD,
          Details,
          M4H, True, HourOf(TS),
          1.0, 1.0, wOI1H, F1H[I],
          'NEUTRAL',
          v_climax, s_trend, s_range, s_start, s_end, e_score
        );

        if Decision <> NO_OPEN then
        begin
          EntryPrice := O1H[I + 1];
          ExitPrice := C1H[I + 1];

          if EntryPrice > 0 then
          begin
            if Decision = LONG_POS then
            begin
              PnL := (ExitPrice - EntryPrice) / EntryPrice * 100.0;
              Signal.Decision := 'LONG';
            end
            else
            begin
              PnL := (EntryPrice - ExitPrice) / EntryPrice * 100.0;
              Signal.Decision := 'SHORT';
            end;

            if IsNaN(PnL) or IsInfinite(PnL) then
              PnL := 0;

            Signal.Timestamp := TS;
            Signal.Entry := EntryPrice;
            Signal.ExitPrice := ExitPrice;
            Signal.PnLPct := PnL;
            Signal.IsWin := PnL > 0;
            Signal.Score := Details.Score;

            Result.Signals.Add(Signal);
            PnLs.Add(PnL);

            Inc(Result.TotalSignals);
            if Signal.IsWin then
              Inc(Result.Wins)
            else
              Inc(Result.Losses);
            if Signal.Decision = 'LONG' then
              Inc(Result.LongN) else Inc(Result.ShortN);

            Result.MaxWin := Max(Result.MaxWin, PnL);
            Result.MaxLoss := Min(Result.MaxLoss, PnL);
          end;
        end;

      except
        on E: Exception do
          Result.Errors.Add(Format('%s: %s', [DateTimeToStr(TS), E.Message]));
      end;
    end;

    Result.HitRate := 0;
    Result.AvgPnL := 0;
    Result.TotalPnL := 0;
    Result.LongHR := 0;
    Result.ShortHR := 0;

    if Result.TotalSignals > 0 then
    begin
      Result.HitRate := (Result.Wins / Result.TotalSignals) * 100.0;
      for var PValue in PnLs do
        Result.TotalPnL := Result.TotalPnL + PValue;
      Result.AvgPnL := Result.TotalPnL / Result.TotalSignals;

      var LWins := 0;
      var SWins := 0;

      for var SigObj in Result.Signals do
      begin
        if SigObj.IsWin then
        begin
          if SigObj.Decision = 'LONG' then
             Inc(LWins)
          else
             Inc(SWins);
        end;
      end;

      if Result.LongN > 0 then
         Result.LongHR := (LWins / Result.LongN) * 100.0;
      if Result.ShortN > 0 then
         Result.ShortHR := (SWins / Result.ShortN) * 100.0;
    end;

    if IsNaN(Result.HitRate) or IsInfinite(Result.HitRate) then
      Result.HitRate := 0;
    if IsNaN(Result.AvgPnL) or IsInfinite(Result.AvgPnL) then
      Result.AvgPnL := 0;
    if IsNaN(Result.TotalPnL) or IsInfinite(Result.TotalPnL) then
      Result.TotalPnL := 0;
    if IsNaN(Result.LongHR) or IsInfinite(Result.LongHR) then
      Result.LongHR := 0;
    if IsNaN(Result.ShortHR) or IsInfinite(Result.ShortHR) then
      Result.ShortHR := 0;

  finally
    PnLs.Free;
    Table4H.Free;
    TableD.Free;
  end;
end;

end.
