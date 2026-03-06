unit uDataManager;


interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  System.Net.HttpClient, System.Net.HttpClientComponent, System.JSON,
  System.Math, System.StrUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf;

type
  TDataFetchManager = class
  private
    FCacheDir: string;
    FHTTP: TNetHTTPClient;
    FFormatSettings: TFormatSettings;
    procedure SetupMemTable(AMemTable: TFDMemTable);
    function GetVisionURL(const ACategory, ASymbol: string; AYear, AMonth: Integer; const AInterval: string = '1h'): string;
    function DownloadAndExtract(const AUrl, ACategory, AFilename: string): string;
    procedure ParseCSVToMemTable(const AFilePath: string; AMemTable: TFDMemTable; ACategory: string);
    function FetchAPIData(const ASymbol: string; AStartDate, AEndDate: TDateTime): TFDMemTable;
    function FetchAPIDerivs(const ASymbol: string; ACategory: string; AStartDate, AEndDate: TDateTime): TFDMemTable;
    procedure MergeAsof(ATarget, ASource: TFDMemTable; const ASourceField, ATargetField: string);
    function DateTimeToUnixMS(ADate: TDateTime): Int64;
    function UnixMSToDateTime(AMS: Int64): TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    
    function GetHistoricalData(const ASymbol: string; AStartDate, AEndDate: TDateTime): TFDMemTable;
    property CacheDir: string read FCacheDir;
  end;

implementation


constructor TDataFetchManager.Create;
var
  ExeDir, RootDir: string;
begin
  inherited Create;
  FHTTP := TNetHTTPClient.Create(nil);
  FHTTP.UserAgent := 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) HyperSniperD12';
  FFormatSettings := TFormatSettings.Invariant;

  ExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  FCacheDir := TPath.Combine(ExeDir, 'cache_data');

  if not TDirectory.Exists(FCacheDir) and (ExtractFileName(ExeDir).ToLower = 'tests') then
  begin
    RootDir := ExtractFilePath(ExeDir);
    if TDirectory.Exists(TPath.Combine(RootDir, 'cache_data')) then
      FCacheDir := TPath.Combine(RootDir, 'cache_data');
  end;

  TDirectory.CreateDirectory(TPath.Combine(FCacheDir, 'metrics'));
  TDirectory.CreateDirectory(TPath.Combine(FCacheDir, 'klines'));
  TDirectory.CreateDirectory(TPath.Combine(FCacheDir, 'funding'));
end;

destructor TDataFetchManager.Destroy;
begin
  FHTTP.Free;
  inherited;
end;

function TDataFetchManager.DateTimeToUnixMS(ADate: TDateTime): Int64;
begin
  Result := DateTimeToUnix(ADate, False) * 1000 + MillisecondOf(ADate);
end;

function TDataFetchManager.UnixMSToDateTime(AMS: Int64): TDateTime;
begin
  Result := UnixToDateTime(AMS div 1000, False);
  Result := IncMilliSecond(Result, AMS mod 1000);
end;

procedure TDataFetchManager.SetupMemTable(AMemTable: TFDMemTable);
begin
  AMemTable.Close;
  AMemTable.FieldDefs.Clear;
  AMemTable.FieldDefs.Add('timestamp', ftDateTime);
  AMemTable.FieldDefs.Add('open', ftFloat);
  AMemTable.FieldDefs.Add('high', ftFloat);
  AMemTable.FieldDefs.Add('low', ftFloat);
  AMemTable.FieldDefs.Add('close', ftFloat);
  AMemTable.FieldDefs.Add('volume', ftFloat);
  AMemTable.FieldDefs.Add('oi', ftFloat);
  AMemTable.FieldDefs.Add('funding', ftFloat);
  AMemTable.CreateDataSet;
  AMemTable.IndexFieldNames := 'timestamp';
end;

function TDataFetchManager.GetVisionURL(const ACategory, ASymbol: string; AYear,
  AMonth: Integer; const AInterval: string): string;
var
  CleanSym: string;
begin
  CleanSym := ASymbol.Replace('/', '').Replace(':USDT', '');
  if ACategory = 'klines' then
    Result := Format('https://data.binance.vision/data/futures/um/monthly/klines/%s/%s/%s-%s-%d-%.2d.zip',
      [CleanSym, AInterval, CleanSym, AInterval, AYear, AMonth])
  else if ACategory = 'metrics' then
    Result := Format('https://data.binance.vision/data/futures/um/monthly/metrics/%s/%s-metrics-%d-%.2d.zip',
      [CleanSym, CleanSym, AYear, AMonth])
  else if ACategory = 'funding' then
    Result := Format('https://data.binance.vision/data/futures/um/monthly/fundingRate/%s/%s-fundingRate-%d-%.2d.zip',
      [CleanSym, CleanSym, AYear, AMonth])
  else
    Result := '';
end;

function TDataFetchManager.DownloadAndExtract(const AUrl, ACategory,
  AFilename: string): string;
var
  TargetPath: string;
  LStream: TMemoryStream;
  LZip: TZipFile;
begin
  TargetPath := TPath.Combine(TPath.Combine(FCacheDir, ACategory), AFilename.Replace('.zip', '.csv'));
  if TFile.Exists(TargetPath) then
  begin
    Exit(TargetPath);
  end;

  LStream := TMemoryStream.Create;
  try
    try
      var LResp := FHTTP.Get(AUrl, LStream);

      if LResp.StatusCode = 200 then
      begin
        LZip := TZipFile.Create;
        try
          LStream.Position := 0;
          LZip.Open(LStream, zmRead);
          var ExtractedFileName := LZip.FileName[0];
          LZip.Extract(ExtractedFileName, TPath.GetDirectoryName(TargetPath), False);

          var ActualPath := TPath.Combine(TPath.GetDirectoryName(TargetPath), ExtractedFileName);
          if (ActualPath <> TargetPath) then
          begin
            if TFile.Exists(TargetPath) then TFile.Delete(TargetPath);
            TFile.Move(ActualPath, TargetPath);
          end;

          Result := TargetPath;
        finally
          LZip.Free;
        end;
      end else
      begin
        Result := '';
      end;
    except
      Result := '';
    end;
  finally
    LStream.Free;
  end;
end;

procedure TDataFetchManager.ParseCSVToMemTable(const AFilePath: string;
  AMemTable: TFDMemTable; ACategory: string);
var
  LLines: TStringList;
  I: Integer;
  LParts: TArray<string>;
  Line: string;
  ValInt: Int64;
begin
  if not TFile.Exists(AFilePath) then
  begin
    Exit;
  end;
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(AFilePath);

    for I := 0 to LLines.Count - 1 do
    begin
      Line := LLines[I].Trim;
      if Line = '' then Continue;

      if (I = 0) and ( (Pos('time', Line.ToLower) > 0) or
           (Pos('calc', Line.ToLower) > 0) ) then
          Continue;

      LParts := Line.Split([',']);
      if Length(LParts) < 2 then
        Continue;

      if ACategory = 'klines' then
      begin
        if TryStrToInt64(LParts[0], ValInt) then
        begin
          AMemTable.Append;
          AMemTable.FieldByName('timestamp').AsDateTime := UnixMSToDateTime(ValInt);
          AMemTable.FieldByName('open').AsFloat := StrToFloatDef(LParts[1], 0.0, FFormatSettings);
          AMemTable.FieldByName('high').AsFloat := StrToFloatDef(LParts[2], 0.0, FFormatSettings);
          AMemTable.FieldByName('low').AsFloat := StrToFloatDef(LParts[3], 0.0, FFormatSettings);
          AMemTable.FieldByName('close').AsFloat := StrToFloatDef(LParts[4], 0.0, FFormatSettings);
          AMemTable.FieldByName('volume').AsFloat := StrToFloatDef(LParts[5], 0.0, FFormatSettings);
          AMemTable.Post;
        end;
      end
      else if ACategory = 'metrics' then
      begin
        if TryStrToInt64(LParts[0], ValInt) then
        begin
          AMemTable.Append;
          AMemTable.FieldByName('timestamp').AsDateTime := UnixMSToDateTime(ValInt);
          if Length(LParts) > 2 then
            AMemTable.FieldByName('oi').AsFloat := StrToFloatDef(LParts[2], 0.0, FFormatSettings)
          else
            AMemTable.FieldByName('oi').AsFloat := StrToFloatDef(LParts[1], 0.0, FFormatSettings);
          AMemTable.Post;
        end;
      end
      else if ACategory = 'funding' then
      begin
        if TryStrToInt64(LParts[0], ValInt) then
        begin
          AMemTable.Append;
          AMemTable.FieldByName('timestamp').AsDateTime := UnixMSToDateTime(ValInt);
          if Length(LParts) > 2 then
            AMemTable.FieldByName('funding').AsFloat := StrToFloatDef(LParts[2], 0.0, FFormatSettings)
          else
            AMemTable.FieldByName('funding').AsFloat := StrToFloatDef(LParts[1], 0.0, FFormatSettings);
          AMemTable.Post;
        end;
      end;
    end;
  finally
    LLines.Free;
  end;
end;

procedure TDataFetchManager.MergeAsof(ATarget, ASource: TFDMemTable; const ASourceField, ATargetField: string);
var
  TargetTS, SourceTS: TDateTime;
begin
  if ASource.IsEmpty then
    Exit;

  ASource.IndexFieldNames := 'timestamp';
  ATarget.First;

  while not ATarget.Eof do
  begin
    TargetTS := ATarget.FieldByName('timestamp').AsDateTime;

    if ASource.Locate('timestamp', TargetTS, []) then
    begin
       ATarget.Edit;
       ATarget.FieldByName(ATargetField).AsFloat := ASource.FieldByName(ASourceField).AsFloat;
       ATarget.Post;
    end
    else
    begin
       ASource.First;
       SourceTS := -1;
       var LastVal: Double := 0;
       while not ASource.Eof do
       begin
         if ASource.FieldByName('timestamp').AsDateTime > TargetTS then Break;
         SourceTS := ASource.FieldByName('timestamp').AsDateTime;
         LastVal := ASource.FieldByName(ASourceField).AsFloat;
         ASource.Next;
       end;

       if SourceTS <> -1 then
       begin
         ATarget.Edit;
         ATarget.FieldByName(ATargetField).AsFloat := LastVal;
         ATarget.Post;
       end;
    end;

    ATarget.Next;
  end;
end;

function TDataFetchManager.FetchAPIDerivs(const ASymbol: string; ACategory: string;
  AStartDate, AEndDate: TDateTime): TFDMemTable;
var
  URL, CleanSym, Resp, TSKey, ValKey: string;
  LJSONArray: TJSONArray;
  I: Integer;
begin
  Result := TFDMemTable.Create(nil);
  SetupMemTable(Result);
  CleanSym := ASymbol.Replace('/', '').Replace(':USDT', '');

  if ACategory = 'metrics' then
  begin
    URL := Format('https://fapi.binance.com/futures/data/openInterestHist?symbol=%s&period=1h&startTime=%d&limit=500',
      [CleanSym, DateTimeToUnixMS(AStartDate)]);
    TSKey := 'timestamp';
    ValKey := 'sumOpenInterest';
  end
  else if ACategory = 'funding' then
  begin
    URL := Format('https://fapi.binance.com/fapi/v1/fundingRate?symbol=%s&startTime=%d&limit=1000',
      [CleanSym, DateTimeToUnixMS(AStartDate)]);
    TSKey := 'fundingTime';
    ValKey := 'fundingRate';
  end;

  try
    Resp := FHTTP.Get(URL).ContentAsString;
    LJSONArray := TJSONObject.ParseJSONValue(Resp) as TJSONArray;
    if Assigned(LJSONArray) then
    try
      for I := 0 to LJSONArray.Count - 1 do
      begin
        Result.Append;
        Result.FieldByName('timestamp').AsDateTime := UnixMSToDateTime(StrToInt64((LJSONArray.Items[I] as TJSONObject).GetValue(TSKey).Value));
        Result.FieldByName(IfThen(ACategory = 'metrics', 'oi', 'funding')).AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONObject).GetValue(ValKey).Value, FFormatSettings);
        Result.Post;
      end;
    finally
      LJSONArray.Free;
    end;
  except

  end;
end;

function TDataFetchManager.FetchAPIData(const ASymbol: string; AStartDate,
  AEndDate: TDateTime): TFDMemTable;
var
  URL, CleanSym: string;
  LResp: string;
  LJSONArray: TJSONArray;
  I: Integer;
begin
  Result := TFDMemTable.Create(nil);
  SetupMemTable(Result);
  CleanSym := ASymbol.Replace('/', '').Replace(':USDT', '');

  URL := Format('https://fapi.binance.com/fapi/v1/klines?symbol=%s&interval=1h&startTime=%d&limit=1000',
    [CleanSym, DateTimeToUnixMS(AStartDate)]);

  LResp := FHTTP.Get(URL).ContentAsString;
  LJSONArray := TJSONObject.ParseJSONValue(LResp) as TJSONArray;
  if Assigned(LJSONArray) then
  try
    for I := 0 to LJSONArray.Count - 1 do
    begin
      Result.Append;
      Result.FieldByName('timestamp').AsDateTime := UnixMSToDateTime(StrToInt64((LJSONArray.Items[I] as TJSONArray).Items[0].Value));
      Result.FieldByName('open').AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONArray).Items[1].Value, FFormatSettings);
      Result.FieldByName('high').AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONArray).Items[2].Value, FFormatSettings);
      Result.FieldByName('low').AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONArray).Items[3].Value, FFormatSettings);
      Result.FieldByName('close').AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONArray).Items[4].Value, FFormatSettings);
      Result.FieldByName('volume').AsFloat := StrToFloat((LJSONArray.Items[I] as TJSONArray).Items[5].Value, FFormatSettings);
      Result.Post;
    end;
  finally
    LJSONArray.Free;
  end;
end;

function TDataFetchManager.GetHistoricalData(const ASymbol: string; AStartDate,
  AEndDate: TDateTime): TFDMemTable;
var
  Threshold30d: TDateTime;
  Current: TDateTime;
  VisionYear, VisionMonth: Integer;
  VURL, VPath: string;
  VTableOI, VTableF: TFDMemTable;
begin
  Result := TFDMemTable.Create(nil);
  SetupMemTable(Result);

  Threshold30d := IncDay(TTimeZone.Local.ToUniversalTime(Now), -30);

  VTableOI := TFDMemTable.Create(nil);
  SetupMemTable(VTableOI);
  VTableF := TFDMemTable.Create(nil);
  SetupMemTable(VTableF);

  try
      var CleanSym := ASymbol.Replace('/', '').Replace(':USDT', '');
      Current := StartOfAMonth(YearOf(AStartDate), MonthOf(AStartDate));
      while (Current < AEndDate) and (Current < Threshold30d) do
      begin
        VisionYear := YearOf(Current);
        VisionMonth := MonthOf(Current);

        VURL := GetVisionURL('klines', ASymbol, VisionYear, VisionMonth);
        VPath := DownloadAndExtract(VURL, 'klines', Format('%s-1h-%d-%.2d.zip', [CleanSym, VisionYear, VisionMonth]));
        if VPath <> '' then ParseCSVToMemTable(VPath, Result, 'klines');

        VURL := GetVisionURL('metrics', ASymbol, VisionYear, VisionMonth);
        VPath := DownloadAndExtract(VURL, 'metrics', Format('%s-metrics-%d-%.2d.zip', [CleanSym, VisionYear, VisionMonth]));
        if VPath <> '' then
           ParseCSVToMemTable(VPath, VTableOI, 'metrics');

        VURL := GetVisionURL('funding', ASymbol, VisionYear, VisionMonth);
        VPath := DownloadAndExtract(VURL, 'funding', Format('%s-fundingRate-%d-%.2d.zip', [CleanSym, VisionYear, VisionMonth]));
        if VPath <> '' then
           ParseCSVToMemTable(VPath, VTableF, 'funding');

        Current := IncMonth(Current);
      end;

      MergeAsof(Result, VTableOI, 'oi', 'oi');
      MergeAsof(Result, VTableF, 'funding', 'funding');

      if AEndDate > Threshold30d then
      begin
        var APIStart: TDateTime;
        if AStartDate > Threshold30d then
          APIStart := AStartDate else APIStart := Threshold30d;
        var APITable := FetchAPIData(ASymbol, APIStart, AEndDate);
        try
          var API_OI := FetchAPIDerivs(ASymbol, 'metrics', APIStart, AEndDate);
          var API_F := FetchAPIDerivs(ASymbol, 'funding', APIStart, AEndDate);
          try
            MergeAsof(APITable, API_OI, 'oi', 'oi');
            MergeAsof(APITable, API_F, 'funding', 'funding');

            APITable.First;
            while not APITable.Eof do
            begin
              if not Result.Locate('timestamp', APITable.FieldByName('timestamp').Value, []) then
              begin
                Result.Append;
                Result.CopyRecord(APITable);
                Result.Post;
              end;
              APITable.Next;
            end;
          finally
            API_OI.Free;
            API_F.Free;
          end;
        finally
          APITable.Free;
        end;
      end;

  finally
    VTableOI.Free;
    VTableF.Free;
  end;

  Result.IndexFieldNames := 'timestamp';
end;

end.
