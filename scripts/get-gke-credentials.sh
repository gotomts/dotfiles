#!/bin/bash

# プロジェクト名を選択
PROJECT_ID=$(gcloud projects list --format="value(projectId)" | fzf --prompt="Select a project: ")

# 選択したプロジェクトで利用可能なクラスタ名を選択
CLUSTER_NAME=$(gcloud container clusters list --project $PROJECT_ID --format="value(name)" | fzf --prompt="Select a cluster: ")

# 選択したクラスタの認証情報を取得
gcloud container clusters get-credentials $CLUSTER_NAME --region asia-northeast1 --project $PROJECT_ID
