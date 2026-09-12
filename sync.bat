@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: Скрипт для синхронизации файлов с гит репозиторием itdo-ios
:: Расположение: C:\путь\к\папке\itdo-ios-main\sync.bat

:: Переходим в директорию скрипта
cd /d "%~dp0"

echo 🚀 Starting synchronization with GitHub...
echo.

echo 🔍 Checking SSH connection...
ssh -T git@github.com
echo.

:: Проверяем, настроен ли origin
git remote get-url origin >nul 2>&1
if %errorlevel% neq 0 (
    echo ⚠️ Remote 'origin' not configured.
    echo 🔧 Setting up origin...
    git remote add origin git@github.com:minibleyz/itdo-ios.git
    echo ✅ Origin configured: git@github.com:minibleyz/itdo-ios.git
    echo.
) else (
    echo ✅ Remote origin configured:
    git remote get-url origin
    echo.
)

:: Определяем текущую ветку
for /f %%i in ('git rev-parse --abbrev-ref HEAD') do set CURRENT_BRANCH=%%i
echo 📍 Current branch: !CURRENT_BRANCH!
echo.

:: Добавляем все изменения
git add .
echo.

:: Проверяем, есть ли что коммитить
git diff-index --quiet HEAD --
if %errorlevel% equ 0 (
    echo ✅ No changes to commit.
) else (
    :: Создаем коммит с сообщением "Syncing code"
    git commit -m "Syncing code"
    echo 📦 Changes committed with message: Syncing code
)
echo.

:: Пушим изменения
echo 📤 Pushing to origin/!CURRENT_BRANCH!...
git push origin !CURRENT_BRANCH! --force
if %errorlevel% equ 0 (
    echo 🎉 Successfully pushed to GitHub!
) else (
    echo ❌ Error: Failed to push changes.
    echo.
    echo Possible solutions:
    echo 1. Check your internet connection
    echo 2. Verify SSH key: ssh -T git@github.com
    echo 3. Make sure you have write access to the repository
    echo 4. Try: git pull origin !CURRENT_BRANCH! --rebase
)
echo.

echo ✨ Synchronization complete.
echo.
echo ⏳ Window will close automatically in 60 seconds...
echo Press Ctrl+C to close immediately.

:: Ждем 60 секунд
ping 127.0.0.1 -n 61 >nul