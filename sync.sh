#!/bin/bash

# Скрипт для синхронизации файлов с гит репозиторием itdo-ios
# Расположение: /home/bleyzos/Загрузки/mimoclaw_workspace (1)/itdo-ios-main/itdo-ios-main/sync.sh

# Переходим в директорию скрипта
cd "$(dirname "$0")"

echo "🚀 Starting synchronization with GitHub..."

echo "🔍 Checking SSH connection..."
ssh -T git@github.com

# Добавляем все изменения
git add .

# Проверяем, есть ли что коммитить
if git diff-index --quiet HEAD --; then
    echo "✅ No changes to commit."
else
    # Создаем коммит с уникальным ID для запуска Workflow
    COMMIT_ID=$(date +%s)
    git commit -m "Sync files from workspace [#$COMMIT_ID]"
    echo "📦 Changes committed with ID: $COMMIT_ID"
fi

# Пушим изменения в текущую ветку (принудительно, чтобы синхронизировать с воркспейсом)
if git push origin $(git rev-parse --abbrev-ref HEAD) --force; then
    echo "🎉 Successfully pushed to GitHub!"
else
    echo "❌ Error: Failed to push changes. Check your connection or permissions."
    exit 1
fi

echo "✨ Synchronization complete."
