#!/usr/bin/env bash
# Trên controller: kéo image rồi deploy. Chạy trong tmux, log ở ~/logs. Chạy lại được (idempotent).
source ~/kolla-venv/bin/activate
cd ~
kolla-ansible pull -i ~/multinode 2>&1 | tee ~/logs/03-pull.log
echo PULL_EXIT=${PIPESTATUS[0]} >> ~/logs/03-pull.log
[ "$(grep -c PULL_EXIT=0 ~/logs/03-pull.log)" = 1 ] || exit 1
kolla-ansible deploy -i ~/multinode 2>&1 | tee ~/logs/04-deploy.log
echo DEPLOY_EXIT=${PIPESTATUS[0]} >> ~/logs/04-deploy.log
