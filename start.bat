@echo off
REM =============================================================================
REM RamiBot — Daily startup (Windows)
REM Usage: Double-click or run from cmd: start.bat
REM =============================================================================
cd /d "%~dp0"
set "PATH=%ProgramFiles%\Docker\Docker\resources\bin;%ProgramFiles%\nodejs;%LocalAppData%\Programs\Python\Python312;%LocalAppData%\Programs\Python\Python312\Scripts;%PATH%"

echo.
echo [ramibot] ============================================================
echo [ramibot]  Starting RamiBot
echo [ramibot] ============================================================
echo.

REM =============================================================================
REM 1. Sanity checks
REM =============================================================================
echo [ramibot] Running sanity checks...

if not exist "backend\.venv\" (
    echo [ramibot] ERROR: backend\.venv not found - run install.bat first.
    goto :fail
)

if not exist "backend\settings.json" (
    echo [ramibot] ERROR: backend\settings.json not found - run install.bat first.
    goto :fail
)

if not exist "frontend\node_modules\" (
    echo [ramibot] ERROR: frontend\node_modules not found - run install.bat first.
    goto :fail
)

if not exist "osiris\node_modules\" (
    echo [ramibot] First-run Osiris files are missing - running install.bat...
    call install.bat
    if errorlevel 1 goto :fail
)

echo [ramibot] Sanity checks passed.
echo.

REM =============================================================================
REM 2. Ensure Docker Desktop is running
REM =============================================================================
echo [ramibot] Checking Docker daemon...
docker info >nul 2>&1
if not errorlevel 1 goto :docker_ready

echo [ramibot]   Docker not running - starting Docker Desktop...
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
echo [ramibot]   Waiting for Docker to start (up to 60s)...

:wait_docker
timeout /t 3 /nobreak >nul
docker info >nul 2>&1
if not errorlevel 1 goto :docker_ready
set /a DOCKER_WAITED+=3
if %DOCKER_WAITED% LSS 60 goto :wait_docker
echo [ramibot] ERROR: Docker did not start in time. Open Docker Desktop manually and re-run.
goto :fail

:docker_ready
echo [ramibot]   Docker daemon running ... OK
echo.

REM =============================================================================
REM 3. Ensure Docker Compose is available
REM =============================================================================
set "COMPOSE_CMD="
docker compose version >nul 2>&1
if not errorlevel 1 (
    set "COMPOSE_CMD=docker compose"
    goto :compose_ready
)
docker-compose --version >nul 2>&1
if not errorlevel 1 (
    set "COMPOSE_CMD=docker-compose"
    goto :compose_ready
)
echo [ramibot] ERROR: Docker Compose not found. Update Docker Desktop.
goto :fail

:compose_ready

REM =============================================================================
REM 4. Ensure the repository-local GGUF model and server are running
REM =============================================================================
echo [ramibot] Checking repository-local G9v3-3B Heretic Q8_0 model...
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup-gguf.ps1
if errorlevel 1 (
    echo [ramibot] ERROR: Failed to download or verify the GGUF model.
    goto :fail
)

echo [ramibot] Starting local llama.cpp server...
%COMPOSE_CMD% -f compose.gguf.yaml up -d
if errorlevel 1 (
    echo [ramibot] ERROR: Failed to start the local GGUF server.
    goto :fail
)
echo [ramibot]   GGUF server started on http://127.0.0.1:1234.
echo.

REM =============================================================================
REM 5. Start Osiris from this checkout (no second Docker service)
REM =============================================================================
echo [ramibot] Starting Osiris on http://127.0.0.1:3000/osiris/ ...
start "RamiBot Osiris" cmd /k "cd /d "%~dp0osiris" && npm run dev -- --hostname 0.0.0.0 --port 3000"

REM =============================================================================
REM 6. Ensure rami-kali container is running
REM =============================================================================
echo [ramibot] Starting rami-kali container...
%COMPOSE_CMD% -f rami-kali\docker-compose.yml up -d
if errorlevel 1 (
    echo [ramibot] ERROR: Failed to start rami-kali container.
    goto :fail
)

echo [ramibot] Waiting for rami-kali to be ready (this may take several minutes on first run)...
:wait_kali
timeout /t 3 /nobreak >nul
docker ps --filter "name=rami-kali" --filter "status=running" > "%TEMP%\rami_ps.txt" 2>&1
findstr /c:"rami-kali" "%TEMP%\rami_ps.txt" >nul 2>&1
if not errorlevel 1 goto :container_ready
goto :wait_kali

:container_ready
echo [ramibot]   rami-kali is ready.
echo.

REM =============================================================================
REM 7. Start backend in a new terminal window
REM =============================================================================
echo [ramibot] Starting backend on http://localhost:8001 ...
start "RamiBot Backend" cmd /k "cd /d "%~dp0backend" && call .venv\Scripts\activate.bat && python -m uvicorn main:app --reload --host 0.0.0.0 --port 8001"

REM =============================================================================
REM 8. Start frontend in a new terminal window
REM =============================================================================
echo [ramibot] Starting frontend on http://localhost:5173 ...
start "RamiBot Frontend" cmd /k "cd /d "%~dp0frontend" && call npm run dev"

REM =============================================================================
REM 9. Start ngrok public UI tunnel
REM =============================================================================
echo [ramibot] Starting ngrok tunnel for the RamiBot UI...
start "RamiBot ngrok" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-ngrok.ps1"

REM =============================================================================
REM 10. Open browser after delay and print public URL
REM =============================================================================
echo [ramibot] Waiting for services in 12 seconds...
timeout /t 12 /nobreak >nul
start "" "http://localhost:5173"
set "PUBLIC_URL="
for /f "delims=" %%u in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\get-ngrok-url.ps1"') do set "PUBLIC_URL=%%u"

REM =============================================================================
REM Done
REM =============================================================================
echo.
echo [ramibot] ============================================================
echo [ramibot]  RamiBot is starting up!
echo [ramibot] ============================================================
echo.
echo   Backend:   http://localhost:8001/docs
echo   Frontend:  http://localhost:5173
echo   Osiris:    embedded in the RamiBot panel
if defined PUBLIC_URL echo   Public UI: %PUBLIC_URL%
echo.
echo   Close the Backend / Frontend terminal windows to stop those services.
echo   rami-kali container stays running in the background.
echo.
pause
exit /b 0

:fail
echo.
echo [ramibot] Fix the error above and re-run start.bat
echo.
pause
exit /b 1
