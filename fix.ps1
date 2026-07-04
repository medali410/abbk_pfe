$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding; Set-Content -Path fix.py -Value $code -Encoding UTF8
