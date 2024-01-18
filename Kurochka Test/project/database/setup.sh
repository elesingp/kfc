#!/bin/bash

# chmod +x /workspaces/codespaces-blank/project/database/setup.sh

# Создание и активация нового окружения conda
conda create --name myenv --yes
source activate myenv

# Установка PostgreSQL
conda install -y -c conda-forge postgresql

# Инициализация и запуск сервера PostgreSQL
initdb -D db
createdb db
pg_ctl -D db -l logfile start

# Создание таблиц
\i /workspaces/codespaces-blank/project/database/test_config.sql
