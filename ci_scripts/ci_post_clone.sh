#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# CoreML 모델은 용량 때문에 비공개 저장소(moa-models)에 있다 — 읽기 전용 토큰으로 받는다
git clone --depth 1 "https://csh1063:${MODELS_REPO_TOKEN}@github.com/csh1063/moa-models.git" Projects/Data/Resources/Models

# Firebase 설정 파일은 git에 없어서 비밀 환경변수로 받는다
echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > Projects/App/SupportingFiles/GoogleService-Info.plist

# .xcworkspace를 커밋하지 않아서 tuist로 생성한다
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
mise exec tuist@4.44.3 -- tuist install
mise exec tuist@4.44.3 -- tuist generate --no-open
