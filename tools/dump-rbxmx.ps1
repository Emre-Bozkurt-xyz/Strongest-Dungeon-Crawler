# Prints a .rbxmx export as an indented tree with the layout/styling properties that matter for
# porting a Studio-authored panel to React (docs/tasks/ui-migration-plan.md).
#
# Reading the raw XML is impractical -- every property is a separate element and the file is mostly
# referents. This collapses it to one line per instance plus one line of properties, skipping
# anything left at its Roblox default.
#
#   ./tools/dump-rbxmx.ps1 -Path docs/ui/InventoryPanel.rbxmx
#
# Note: Studio Stylesheet rules are stored as base64 PropertiesSerialize blobs and are NOT decoded
# here. Panels styled that way will show their instance defaults rather than their applied look.

param([Parameter(Mandatory=$true)][string]$Path)

$xml = [xml](Get-Content -Raw -LiteralPath $Path)

function Num($v) {
  if ($null -eq $v -or "$v" -eq '') { return '0' }
  $d = [double]$v
  if ([math]::Abs($d - [math]::Round($d)) -lt 1e-6) { return [string][int][math]::Round($d) }
  return [string][math]::Round($d, 4)
}

$TOKENS = @{
  'AutomaticSize' = @{0='None';1='X';2='Y';3='XY'}
  'FillDirection' = @{0='Horizontal';1='Vertical'}
  'SortOrder' = @{0='Name';1='Custom';2='LayoutOrder'}
  'HorizontalAlignment' = @{0='Left';1='Center';2='Right'}
  'VerticalAlignment' = @{0='Top';1='Center';2='Bottom'}
  'TextXAlignment' = @{0='Left';1='Center';2='Right';3='Right'}
  'TextYAlignment' = @{0='Top';1='Center';2='Bottom'}
  'ScaleType' = @{0='Stretch';1='Slice';2='Tile';3='Fit';4='Crop'}
}

function Fmt-Prop($p) {
  $t = $p.LocalName
  switch ($t) {
    'UDim2' { return "{$(Num $p.XS),$(Num $p.XO)},{$(Num $p.YS),$(Num $p.YO)}" }
    'UDim'  { return "{$(Num $p.S),$(Num $p.O)}" }
    'Vector2' { return "($(Num $p.X),$(Num $p.Y))" }
    { $_ -eq 'Color3' -or $_ -eq 'Color3uint8' } {
      if ($null -ne $p.R -and "$($p.R)" -ne '') {
        return "rgb($([int][math]::Round([double]$p.R*255)),$([int][math]::Round([double]$p.G*255)),$([int][math]::Round([double]$p.B*255)))"
      }
      $v = [int64]"$($p.'#text')"
      return "rgb($((($v -shr 16) -band 255)),$((($v -shr 8) -band 255)),$(($v -band 255)))"
    }
    'ColorSequence' {
      $parts = ("$($p.'#text')".Trim() -split '\s+')
      $out = @()
      for ($i=0; $i+4 -lt $parts.Count; $i+=5) {
        $t0=Num $parts[$i]
        $r=[int][math]::Round([double]$parts[$i+1]*255); $g=[int][math]::Round([double]$parts[$i+2]*255); $b=[int][math]::Round([double]$parts[$i+3]*255)
        $out += "$t0=>rgb($r,$g,$b)"
      }
      return ($out -join ' ')
    }
    'NumberSequence' {
      $parts = ("$($p.'#text')".Trim() -split '\s+')
      $out = @()
      for ($i=0; $i+2 -lt $parts.Count; $i+=3) { $out += "$(Num $parts[$i])=>$(Num $parts[$i+1])" }
      return ($out -join ' ')
    }
    'token' {
      $n = $p.name; $v = "$($p.'#text')"
      if ($TOKENS.ContainsKey($n) -and $TOKENS[$n].ContainsKey([int]$v)) { return $TOKENS[$n][[int]$v] }
      return $v
    }
    'Font' { return "$($p.Family.url)" }
    'float' { return Num $p.'#text' }
    'double' { return Num $p.'#text' }
    default { return "$($p.'#text')" }
  }
}

$INTERESTING = @('Size','Position','AnchorPoint','BackgroundColor3','BackgroundTransparency',
  'Text','TextColor3','TextSize','TextScaled','TextXAlignment','TextYAlignment','FontFace','RichText',
  'Image','ImageColor3','ImageTransparency','ScaleType','Visible','LayoutOrder','ZIndex',
  'CornerRadius','Color','Thickness','Transparency','Rotation','Offset',
  'PaddingTop','PaddingBottom','PaddingLeft','PaddingRight',
  'FillDirection','SortOrder','Padding','HorizontalAlignment','VerticalAlignment','CellSize','CellPadding',
  'AutomaticSize','ClipsDescendants','BorderSizePixel','ScrollBarThickness','CanvasSize','AutomaticCanvasSize',
  'FlexMode','GridStyle','ApplyStrokeMode','LineJoinMode')

# Properties that only matter when they deviate from the Roblox default.
$SKIP_IF = @{ 'Rotation'='0'; 'ZIndex'='1'; 'LayoutOrder'='0'; 'Visible'='true'; 'ClipsDescendants'='false';
  'AutomaticSize'='None'; 'BorderSizePixel'='0'; 'AnchorPoint'='(0,0)'; 'Position'='{0,0},{0,0}';
  'RichText'='false'; 'ImageTransparency'='0'; 'ImageColor3'='rgb(255,255,255)'; 'TextSize'='14' }

function Walk($item, $depth) {
  $props = $item.Properties
  $name = ($props.string | Where-Object { $_.name -eq 'Name' }).'#text'
  $indent = '  ' * $depth
  $bits = @()

  foreach ($p in $props.ChildNodes) {
    $pn = $p.name
    if ($INTERESTING -notcontains $pn) { continue }
    $val = Fmt-Prop $p
    if ($null -eq $val -or "$val" -eq '') { continue }
    if ($SKIP_IF.ContainsKey($pn) -and $SKIP_IF[$pn] -eq "$val") { continue }
    if ($pn -eq 'BackgroundColor3' -and "$val" -eq 'rgb(255,255,255)') { continue }
    $bits += "$pn=$val"
  }

  Write-Output "$indent- $name [$($item.class)]"
  if ($bits.Count) { Write-Output "$indent    $($bits -join '  ')" }

  foreach ($child in $item.SelectNodes('Item')) { Walk $child ($depth + 1) }
}

foreach ($root in $xml.roblox.SelectNodes('Item')) { Walk $root 0 }
