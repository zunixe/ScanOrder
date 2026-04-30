# Generate ScanOrder icon PNG from scratch using System.Drawing
Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

# Background (blue gradient simulation - solid blue)
$bgRect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(37, 99, 235))
$g.FillRectangle($bgBrush, $bgRect)

# Corner scanner frame (white, stroke width ~24 scaled to 1024)
$cornerLen = 120
$cornerOff = 180
$penWhite = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 24)
$penWhite.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$penWhite.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

# Top-left
$g.DrawLine($penWhite, $cornerOff, $cornerOff + $cornerLen, $cornerOff, $cornerOff)
$g.DrawLine($penWhite, $cornerOff, $cornerOff, $cornerOff + $cornerLen, $cornerOff)
# Top-right
$g.DrawLine($penWhite, $size - $cornerOff - $cornerLen, $cornerOff, $size - $cornerOff, $cornerOff)
$g.DrawLine($penWhite, $size - $cornerOff, $cornerOff, $size - $cornerOff, $cornerOff + $cornerLen)
# Bottom-left
$g.DrawLine($penWhite, $cornerOff, $size - $cornerOff - $cornerLen, $cornerOff, $size - $cornerOff)
$g.DrawLine($penWhite, $cornerOff, $size - $cornerOff, $cornerOff + $cornerLen, $size - $cornerOff)
# Bottom-right
$g.DrawLine($penWhite, $size - $cornerOff - $cornerLen, $size - $cornerOff, $size - $cornerOff, $size - $cornerOff)
$g.DrawLine($penWhite, $size - $cornerOff, $size - $cornerOff, $size - $cornerOff, $size - $cornerOff - $cornerLen)

# Package box
$boxX = 392
$boxY = 392
$boxW = 240
$boxH = 200
$boxRect = New-Object System.Drawing.Rectangle($boxX, $boxY, $boxW, $boxH)
$boxBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 245, 255))
$g.FillRectangle($boxBrush, $boxRect)

# Box top flap (triangle simulation with polygon)
$flapPoints = @(
    New-Object System.Drawing.Point($boxX, $boxY),
    New-Object System.Drawing.Point($boxX + $boxW/2, $boxY - 60),
    New-Object System.Drawing.Point($boxX + $boxW, $boxY)
)
$g.FillPolygon($boxBrush, $flapPoints)

# Box border
$boxPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 200, 220), 4)
$g.DrawRectangle($boxPen, $boxRect)

# Barcode lines on box
$barY = 452
$barH = 40
$barPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(37, 99, 235), 6)
$barStarts = @(416, 448, 464, 512, 552, 576, 592)
foreach ($bx in $barStarts) {
    $g.DrawLine($barPen, $bx, $barY, $bx, $barY + $barH)
}

# Tape strip
$tapeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(37, 99, 235))
$tapeRect = New-Object System.Drawing.Rectangle(502, 332, 20, 260)
$g.FillRectangle($tapeBrush, $tapeRect)

# Laser line (red)
$laserPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(239, 68, 68), 16)
$laserPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$laserPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$laserY = 512
$g.DrawLine($laserPen, $cornerOff - 20, $laserY, $size - $cornerOff + 20, $laserY)

# Laser glow (circle)
$glowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 239, 68, 68))
$g.FillEllipse($glowBrush, 496, 496, 32, 32)

# Text
$font = New-Object System.Drawing.Font("Segoe UI", 96, [System.Drawing.FontStyle]::Bold)
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 255, 255, 255))
$textRect = New-Object System.Drawing.RectangleF(0, 840, $size, 120)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString("ScanOrder", $font, $textBrush, $textRect, $sf)

# Save
$outputPath = "assets\logo\scanorder_icon.png"
$bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Icon saved to $outputPath"

$g.Dispose()
$bmp.Dispose()
