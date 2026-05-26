@echo off
set "GIT_PATH=C:\Program Files\Git\cmd"
set "FLUTTER_PATH=C:\flutter\bin"
set "PATH=%PATH%;%GIT_PATH%;%FLUTTER_PATH%"
echo Path updated for this session.
git --version
flutter --version
flutter doctor
