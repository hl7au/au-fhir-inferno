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
	rm -rf data/pg
	rm -rf data/redis

generate:
	$(compose) run inferno_web bundle exec rake web:generate

migrate:
	$(compose) run inferno_web /opt/inferno/migrate.sh

down_app: stop down remove_data

setup: pull build generate migrate

run: build up

full_restart: down_app setup run
