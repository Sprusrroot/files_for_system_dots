#!/bin/bash

playerctl status -f "{{status}}" -i "chromium" --follow | while read -r status
do
    if [ "$status" == "Paused" ]; then
        echo "Нажата пауза. Выключаю комп через 5 секунд..."
        sleep 5
        CURRENT_STATUS=$(playerctl status 2>/dev/null)
        if [ "$CURRENT_STATUS" == "Paused" ]; then
            systemctl poweroff
        else
            echo "Воспроизведение возобновлено, отмена выключения."
        fi
    fi
done
