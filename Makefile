compose = docker compose

.PHONY: setup run down full_restart

pull:
	$(compose) pull

build:
	$(compose) build

up:
	$(compose) up

stop:
	$(compose) stop

down:
	$(compose) down

remove_data:
	sudo rm -rf data/pg
	sudo rm -rf data/redis

generate:
	$(compose) -f compose.generate.yml run inferno bundle exec rake web:generate

generate_dev:
	$(compose) -f compose.generate.yml run inferno bundle exec rake web:generate_dev

generate_prod:
	$(compose) -f compose.generate.yml run inferno bundle exec rake web:generate_prod

migrate:
	$(compose) run inferno_web /opt/inferno/migrate.sh

down_app: stop down remove_data

setup: pull build generate migrate

setup_dev: pull build generate_dev migrate

setup_prod: pull build generate_prod migrate

run: build up

full_restart: down_app setup run

full_restart_dev: down_app setup_dev run

full_restart_prod: down_app setup_prod run

serve_dev_local:
	bundle exec rake web:serve_dev

open_generated:
	open _site/index.html