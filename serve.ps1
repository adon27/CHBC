# Optional local server for the Office of Examinations Back Office.
#
# Why this exists: opening index.html directly (double-click / file://) works in
# some browsers but not all -- IndexedDB and other storage APIs are unreliable
# under the file:// origin in several browser configurations. This script serves
# the admin/ folder over plain HTTP on localhost using only what Windows already
# ships with (PowerShell's built-in .NET HttpListener) -- no Node.js, Python, or
# any other install required.
#
# Usage:
#   Right-click this file -> "Run with PowerShell", OR from a PowerShell prompt:
#     powershell -ExecutionPolicy Bypass -File serve.ps1
#   Then open http://localhost:8899/ in your browser.
#   Press Ctrl+C in the console window to stop the server.
param(
  [int]$Port = 8899
)

$Root = $PSScriptRoot

$mimeMap = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.svg'  = 'image/svg+xml'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Office of Examinations Back Office is running at http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop."

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $request = $context.Request
  $response = $context.Response
  try {
    $relPath = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)
    if ($relPath -eq '/') { $relPath = '/index.html' }
    $filePath = Join-Path $Root ($relPath.TrimStart('/'))
    $filePath = [System.IO.Path]::GetFullPath($filePath)

    if (-not $filePath.StartsWith([System.IO.Path]::GetFullPath($Root))) {
      $response.StatusCode = 403
      $response.Close()
      continue
    }

    if (Test-Path $filePath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
      $contentType = $mimeMap[$ext]
      if (-not $contentType) { $contentType = 'application/octet-stream' }
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $response.ContentType = $contentType
      $response.ContentLength64 = $bytes.Length
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $response.StatusCode = 404
      $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not found: $relPath")
      $response.OutputStream.Write($notFound, 0, $notFound.Length)
    }
  } catch {
    $response.StatusCode = 500
  } finally {
    $response.Close()
  }
}
